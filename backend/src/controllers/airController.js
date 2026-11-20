const db = require('../config/db');
const airProbabilityService = require('../services/airProbabilityService');
const VALID_CABINS = new Set(['ECONOMY', 'BUSINESS']);

function roundMoney(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function isSqlRule(error) {
  return error.sqlState === '45000' || error.code === 'ER_SIGNAL_EXCEPTION';
}

exports.listAirports = async (_req, res, next) => {
  try {
    const [rows] = await db.query(
      'SELECT airport_id, iata_code, airport_name, city FROM airline_db.airports ORDER BY city, airport_name'
    );
    return res.json({ airports: rows });
  } catch (error) { return next(error); }
};

exports.searchFlights = async (req, res, next) => {
  try {
    const originId = Number(req.query.origin_airport_id);
    const destinationId = Number(req.query.destination_airport_id);
    const flightDate = String(req.query.flight_date || '');
    const cabin = String(req.query.cabin_class || 'ECONOMY').toUpperCase();

    if (!Number.isInteger(originId) || originId < 1 || !Number.isInteger(destinationId) || destinationId < 1) {
      return res.status(400).json({ error: 'Choose both an origin and destination airport.' });
    }
    if (originId === destinationId) return res.status(400).json({ error: 'Origin and destination must be different.' });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(flightDate) || Number.isNaN(Date.parse(`${flightDate}T00:00:00Z`))) {
      return res.status(400).json({ error: 'Choose a valid flight date.' });
    }
    if (!VALID_CABINS.has(cabin)) return res.status(400).json({ error: 'Choose a supported cabin class.' });

    const [dateWindow] = await db.query(
      'SELECT (? >= CURDATE() AND ? <= DATE_ADD(CURDATE(), INTERVAL 29 DAY)) AS in_range',
      [flightDate, flightDate]
    );
    if (!Number(dateWindow[0]?.in_range)) {
      return res.status(400).json({ error: 'Choose a flight date within the next 30 days.' });
    }

    // Use the passenger's current shared loyalty balance to preview the flight-only tier discount.
    const [loyaltyRows] = await db.query(
      `SELECT loyalty_points, tier, airline_db.fn_air_loyalty_discount_percent(loyalty_points) AS flight_discount_percent
       FROM railway_db.users WHERE user_id = ? LIMIT 1`,
      [req.user_id]
    );
    if (!loyaltyRows.length) return res.status(404).json({ error: 'Passenger account was not found.' });
    const loyaltyAccount = loyaltyRows[0];

    // Base fare includes the existing dynamic occupancy/time pricing; loyalty discount is applied after it.
    const sql = `
      SELECT
        fs.flight_schedule_id, fs.flight_date, fs.schedule_status, fs.overbook_limit,
        f.flight_id, f.flight_number, al.airline_name,
        TIME_FORMAT(f.departure_time, '%H:%i') AS departure_time,
        TIME_FORMAT(f.arrival_time, '%H:%i') AS arrival_time,
        o.airport_id AS origin_airport_id, o.iata_code AS origin_code, o.airport_name AS origin_airport, o.city AS origin_city,
        d.airport_id AS destination_airport_id, d.iata_code AS destination_code, d.airport_name AS destination_airport, d.city AS destination_city,
        ? AS cabin_class,
        COUNT(DISTINCT seat.flight_seat_id) AS total_seats,
        COUNT(DISTINCT alloc.flight_seat_id) AS occupied_seats,
        COUNT(DISTINCT seat.flight_seat_id) - COUNT(DISTINCT alloc.flight_seat_id) AS available_seats,
        (SELECT COUNT(*) FROM airline_db.air_standby_entries e
           WHERE e.flight_schedule_id = fs.flight_schedule_id AND e.cabin_class = ? AND e.status = 'WAITING') AS standby_waiting,
        airline_db.fn_air_fare(fs.flight_schedule_id, ?) AS base_fare
      FROM airline_db.flight_schedules fs
      JOIN airline_db.flights f ON f.flight_id = fs.flight_id
      JOIN airline_db.airlines al ON al.airline_id = f.airline_id
      JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
      JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id
      LEFT JOIN airline_db.flight_seats seat ON seat.flight_schedule_id = fs.flight_schedule_id AND seat.cabin_class = ?
      LEFT JOIN airline_db.air_seat_allocations alloc ON alloc.flight_schedule_id = fs.flight_schedule_id AND alloc.flight_seat_id = seat.flight_seat_id
      WHERE f.origin_airport_id = ? AND f.destination_airport_id = ?
        AND fs.flight_date = ?
        AND fs.flight_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY)
        AND (fs.flight_date > CURDATE() OR f.departure_time > CURTIME())
        AND fs.schedule_status IN ('SCHEDULED', 'DELAYED')
      GROUP BY fs.flight_schedule_id, fs.flight_date, fs.schedule_status, fs.overbook_limit,
        f.flight_id, f.flight_number, al.airline_name, f.departure_time, f.arrival_time,
        o.airport_id, o.iata_code, o.airport_name, o.city, d.airport_id, d.iata_code, d.airport_name, d.city
      HAVING COUNT(DISTINCT seat.flight_seat_id) > 0
      ORDER BY f.departure_time ASC`;
    const [rows] = await db.query(sql, [cabin, cabin, cabin, cabin, originId, destinationId, flightDate]);
    const discountPercent = Number(loyaltyAccount.flight_discount_percent || 0);
    const flights = rows.map((row) => {
      const baseFare = roundMoney(row.base_fare);
      const discountAmount = roundMoney(baseFare * discountPercent / 100);
      const finalFare = Math.max(0, roundMoney(baseFare - discountAmount));
      return {
        ...row,
        base_fare: baseFare,
        loyalty_points: Number(loyaltyAccount.loyalty_points),
        loyalty_tier: loyaltyAccount.tier,
        loyalty_discount_percent: discountPercent,
        loyalty_discount_amount: discountAmount,
        fare: finalFare,
        final_fare: finalFare,
        standby_open: Number(row.standby_waiting) < Number(row.overbook_limit),
        standby_slots_left: Math.max(Number(row.overbook_limit) - Number(row.standby_waiting), 0)
      };
    });
    return res.json({
      flights,
      loyalty: { points: Number(loyaltyAccount.loyalty_points), tier: loyaltyAccount.tier, flight_discount_percent: discountPercent },
      search: { origin_airport_id: originId, destination_airport_id: destinationId, flight_date: flightDate, cabin_class: cabin }
    });
  } catch (error) { return next(error); }
};

exports.myBookings = async (req, res, next) => {
  try {
    const [bookings] = await db.query(`
      SELECT air_booking_id, flight_schedule_id, flight_number, airline_name,
        origin_airport, origin_code, destination_airport, destination_code,
        flight_date, TIME_FORMAT(departure_time, '%H:%i') AS departure_time,
        TIME_FORMAT(arrival_time, '%H:%i') AS arrival_time,
        cabin_class, booking_status AS status, fare, base_fare, loyalty_discount_percent,
        loyalty_discount_amount, loyalty_tier_at_booking, refund_amount, seat_no,
        standby_position, booking_time
      FROM airline_db.vw_air_booking_overview
      WHERE passenger_id = ?
      ORDER BY booking_time DESC, air_booking_id DESC`, [req.user_id]);

    const ids = bookings.map((b) => b.air_booking_id);
    let bags = [];
    if (ids.length) {
      const [bagRows] = await db.query(
        'SELECT air_booking_id, bag_no, weight_kg, excess_fee FROM airline_db.baggage WHERE air_booking_id IN (?) ORDER BY air_booking_id, bag_no',
        [ids]
      );
      bags = bagRows;
    }
    const withBags = bookings.map((b) => {
      const list = bags.filter((bag) => bag.air_booking_id === b.air_booking_id);
      return {
        ...b,
        bags: list,
        baggage_total_kg: list.reduce((sum, bag) => sum + Number(bag.weight_kg), 0),
        baggage_fees: list.reduce((sum, bag) => sum + Number(bag.excess_fee), 0)
      };
    });
    return res.json({ bookings: withBags });
  } catch (error) { return next(error); }
};

exports.createBooking = async (req, res, next) => {
  let connection;
  try {
    const scheduleId = Number(req.body.flight_schedule_id);
    const cabin = String(req.body.cabin_class || '').toUpperCase();
    if (!Number.isInteger(scheduleId) || scheduleId < 1) return res.status(400).json({ error: 'Choose a valid scheduled flight.' });
    if (!VALID_CABINS.has(cabin)) return res.status(400).json({ error: 'Choose a supported cabin class.' });

    // OUT parameters are session-scoped, so CALL and SELECT must use the same connection.
    connection = await db.getConnection();
    await connection.query(
      'CALL airline_db.sp_air_create_booking(?, ?, ?, @booking_id, @final_status, @base_fare, @discount_percent, @discount_amount, @final_fare, @tier_at_booking)',
      [req.user_id, scheduleId, cabin]
    );
    const [result] = await connection.query(`
      SELECT @booking_id AS booking_id, @final_status AS final_status,
             @base_fare AS base_fare, @discount_percent AS loyalty_discount_percent,
             @discount_amount AS loyalty_discount_amount, @final_fare AS final_fare,
             @tier_at_booking AS loyalty_tier_at_booking`
    );
    const created = result[0];
    return res.status(201).json({
      message: created.final_status === 'STANDBY'
        ? 'The flight is full, so you have been added to the priority standby list.'
        : 'Your seat is confirmed.',
      air_booking_id: Number(created.booking_id),
      status: created.final_status,
      base_fare: Number(created.base_fare || 0),
      loyalty_discount_percent: Number(created.loyalty_discount_percent || 0),
      loyalty_discount_amount: Number(created.loyalty_discount_amount || 0),
      final_fare: Number(created.final_fare || 0),
      fare: Number(created.final_fare || 0),
      loyalty_tier_at_booking: created.loyalty_tier_at_booking
    });
  } catch (error) {
    if (isSqlRule(error)) return res.status(400).json({ error: error.sqlMessage || 'The booking could not be completed.' });
    return next(error);
  } finally {
    if (connection) connection.release();
  }
};

exports.cancelBooking = async (req, res, next) => {
  let connection;
  try {
    const bookingId = Number(req.body.air_booking_id);
    if (!Number.isInteger(bookingId) || bookingId < 1) return res.status(400).json({ error: 'Enter a valid booking ID.' });
    connection = await db.getConnection();
    await connection.query('CALL airline_db.sp_air_cancel_booking(?, ?, @refund)', [bookingId, req.user_id]);
    const [result] = await connection.query('SELECT @refund AS refund');
    const refund = Number(result[0]?.refund || 0);
    return res.json({
      message: 'Booking cancelled. If a seat was released, the database trigger has promoted the highest-priority standby passenger.',
      refund_amount: refund
    });
  } catch (error) {
    if (isSqlRule(error)) return res.status(400).json({ error: error.sqlMessage || 'The booking could not be cancelled.' });
    return next(error);
  } finally {
    if (connection) connection.release();
  }
};

exports.getStandbyProbability = async (req, res, next) => {
  try {
    const bookingId = Number(req.query.air_booking_id);
    if (!Number.isInteger(bookingId) || bookingId < 1) {
      return res.status(400).json({ error: 'Choose a standby booking to estimate its confirmation probability.' });
    }

    const [rows] = await db.query(`
      SELECT b.air_booking_id, b.fare, b.cabin_class,
        f.origin_airport_id, f.destination_airport_id,
        fs.flight_date,
        GREATEST(DATEDIFF(fs.flight_date, CURDATE()), 0) AS days_remaining,
        ranked.standby_position,
        o.city AS origin_city, d.city AS destination_city
      FROM (
        SELECT e.air_booking_id, e.flight_schedule_id, e.cabin_class,
          ROW_NUMBER() OVER (
            PARTITION BY e.flight_schedule_id, e.cabin_class
            ORDER BY e.priority_score DESC, e.queued_at ASC, e.standby_id ASC
          ) AS standby_position
        FROM airline_db.air_standby_entries e
        WHERE e.status = 'WAITING'
      ) ranked
      JOIN airline_db.air_bookings b ON b.air_booking_id = ranked.air_booking_id
      JOIN airline_db.flight_schedules fs ON fs.flight_schedule_id = ranked.flight_schedule_id
      JOIN airline_db.flights f ON f.flight_id = fs.flight_id
      JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
      JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id
      WHERE b.air_booking_id = ?
        AND b.passenger_id = ?
        AND b.status = 'STANDBY'
      LIMIT 1`, [bookingId, req.user_id]);

    if (!rows.length) {
      return res.status(404).json({ error: 'A probability estimate is available only for your active standby booking.' });
    }

    const booking = rows[0];
    const estimate = await airProbabilityService.estimate({
      originAirportId: Number(booking.origin_airport_id),
      destinationAirportId: Number(booking.destination_airport_id),
      cabinClass: booking.cabin_class,
      position: Number(booking.standby_position),
      daysRemaining: Number(booking.days_remaining)
    });

    return res.json({
      booking: {
        air_booking_id: Number(booking.air_booking_id),
        cabin_class: booking.cabin_class,
        standby_position: Number(booking.standby_position),
        days_remaining: Number(booking.days_remaining),
        flight_date: booking.flight_date,
        origin_city: booking.origin_city,
        destination_city: booking.destination_city,
        fare: Number(booking.fare)
      },
      ...estimate
    });
  } catch (error) { return next(error); }
};

exports.addBaggage = async (req, res, next) => {
  let connection;
  try {
    const bookingId = Number(req.body.air_booking_id);
    const weight = Number(req.body.weight_kg);
    if (!Number.isInteger(bookingId) || bookingId < 1) return res.status(400).json({ error: 'Choose a valid booking.' });
    if (!Number.isFinite(weight) || weight <= 0 || weight > 50) return res.status(400).json({ error: 'A bag must weigh more than 0 kg and at most 50 kg.' });

    connection = await db.getConnection();
    await connection.query('CALL airline_db.sp_air_add_baggage(?, ?, ?, @bag_no, @fee)', [bookingId, req.user_id, weight.toFixed(2)]);
    const [result] = await connection.query('SELECT @bag_no AS bag_no, @fee AS fee');
    const fee = Number(result[0]?.fee || 0);
    return res.status(201).json({
      message: fee > 0 ? `Bag added. Excess baggage fee: ₹${fee.toFixed(0)}.` : 'Bag added within your free allowance.',
      bag_no: Number(result[0]?.bag_no),
      excess_fee: fee
    });
  } catch (error) {
    if (isSqlRule(error)) return res.status(400).json({ error: error.sqlMessage || 'The bag could not be added.' });
    return next(error);
  } finally {
    if (connection) connection.release();
  }
};
