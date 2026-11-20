const db = require('../config/db');

// A rail waitlist estimate below this percentage is considered low.
const LOW_PROBABILITY_THRESHOLD_PERCENT = 30;
const MAX_SUGGESTIONS = 4;

function isLowProbability(estimate) {
  return Boolean(estimate?.canEstimate)
    && Number.isFinite(Number(estimate.probabilityPercent))
    && Number(estimate.probabilityPercent) < LOW_PROBABILITY_THRESHOLD_PERCENT;
}

function roundMoney(value) {
  return Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100;
}

async function getPassengerLoyalty(passengerId) {
  const fallback = {
    points: 0,
    tier: 'BASIC',
    discountPercent: 0
  };

  try {
    const [rows] = await db.query(
      `SELECT loyalty_points, tier,
              airline_db.fn_air_loyalty_discount_percent(loyalty_points) AS discount_percent
       FROM railway_db.users
       WHERE user_id = ?
       LIMIT 1`,
      [passengerId]
    );

    if (!rows.length) return fallback;

    return {
      points: Number(rows[0].loyalty_points || 0),
      tier: rows[0].tier || 'BASIC',
      discountPercent: Number(rows[0].discount_percent || 0)
    };

  } catch (error) {
    console.warn(
      `Could not load loyalty preview for flight alternatives: ${error.code || error.message}`
    );

    return fallback;
  }
}

/**
 * Returns same-day direct flights between the cities represented
 * by the selected railway stations.
 *
 * Only flights with currently available confirmed seats are returned.
 */
async function findAvailableFlights({
  journeyDate,
  originStationId,
  destinationStationId,
  passengerId,
  referenceFare = null
}) {

  const base = {
    available: false,
    referenceFare: Number.isFinite(Number(referenceFare))
      ? Number(referenceFare)
      : null,

    flights: [],

    loyalty: {
      points: 0,
      tier: 'BASIC',
      flight_discount_percent: 0
    }
  };

  if (!journeyDate || !originStationId || !destinationStationId) {
    return {
      ...base,
      message: 'A valid route and journey date are required to find flight alternatives.'
    };
  }

  const loyalty = await getPassengerLoyalty(passengerId);

  let rows;

  try {

    [rows] = await db.query(`
      SELECT
        fs.flight_schedule_id,
        fs.flight_date,
        f.flight_number,
        al.airline_name,

        TIME_FORMAT(f.departure_time, '%H:%i') AS departure_time,
        TIME_FORMAT(f.arrival_time, '%H:%i') AS arrival_time,

        o.iata_code AS origin_code,
        o.airport_name AS origin_airport,
        o.city AS origin_city,

        d.iata_code AS destination_code,
        d.airport_name AS destination_airport,
        d.city AS destination_city,

        fr.cabin_class,

        COUNT(DISTINCT seat.flight_seat_id) AS total_seats,

        COUNT(DISTINCT alloc.flight_seat_id) AS occupied_seats,

        airline_db.fn_air_fare(
          fs.flight_schedule_id,
          fr.cabin_class
        ) AS base_fare

      FROM airline_db.flight_schedules fs

      JOIN airline_db.flights f
        ON f.flight_id = fs.flight_id

      JOIN airline_db.airlines al
        ON al.airline_id = f.airline_id

      JOIN airline_db.fare_rules fr
        ON fr.flight_id = f.flight_id

      JOIN airline_db.airports o
        ON o.airport_id = f.origin_airport_id

      JOIN airline_db.airports d
        ON d.airport_id = f.destination_airport_id

      JOIN railway_db.stations so
        ON so.station_id = ?
       AND LOWER(TRIM(so.city)) = LOWER(TRIM(o.city))

      JOIN railway_db.stations sd
        ON sd.station_id = ?
       AND LOWER(TRIM(sd.city)) = LOWER(TRIM(d.city))

      LEFT JOIN airline_db.flight_seats seat
        ON seat.flight_schedule_id = fs.flight_schedule_id
       AND seat.cabin_class = fr.cabin_class

      LEFT JOIN airline_db.air_seat_allocations alloc
        ON alloc.flight_schedule_id = fs.flight_schedule_id
       AND alloc.flight_seat_id = seat.flight_seat_id

      WHERE fs.flight_date = ?
        AND fs.flight_date >= CURDATE()
        AND (
          fs.flight_date > CURDATE()
          OR f.departure_time > CURTIME()
        )
        AND fs.schedule_status IN ('SCHEDULED', 'DELAYED')

      GROUP BY
        fs.flight_schedule_id,
        fs.flight_date,
        f.flight_number,
        al.airline_name,
        f.departure_time,
        f.arrival_time,
        o.iata_code,
        o.airport_name,
        o.city,
        d.iata_code,
        d.airport_name,
        d.city,
        fr.cabin_class

      HAVING
        COUNT(DISTINCT seat.flight_seat_id)
        >
        COUNT(DISTINCT alloc.flight_seat_id)

      ORDER BY
        base_fare ASC,
        f.departure_time ASC

      LIMIT 30
    `, [
      originStationId,
      destinationStationId,
      journeyDate
    ]);

  } catch (error) {

    console.warn(
      `Flight alternatives unavailable: ${error.code || error.message}`
    );

    return {
      ...base,
      message: 'Flight suggestions could not be loaded. Check that the Airways database and its flight schedules are installed.'
    };
  }

  const reference = Number(referenceFare);

  const flights = rows
    .map((row) => {

      const baseFare = roundMoney(row.base_fare);

      const discountAmount = roundMoney(
        baseFare * loyalty.discountPercent / 100
      );

      const finalFare = Math.max(
        0,
        roundMoney(baseFare - discountAmount)
      );

      const seatsLeft = Math.max(
        0,
        Number(row.total_seats) - Number(row.occupied_seats)
      );

      return {
        flight_schedule_id: Number(row.flight_schedule_id),

        flight_number: row.flight_number,
        airline_name: row.airline_name,

        flight_date: row.flight_date,

        departure_time: row.departure_time,
        arrival_time: row.arrival_time,

        origin_code: row.origin_code,
        origin_airport: row.origin_airport,
        origin_city: row.origin_city,

        destination_code: row.destination_code,
        destination_airport: row.destination_airport,
        destination_city: row.destination_city,

        cabin_class: row.cabin_class,

        total_seats: Number(row.total_seats),
        occupied_seats: Number(row.occupied_seats),
        seats_left: seatsLeft,

        base_fare: baseFare,

        loyalty_points: loyalty.points,
        loyalty_tier: loyalty.tier,

        loyalty_discount_percent: loyalty.discountPercent,
        loyalty_discount_amount: discountAmount,

        fare: finalFare,
        final_fare: finalFare,

        price_difference:
          Number.isFinite(reference) && reference > 0
            ? Number((finalFare - reference).toFixed(2))
            : null,

        price_difference_percent:
          Number.isFinite(reference) && reference > 0
            ? Number(
                (((finalFare - reference) / reference) * 100).toFixed(1)
              )
            : null
      };
    })

    .filter((flight) =>
      flight.seats_left > 0 &&
      Number.isFinite(flight.fare) &&
      flight.fare > 0
    )

    .sort((a, b) =>
      a.fare - b.fare ||
      a.departure_time.localeCompare(b.departure_time)
    )

    .slice(0, MAX_SUGGESTIONS);

  return {
    available: true,

    referenceFare:
      Number.isFinite(reference) && reference > 0
        ? reference
        : null,

    flights,

    loyalty: {
      points: loyalty.points,
      tier: loyalty.tier,
      flight_discount_percent: loyalty.discountPercent
    },

    message: flights.length
      ? 'These same-day flights have confirmed seats available. Compare departure times, cabin classes and the final fare after your loyalty discount.'
      : 'No same-day flight with an available confirmed seat was found for the selected city pair.'
  };
}


/**
 * Called when a railway booking has a low historical
 * confirmation probability.
 */
async function suggestFlights({
  railFare,
  journeyDate,
  originStationId,
  destinationStationId,
  passengerId
}) {

  const alternatives = await findAvailableFlights({
    referenceFare: railFare,
    journeyDate,
    originStationId,
    destinationStationId,
    passengerId
  });

  return {
    ...alternatives,

    triggered: true,

    reason: 'LOW_RAIL_CONFIRMATION_PROBABILITY',

    thresholdPercent: LOW_PROBABILITY_THRESHOLD_PERCENT,

    referenceFare: Number(railFare),

    message: alternatives.flights?.length
      ? 'Your train confirmation probability is low. These same-day flights have available confirmed seats; compare the final fares before choosing.'
      : alternatives.message
  };
}


/**
 * Called during railway search when matching trains
 * are full or no train service is available.
 */
async function suggestFlightsForTrainSearch({
  journeyDate,
  originStationId,
  destinationStationId,
  passengerId,
  referenceFare = null,
  message
}) {

  const alternatives = await findAvailableFlights({
    journeyDate,
    originStationId,
    destinationStationId,
    passengerId,
    referenceFare
  });

  return {
    ...alternatives,

    triggered: true,

    reason: 'TRAIN_CAPACITY_OR_NO_SERVICE',

    message: alternatives.flights?.length
      ? (message || alternatives.message)
      : alternatives.message
  };
}


module.exports = {
  suggestFlights,
  suggestFlightsForTrainSearch,
  isLowProbability,
  LOW_PROBABILITY_THRESHOLD_PERCENT
};