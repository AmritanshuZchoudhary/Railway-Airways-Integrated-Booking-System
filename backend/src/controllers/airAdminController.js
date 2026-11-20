const db = require('../config/db');

exports.getAirAdminSummary = async (_req, res, next) => {
  try {
    const [rows] = await db.query(`
      SELECT
        (SELECT COUNT(*) FROM airline_db.airlines) AS airlines,
        (SELECT COUNT(*) FROM airline_db.aircraft) AS aircraft,
        (SELECT COUNT(*) FROM airline_db.flight_schedules WHERE flight_date >= CURDATE() AND schedule_status IN ('SCHEDULED','DELAYED')) AS open_flights,
        (SELECT COUNT(*) FROM airline_db.air_bookings) AS total_bookings,
        (SELECT COUNT(*) FROM airline_db.air_bookings WHERE status = 'STANDBY') AS current_standby,
        (SELECT COUNT(*) FROM airline_db.air_standby_entries WHERE status = 'PROMOTED') AS promotions,
        (SELECT COUNT(*) FROM airline_db.air_cancellations) AS cancellations,
        (SELECT COALESCE(SUM(excess_fee), 0) FROM airline_db.baggage) AS baggage_fees,
        (SELECT COALESCE(SUM(fare), 0) FROM airline_db.air_bookings WHERE status = 'CONFIRMED') AS confirmed_revenue,
        (SELECT COALESCE(SUM(points), 0) FROM transport_core.loyalty_txn) AS loyalty_points_issued,
        (SELECT COALESCE(SUM(loyalty_discount_amount), 0) FROM airline_db.air_bookings) AS flight_discounts_given`);
    return res.json({ summary: rows[0] });
  } catch (error) { return next(error); }
};

exports.getScheduleOptions = async (_req, res, next) => {
  try {
    const [[flights], [aircraft], [schedules]] = await Promise.all([
      db.query(`SELECT f.flight_id, f.flight_number, f.airline_id, al.airline_name,
                  TIME_FORMAT(f.departure_time, '%H:%i') AS departure_time, TIME_FORMAT(f.arrival_time, '%H:%i') AS arrival_time,
                  o.iata_code AS origin_code, d.iata_code AS destination_code
                FROM airline_db.flights f
                JOIN airline_db.airlines al ON al.airline_id = f.airline_id
                JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
                JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id
                ORDER BY f.flight_number`),
      db.query(`SELECT a.aircraft_id, a.registration_no, a.model, a.airline_id, al.airline_name, a.economy_seats, a.business_seats
                FROM airline_db.aircraft a JOIN airline_db.airlines al ON al.airline_id = a.airline_id ORDER BY a.registration_no`),
      db.query(`SELECT fs.flight_schedule_id, f.flight_number, fs.flight_date, a.registration_no, fs.schedule_status, fs.overbook_limit
                FROM airline_db.flight_schedules fs
                JOIN airline_db.flights f ON f.flight_id = fs.flight_id
                JOIN airline_db.aircraft a ON a.aircraft_id = fs.aircraft_id
                WHERE fs.flight_date >= CURDATE() ORDER BY fs.flight_date, f.departure_time LIMIT 30`)
    ]);
    return res.json({ flights, aircraft, schedules });
  } catch (error) { return next(error); }
};

// Novelty A4 demo: the trigger rejects an aircraft that already flies an overlapping schedule.
exports.createSchedule = async (req, res, next) => {
  try {
    const flightId = Number(req.body.flight_id);
    const aircraftId = Number(req.body.aircraft_id);
    const flightDate = String(req.body.flight_date || '');
    const overbookLimit = Number(req.body.overbook_limit ?? 2);
    if (!Number.isInteger(flightId) || flightId < 1) return res.status(400).json({ error: 'Choose a flight.' });
    if (!Number.isInteger(aircraftId) || aircraftId < 1) return res.status(400).json({ error: 'Choose an aircraft.' });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(flightDate) || Number.isNaN(Date.parse(`${flightDate}T00:00:00Z`))) {
      return res.status(400).json({ error: 'Choose a valid flight date.' });
    }
    if (!Number.isInteger(overbookLimit) || overbookLimit < 0 || overbookLimit > 20) {
      return res.status(400).json({ error: 'The standby limit must be a whole number from 0 to 20.' });
    }
    const [result] = await db.query(
      'INSERT INTO airline_db.flight_schedules (flight_id, aircraft_id, flight_date, overbook_limit) VALUES (?, ?, ?, ?)',
      [flightId, aircraftId, flightDate, overbookLimit]
    );
    const [[seatCount]] = await db.query('SELECT COUNT(*) AS seats FROM airline_db.flight_seats WHERE flight_schedule_id = ?', [result.insertId]);
    return res.status(201).json({
      message: `Flight schedule #${result.insertId} created with ${seatCount.seats} generated seats.`,
      flight_schedule_id: result.insertId,
      seats_generated: Number(seatCount.seats)
    });
  } catch (error) {
    if (error.sqlState === '45000' || error.code === 'ER_SIGNAL_EXCEPTION') {
      return res.status(400).json({ error: error.sqlMessage || 'The schedule could not be created.' });
    }
    if (error.code === 'ER_DUP_ENTRY') return res.status(409).json({ error: 'This flight is already scheduled on that date.' });
    if (error.code === 'ER_NO_REFERENCED_ROW_2') return res.status(400).json({ error: 'The flight or aircraft does not exist.' });
    return next(error);
  }
};


exports.finalizeStandbyHistory = async (_req, res, next) => {
  let connection;
  try {
    connection = await db.getConnection();
    await connection.query('CALL airline_db.sp_air_finalize_standby_history(@inserted_air_history_count)');
    const [rows] = await connection.query('SELECT @inserted_air_history_count AS inserted_count');
    const insertedCount = Number(rows[0]?.inserted_count || 0);
    return res.json({
      message: insertedCount
        ? `Recorded ${insertedCount} completed airline standby outcome(s).`
        : 'No new completed airline standby outcomes were ready to record.',
      inserted_count: insertedCount
    });
  } catch (error) { return next(error); }
  finally { if (connection) connection.release(); }
};
