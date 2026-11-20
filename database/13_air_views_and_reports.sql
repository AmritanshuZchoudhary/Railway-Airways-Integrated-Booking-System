USE airline_db;

-- Standby position is derived (rank by priority, then queue time), so it is always current.
CREATE OR REPLACE VIEW vw_air_booking_overview AS
SELECT
  b.air_booking_id,
  b.passenger_id,
  u.full_name AS passenger_name,
  u.email AS passenger_email,
  u.tier AS passenger_tier,
  b.flight_schedule_id,
  f.flight_number,
  al.airline_name,
  o.airport_name AS origin_airport,
  o.iata_code AS origin_code,
  d.airport_name AS destination_airport,
  d.iata_code AS destination_code,
  fs.flight_date,
  fs.schedule_status,
  f.departure_time,
  f.arrival_time,
  b.cabin_class,
  b.status AS booking_status,
  b.fare,
  b.refund_amount,
  seat.seat_no,
  sq.standby_position,
  b.booking_time
FROM air_bookings b
JOIN railway_db.users u ON u.user_id = b.passenger_id
JOIN flight_schedules fs ON fs.flight_schedule_id = b.flight_schedule_id
JOIN flights f ON f.flight_id = fs.flight_id
JOIN airlines al ON al.airline_id = f.airline_id
JOIN airports o ON o.airport_id = f.origin_airport_id
JOIN airports d ON d.airport_id = f.destination_airport_id
LEFT JOIN air_seat_allocations a ON a.air_booking_id = b.air_booking_id
LEFT JOIN flight_seats seat ON seat.flight_seat_id = a.flight_seat_id
LEFT JOIN (
  SELECT air_booking_id,
         ROW_NUMBER() OVER (PARTITION BY flight_schedule_id, cabin_class
                            ORDER BY priority_score DESC, queued_at ASC, standby_id ASC) AS standby_position
  FROM air_standby_entries
  WHERE status = 'WAITING'
) sq ON sq.air_booking_id = b.air_booking_id;

CREATE OR REPLACE VIEW vw_flight_occupancy AS
SELECT
  fs.flight_schedule_id,
  fs.flight_date,
  fs.schedule_status,
  f.flight_number,
  o.iata_code AS origin_code,
  d.iata_code AS destination_code,
  seat.cabin_class,
  COUNT(DISTINCT seat.flight_seat_id) AS total_seats,
  COUNT(DISTINCT a.flight_seat_id) AS occupied_seats,
  COUNT(DISTINCT seat.flight_seat_id) - COUNT(DISTINCT a.flight_seat_id) AS available_seats,
  fs.overbook_limit,
  (SELECT COUNT(*) FROM air_standby_entries e
    WHERE e.flight_schedule_id = fs.flight_schedule_id AND e.cabin_class = seat.cabin_class AND e.status = 'WAITING') AS standby_waiting
FROM flight_schedules fs
JOIN flights f ON f.flight_id = fs.flight_id
JOIN airports o ON o.airport_id = f.origin_airport_id
JOIN airports d ON d.airport_id = f.destination_airport_id
JOIN flight_seats seat ON seat.flight_schedule_id = fs.flight_schedule_id
LEFT JOIN air_seat_allocations a ON a.flight_schedule_id = fs.flight_schedule_id AND a.flight_seat_id = seat.flight_seat_id
GROUP BY fs.flight_schedule_id, fs.flight_date, fs.schedule_status, f.flight_number,
         o.iata_code, d.iata_code, seat.cabin_class, fs.overbook_limit;

CREATE OR REPLACE VIEW vw_air_revenue_summary AS
SELECT
  f.flight_number,
  fs.flight_date,
  COUNT(*) AS bookings,
  SUM(b.status = 'CONFIRMED') AS confirmed,
  SUM(b.status = 'STANDBY') AS standby,
  SUM(b.status = 'CANCELLED') AS cancelled,
  COALESCE(SUM(CASE WHEN b.status = 'CONFIRMED' THEN b.fare END), 0) AS confirmed_revenue,
  COALESCE(SUM(CASE WHEN b.status = 'CANCELLED' THEN b.refund_amount END), 0) AS refunds_paid
FROM air_bookings b
JOIN flight_schedules fs ON fs.flight_schedule_id = b.flight_schedule_id
JOIN flights f ON f.flight_id = fs.flight_id
GROUP BY f.flight_number, fs.flight_date;
