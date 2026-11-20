-- Flight loyalty discounts (MySQL 8.0.46+)
-- Run after database/09_air_schema.sql, 10_core_loyalty.sql, 11_air_procedures.sql,
-- and 12_air_triggers.sql. The shared users/tier and air fare function must exist.
-- Shared loyalty points are earned across rail and air. This benefit applies to AIR bookings only.
-- Policy: BASIC < 1,000 points = 0%; SILVER 1,000-4,999 = 5%; GOLD >= 5,000 = 10%.
-- Existing bookings are preserved and treated as legacy bookings with no loyalty discount.

USE airline_db;

-- 1. Add a persistent fare breakdown to existing bookings (safe to re-run).
DROP PROCEDURE IF EXISTS sp_install_air_loyalty_discount_columns;
DELIMITER $$
CREATE PROCEDURE sp_install_air_loyalty_discount_columns()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'airline_db' AND TABLE_NAME = 'air_bookings' AND COLUMN_NAME = 'base_fare'
  ) THEN
    ALTER TABLE airline_db.air_bookings
      ADD COLUMN base_fare DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER fare;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'airline_db' AND TABLE_NAME = 'air_bookings' AND COLUMN_NAME = 'loyalty_discount_percent'
  ) THEN
    ALTER TABLE airline_db.air_bookings
      ADD COLUMN loyalty_discount_percent DECIMAL(5,2) NOT NULL DEFAULT 0.00 AFTER base_fare;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'airline_db' AND TABLE_NAME = 'air_bookings' AND COLUMN_NAME = 'loyalty_discount_amount'
  ) THEN
    ALTER TABLE airline_db.air_bookings
      ADD COLUMN loyalty_discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER loyalty_discount_percent;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'airline_db' AND TABLE_NAME = 'air_bookings' AND COLUMN_NAME = 'loyalty_tier_at_booking'
  ) THEN
    ALTER TABLE airline_db.air_bookings
      ADD COLUMN loyalty_tier_at_booking ENUM('BASIC', 'SILVER', 'GOLD') NOT NULL DEFAULT 'BASIC' AFTER loyalty_discount_amount;
  END IF;
END$$
DELIMITER ;
CALL sp_install_air_loyalty_discount_columns();
DROP PROCEDURE sp_install_air_loyalty_discount_columns;

-- Legacy records pre-date the discount feature. Preserve their paid fare as the base fare.
-- Workbench Safe Update Mode can reject this intentional migration update because it
-- filters on a non-key fare-breakdown column, so disable it only for this statement.
SET @air_loyalty_old_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
UPDATE airline_db.air_bookings
SET base_fare = fare
WHERE base_fare = 0.00 AND fare > 0.00;
SET SQL_SAFE_UPDATES = @air_loyalty_old_safe_updates;

-- 2. One authoritative discount policy, calculated from the passenger's shared points balance.
DROP FUNCTION IF EXISTS airline_db.fn_air_loyalty_discount_percent;
DELIMITER $$
CREATE FUNCTION airline_db.fn_air_loyalty_discount_percent(p_loyalty_points INT UNSIGNED)
RETURNS DECIMAL(5,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE
    WHEN p_loyalty_points >= 5000 THEN 10.00
    WHEN p_loyalty_points >= 1000 THEN 5.00
    ELSE 0.00
  END;
END$$
DELIMITER ;

-- 3. Rebuild booking procedure so discounts are calculated and stored in MySQL,
--    never accepted from the browser. fare remains the final amount actually payable.
DROP PROCEDURE IF EXISTS airline_db.sp_air_create_booking;
DELIMITER $$
CREATE PROCEDURE airline_db.sp_air_create_booking(
  IN p_user_id BIGINT UNSIGNED,
  IN p_schedule_id BIGINT UNSIGNED,
  IN p_cabin VARCHAR(10),
  OUT p_booking_id BIGINT UNSIGNED,
  OUT p_final_status VARCHAR(20),
  OUT p_base_fare DECIMAL(10,2),
  OUT p_discount_percent DECIMAL(5,2),
  OUT p_discount_amount DECIMAL(10,2),
  OUT p_final_fare DECIMAL(10,2),
  OUT p_tier_at_booking VARCHAR(10)
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_date DATE DEFAULT NULL;
  DECLARE v_overbook INT DEFAULT 0;
  DECLARE v_seat_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_waiting INT DEFAULT 0;
  DECLARE v_priority TINYINT UNSIGNED DEFAULT 1;
  DECLARE v_points INT UNSIGNED DEFAULT 0;
  DECLARE v_tier VARCHAR(10) DEFAULT 'BASIC';

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_booking_id = NULL;
  SET p_final_status = NULL;
  SET p_base_fare = NULL;
  SET p_discount_percent = 0.00;
  SET p_discount_amount = 0.00;
  SET p_final_fare = NULL;
  SET p_tier_at_booking = 'BASIC';

  IF p_cabin NOT IN ('ECONOMY', 'BUSINESS') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unsupported cabin class.';
  END IF;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_count
  FROM railway_db.users
  WHERE user_id = p_user_id AND role = 'PASSENGER';
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger account was not found.';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM airline_db.flight_schedules
  WHERE flight_schedule_id = p_schedule_id;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Scheduled flight was not found.';
  END IF;

  -- Serialize bookings and cancellations for this flight.
  SELECT schedule_status, flight_date, overbook_limit
    INTO v_status, v_date, v_overbook
  FROM airline_db.flight_schedules
  WHERE flight_schedule_id = p_schedule_id
  FOR UPDATE;

  IF v_status NOT IN ('SCHEDULED', 'DELAYED') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight is not open for booking.';
  END IF;
  IF v_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Past flights cannot be booked.';
  END IF;

  -- Lock the shared passenger row after the schedule row, keeping booking/cancellation lock order consistent.
  SELECT loyalty_points, tier INTO v_points, v_tier
  FROM railway_db.users
  WHERE user_id = p_user_id
  FOR UPDATE;

  SELECT COUNT(*) INTO v_count
  FROM airline_db.flight_seats
  WHERE flight_schedule_id = p_schedule_id AND cabin_class = p_cabin;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight does not offer the selected cabin.';
  END IF;

  -- Dynamic fare before loyalty benefit.
  SET p_base_fare = airline_db.fn_air_fare(p_schedule_id, p_cabin);
  IF p_base_fare IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No fare is configured for this flight and cabin.';
  END IF;

  -- Tier benefit: BASIC 0%, SILVER 5%, GOLD 10%.
  SET p_discount_percent = airline_db.fn_air_loyalty_discount_percent(v_points);
  SET p_discount_amount = ROUND(p_base_fare * p_discount_percent / 100, 2);
  SET p_final_fare = GREATEST(ROUND(p_base_fare - p_discount_amount, 2), 0.00);
  SET p_tier_at_booking = v_tier;

  SELECT MIN(s.flight_seat_id) INTO v_seat_id
  FROM airline_db.flight_seats s
  WHERE s.flight_schedule_id = p_schedule_id
    AND s.cabin_class = p_cabin
    AND NOT EXISTS (
      SELECT 1 FROM airline_db.air_seat_allocations a
      WHERE a.flight_schedule_id = p_schedule_id
        AND a.flight_seat_id = s.flight_seat_id
    );

  IF v_seat_id IS NOT NULL THEN
    INSERT INTO airline_db.air_bookings
      (passenger_id, flight_schedule_id, cabin_class, status, fare,
       base_fare, loyalty_discount_percent, loyalty_discount_amount, loyalty_tier_at_booking)
    VALUES
      (p_user_id, p_schedule_id, p_cabin, 'CONFIRMED', p_final_fare,
       p_base_fare, p_discount_percent, p_discount_amount, p_tier_at_booking);
    SET p_booking_id = LAST_INSERT_ID();

    INSERT INTO airline_db.air_seat_allocations (flight_schedule_id, flight_seat_id, air_booking_id)
    VALUES (p_schedule_id, v_seat_id, p_booking_id);
    SET p_final_status = 'CONFIRMED';
  ELSE
    SELECT COUNT(*) INTO v_waiting
    FROM airline_db.air_standby_entries
    WHERE flight_schedule_id = p_schedule_id
      AND cabin_class = p_cabin
      AND status = 'WAITING';
    IF v_waiting >= v_overbook THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight is full and its standby list is full.';
    END IF;

    SET v_priority = CASE v_tier WHEN 'GOLD' THEN 3 WHEN 'SILVER' THEN 2 ELSE 1 END;

    INSERT INTO airline_db.air_bookings
      (passenger_id, flight_schedule_id, cabin_class, status, fare,
       base_fare, loyalty_discount_percent, loyalty_discount_amount, loyalty_tier_at_booking)
    VALUES
      (p_user_id, p_schedule_id, p_cabin, 'STANDBY', p_final_fare,
       p_base_fare, p_discount_percent, p_discount_amount, p_tier_at_booking);
    SET p_booking_id = LAST_INSERT_ID();

    INSERT INTO airline_db.air_standby_entries
      (air_booking_id, flight_schedule_id, cabin_class, priority_score, status)
    VALUES (p_booking_id, p_schedule_id, p_cabin, v_priority, 'WAITING');
    SET p_final_status = 'STANDBY';
  END IF;

  COMMIT;
END$$
DELIMITER ;

-- 4. Refresh airline booking view with the persisted price breakdown.
CREATE OR REPLACE VIEW airline_db.vw_air_booking_overview AS
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
  b.base_fare,
  b.loyalty_discount_percent,
  b.loyalty_discount_amount,
  b.loyalty_tier_at_booking,
  b.refund_amount,
  seat.seat_no,
  sq.standby_position,
  b.booking_time
FROM airline_db.air_bookings b
JOIN railway_db.users u ON u.user_id = b.passenger_id
JOIN airline_db.flight_schedules fs ON fs.flight_schedule_id = b.flight_schedule_id
JOIN airline_db.flights f ON f.flight_id = fs.flight_id
JOIN airline_db.airlines al ON al.airline_id = f.airline_id
JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id
LEFT JOIN airline_db.air_seat_allocations a ON a.air_booking_id = b.air_booking_id
LEFT JOIN airline_db.flight_seats seat ON seat.flight_seat_id = a.flight_seat_id
LEFT JOIN (
  SELECT e.air_booking_id,
         ROW_NUMBER() OVER (PARTITION BY e.flight_schedule_id, e.cabin_class
                            ORDER BY e.priority_score DESC, e.queued_at ASC, e.standby_id ASC) AS standby_position
  FROM airline_db.air_standby_entries e
  WHERE e.status = 'WAITING'
) sq ON sq.air_booking_id = b.air_booking_id;

-- 5. Refresh the unified trip history to expose the air discount in trip records too.
CREATE OR REPLACE VIEW transport_core.v_trip_history AS
SELECT
  'RAIL' AS travel_mode,
  b.passenger_id,
  b.booking_id AS booking_ref,
  t.train_name AS carrier,
  t.train_number AS service_number,
  o.station_name AS origin,
  d.station_name AS destination,
  s.journey_date AS travel_date,
  TIME_FORMAT(s.departure_time, '%H:%i') AS departure_time,
  b.class_type AS travel_class,
  b.status AS status,
  b.fare AS fare,
  b.fare AS base_fare,
  CAST(0.00 AS DECIMAL(5,2)) AS loyalty_discount_percent,
  CAST(0.00 AS DECIMAL(10,2)) AS loyalty_discount_amount,
  b.booking_time AS booking_time
FROM railway_db.bookings b
JOIN railway_db.train_schedules s ON s.schedule_id = b.schedule_id
JOIN railway_db.train_routes r ON r.route_id = s.route_id
JOIN railway_db.trains t ON t.train_id = r.train_id
JOIN railway_db.stations o ON o.station_id = r.origin_station_id
JOIN railway_db.stations d ON d.station_id = r.destination_station_id
UNION ALL
SELECT
  'AIR' AS travel_mode,
  ab.passenger_id,
  ab.air_booking_id AS booking_ref,
  al.airline_name AS carrier,
  f.flight_number AS service_number,
  o.airport_name AS origin,
  d.airport_name AS destination,
  fs.flight_date AS travel_date,
  TIME_FORMAT(f.departure_time, '%H:%i') AS departure_time,
  ab.cabin_class AS travel_class,
  ab.status AS status,
  ab.fare AS fare,
  ab.base_fare AS base_fare,
  ab.loyalty_discount_percent AS loyalty_discount_percent,
  ab.loyalty_discount_amount AS loyalty_discount_amount,
  ab.booking_time AS booking_time
FROM airline_db.air_bookings ab
JOIN airline_db.flight_schedules fs ON fs.flight_schedule_id = ab.flight_schedule_id
JOIN airline_db.flights f ON f.flight_id = fs.flight_id
JOIN airline_db.airlines al ON al.airline_id = f.airline_id
JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id;

SELECT 'Air loyalty discount migration installed.' AS result;
SELECT 'BASIC: 0% (< 1,000 points); SILVER: 5% (1,000-4,999); GOLD: 10% (5,000+).' AS policy;
