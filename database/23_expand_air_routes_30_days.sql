-- Expand the Airways demo network so every ordered airport pair has two direct flights.
-- Each flight receives a dedicated aircraft and runs once per day for 30 calendar days.
-- All airlines, routes, schedules, times, prices and aircraft are synthetic academic demo data.
-- Safe to re-run: aircraft/flights/fares are upserted and existing flight/date schedules are skipped.
USE airline_db;

START TRANSACTION;

-- Two dedicated aircraft per ordered airport pair, one for each daily flight option.
INSERT INTO aircraft (airline_id, registration_no, model, economy_seats, business_seats)
SELECT
  MOD(o.airport_id + d.airport_id + svc.service_no - 1, 4) + 1 AS airline_id,
  CONCAT('VX', LPAD(o.airport_id, 2, '0'), LPAD(d.airport_id, 2, '0'), svc.service_no) AS registration_no,
  'Demo Narrowbody 120' AS model,
  48 AS economy_seats,
  12 AS business_seats
FROM airports o
CROSS JOIN airports d
CROSS JOIN (
  SELECT 1 AS service_no
  UNION ALL SELECT 2
) svc
WHERE o.airport_id <> d.airport_id
ON DUPLICATE KEY UPDATE
  airline_id = VALUES(airline_id),
  model = VALUES(model),
  economy_seats = 48,
  business_seats = 12;

-- Two flight numbers for each direct airport-to-airport direction.
INSERT INTO flights
  (flight_number, airline_id, origin_airport_id, destination_airport_id,
   departure_time, arrival_time, distance_km)
SELECT
  CONCAT('AX', LPAD(o.airport_id, 2, '0'), LPAD(d.airport_id, 2, '0'), svc.service_no) AS flight_number,
  MOD(o.airport_id + d.airport_id + svc.service_no - 1, 4) + 1 AS airline_id,
  o.airport_id,
  d.airport_id,
  CASE WHEN svc.service_no = 1 THEN '06:30:00' ELSE '15:30:00' END,
  ADDTIME(
    CASE WHEN svc.service_no = 1 THEN '06:30:00' ELSE '15:30:00' END,
    SEC_TO_TIME((1 + MOD(o.airport_id + d.airport_id + svc.service_no, 4)) * 3600)
  ),
  GREATEST(
    120.00,
    200.00
      + ABS(CAST(o.airport_id AS SIGNED) - CAST(d.airport_id AS SIGNED)) * 110.00
      + MOD(o.airport_id * d.airport_id, 100)
  ) AS distance_km
FROM airports o
CROSS JOIN airports d
CROSS JOIN (
  SELECT 1 AS service_no
  UNION ALL SELECT 2
) svc
WHERE o.airport_id <> d.airport_id
ON DUPLICATE KEY UPDATE
  airline_id = VALUES(airline_id),
  origin_airport_id = VALUES(origin_airport_id),
  destination_airport_id = VALUES(destination_airport_id),
  departure_time = VALUES(departure_time),
  arrival_time = VALUES(arrival_time),
  distance_km = VALUES(distance_km);

-- Dynamic demo fares for both cabins.
INSERT INTO fare_rules (flight_id, cabin_class, base_fare)
SELECT f.flight_id, cabins.cabin_class,
       GREATEST(1500.00, ROUND(f.distance_km * cabins.fare_multiplier, 2))
FROM flights f
CROSS JOIN (
  SELECT 'ECONOMY' AS cabin_class, 4.00 AS fare_multiplier
  UNION ALL SELECT 'BUSINESS', 10.80
) cabins
WHERE f.flight_number REGEXP '^AX[0-9]{5}$'
ON DUPLICATE KEY UPDATE base_fare = VALUES(base_fare);

-- Use a set-based seat trigger for newly created schedules.
-- Existing flight_schedules rows and their seat allocations are untouched.
DROP TRIGGER IF EXISTS trg_air_schedule_generate_seats;
DELIMITER $$
CREATE TRIGGER trg_air_schedule_generate_seats
AFTER INSERT ON flight_schedules
FOR EACH ROW
BEGIN
  DECLARE v_economy INT DEFAULT 0;
  DECLARE v_business INT DEFAULT 0;

  SELECT economy_seats, business_seats
    INTO v_economy, v_business
  FROM aircraft
  WHERE aircraft_id = NEW.aircraft_id;

  INSERT INTO flight_seats (flight_schedule_id, seat_no, cabin_class)
  SELECT
    NEW.flight_schedule_id,
    CONCAT(seat_types.seat_prefix, LPAD(numbers.seat_no, 2, '0')),
    seat_types.cabin_class
  FROM (
    SELECT 'ECONOMY' AS cabin_class, 'E' AS seat_prefix, v_economy AS seat_count
    UNION ALL
    SELECT 'BUSINESS', 'B', v_business
  ) AS seat_types
  CROSS JOIN (
    SELECT ones.n + tens.n * 10 + 1 AS seat_no
    FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
          UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) tens
  ) AS numbers
  WHERE numbers.seat_no <= seat_types.seat_count;
END$$
DELIMITER ;

-- Create one schedule per flight per day from today through day 29.
-- Each generated flight owns one aircraft, avoiding aircraft overlap conflicts.
INSERT INTO flight_schedules
  (flight_id, aircraft_id, flight_date, schedule_status, overbook_limit)
SELECT
  f.flight_id,
  ac.aircraft_id,
  DATE_ADD(CURDATE(), INTERVAL day_grid.day_offset DAY),
  'SCHEDULED',
  4
FROM flights f
JOIN aircraft ac
  ON ac.registration_no = CONCAT('VX', SUBSTRING(f.flight_number, 3))
CROSS JOIN (
  SELECT ones.n + tens.n * 10 AS day_offset
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2) tens
  WHERE ones.n + tens.n * 10 < 30
) day_grid
WHERE f.flight_number REGEXP '^AX[0-9]{5}$'
  AND NOT EXISTS (
    SELECT 1
    FROM flight_schedules existing
    WHERE existing.flight_id = f.flight_id
      AND existing.flight_date = DATE_ADD(CURDATE(), INTERVAL day_grid.day_offset DAY)
  );

COMMIT;

-- Verification: every ordered airport pair should show at least two generated flights.
SELECT COUNT(*) AS airport_count FROM airports;
SELECT COUNT(*) AS generated_flights FROM flights WHERE flight_number REGEXP '^AX[0-9]{5}$';
SELECT COUNT(*) AS generated_30_day_flight_schedules
FROM flight_schedules fs JOIN flights f ON f.flight_id = fs.flight_id
WHERE f.flight_number REGEXP '^AX[0-9]{5}$'
  AND fs.flight_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);

-- Example check requested by the team: Indore to Jaipur (if both airports exist).
SELECT o.city AS origin_city, d.city AS destination_city, COUNT(DISTINCT f.flight_id) AS flight_options
FROM airports o
JOIN flights f ON f.origin_airport_id = o.airport_id
JOIN airports d ON d.airport_id = f.destination_airport_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
  AND f.flight_number REGEXP '^AX[0-9]{5}$'
GROUP BY o.city, d.city;
