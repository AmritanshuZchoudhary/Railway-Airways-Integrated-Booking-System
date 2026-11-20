const db = require('../config/db');
const flightAlternatives = require('../services/flightAlternativeService');

const VALID_CLASSES = new Set([
  'SLEEPER',
  'AC',
  'CHAIR_CAR'
]);

// Get all railway stations for the search dropdowns.
exports.listStations = async (_req, res, next) => {
  try {
    const [rows] = await db.query(
      `SELECT station_id, station_code, station_name, city
       FROM stations
       ORDER BY city, station_name`
    );

    return res.json({ stations: rows });

  } catch (error) {
    return next(error);
  }
};


// Search trains and check their seat availability.
// If trains are full or unavailable, suggest available flights.
exports.searchSchedules = async (req, res, next) => {
  try {
    const originId = Number(req.query.origin_station_id);
    const destinationId = Number(req.query.destination_station_id);

    const journeyDate = String(req.query.journey_date || '');

    const classType = String(
      req.query.class_type || 'SLEEPER'
    ).toUpperCase();


    // Validate station selection.
    if (
      !Number.isInteger(originId) ||
      originId < 1 ||
      !Number.isInteger(destinationId) ||
      destinationId < 1
    ) {
      return res.status(400).json({
        error: 'Choose both an origin and destination station.'
      });
    }

    if (originId === destinationId) {
      return res.status(400).json({
        error: 'Origin and destination must be different.'
      });
    }


    // Validate journey date.
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(journeyDate) ||
      Number.isNaN(Date.parse(`${journeyDate}T00:00:00Z`))
    ) {
      return res.status(400).json({
        error: 'Choose a valid journey date.'
      });
    }


    // Validate travel class.
    if (!VALID_CLASSES.has(classType)) {
      return res.status(400).json({
        error: 'Choose a supported travel class.'
      });
    }


    // Restrict searches to the next 30 days.
    const [dateWindow] = await db.query(
      `SELECT (
        ? >= CURDATE()
        AND ? <= DATE_ADD(CURDATE(), INTERVAL 29 DAY)
      ) AS in_range`,
      [journeyDate, journeyDate]
    );

    if (!Number(dateWindow[0]?.in_range)) {
      return res.status(400).json({
        error: 'Choose a journey date within the next 30 days.'
      });
    }


    // Retrieve every matching train and calculate seat availability.
    const sql = `
      SELECT
        s.schedule_id,
        s.journey_date,

        TIME_FORMAT(
          s.departure_time, '%H:%i'
        ) AS departure_time,

        TIME_FORMAT(
          s.arrival_time, '%H:%i'
        ) AS arrival_time,

        s.base_fare,

        t.train_id,
        t.train_number,
        t.train_name,

        r.route_id,

        o.station_id AS origin_station_id,
        o.station_name AS origin_station,
        o.city AS origin_city,

        d.station_id AS destination_station_id,
        d.station_name AS destination_station,
        d.city AS destination_city,

        ? AS class_type,

        COUNT(DISTINCT seat.seat_id) AS total_seats,

        COUNT(DISTINCT alloc.seat_id) AS occupied_seats,

        COUNT(DISTINCT seat.seat_id)
          - COUNT(DISTINCT alloc.seat_id) AS available_seats

      FROM train_schedules s

      JOIN train_routes r
        ON r.route_id = s.route_id

      JOIN trains t
        ON t.train_id = r.train_id
        AND t.status = 'ACTIVE'

      JOIN stations o
        ON o.station_id = r.origin_station_id

      JOIN stations d
        ON d.station_id = r.destination_station_id

      LEFT JOIN train_seats seat
        ON seat.train_id = t.train_id
        AND seat.class_type = ?

      LEFT JOIN seat_allocations alloc
        ON alloc.schedule_id = s.schedule_id
        AND alloc.seat_id = seat.seat_id

      WHERE
        r.origin_station_id = ?
        AND r.destination_station_id = ?

        AND s.journey_date = ?

        AND s.journey_date BETWEEN
          CURDATE()
          AND DATE_ADD(CURDATE(), INTERVAL 29 DAY)

        AND (
          s.journey_date > CURDATE()
          OR s.departure_time > CURTIME()
        )

        AND s.booking_status = 'OPEN'

      GROUP BY
        s.schedule_id,
        s.journey_date,
        s.departure_time,
        s.arrival_time,
        s.base_fare,

        t.train_id,
        t.train_number,
        t.train_name,

        r.route_id,

        o.station_id,
        o.station_name,
        o.city,

        d.station_id,
        d.station_name,
        d.city

      HAVING COUNT(DISTINCT seat.seat_id) > 0

      ORDER BY s.departure_time ASC
    `;


    const [schedules] = await db.query(sql, [
      classType,
      classType,
      originId,
      destinationId,
      journeyDate
    ]);


    // Calculate railway availability.
    const fullTrainCount = schedules.filter(
      item => Number(item.available_seats) <= 0
    ).length;

    const availableTrainCount = schedules.filter(
      item => Number(item.available_seats) > 0
    ).length;


    // Default flight suggestion response.
    let flightSuggestions = {
      triggered: false,
      available: true,
      flights: []
    };


    // Suggest flights if no trains exist or at least one
    // matching train option is completely full.
    if (schedules.length === 0 || fullTrainCount > 0) {

      const validFares = schedules
        .map(item => Number(item.base_fare))
        .filter(
          fare => Number.isFinite(fare) && fare > 0
        );

      const referenceFare = validFares.length
        ? Math.min(...validFares)
        : null;


      let message;

      if (schedules.length === 0) {

        message =
          'No train services matched this route and date. Here are same-day flights with available seats.';

      } else if (availableTrainCount > 0) {

        message =
          `${fullTrainCount} train option(s) are full. Other train options with available seats remain listed above; you can also compare these same-day flights.`;

      } else {

        message =
          'All matching train options for this class are full. Compare these same-day flights with available seats.';

      }


      // Find flight alternatives for the same journey.
      flightSuggestions =
        await flightAlternatives.suggestFlightsForTrainSearch({
          journeyDate,

          originStationId: originId,

          destinationStationId: destinationId,

          passengerId: req.user_id,

          referenceFare:
            Number.isFinite(referenceFare)
              ? referenceFare
              : null,

          message
        });
    }


    // Return train options and flight alternatives together.
    return res.json({

      schedules,

      flightAlternatives: flightSuggestions,

      trainAvailability: {

        totalOptions: schedules.length,

        availableOptions: availableTrainCount,

        fullOptions: fullTrainCount

      },

      search: {

        origin_station_id: originId,

        destination_station_id: destinationId,

        journey_date: journeyDate,

        class_type: classType

      }

    });

  } catch (error) {

    return next(error);

  }
};