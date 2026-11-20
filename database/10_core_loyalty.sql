-- Shared core: the only things the railway and airline modules have in common.
--   * the passenger account  -> railway_db.users (gets loyalty_points + tier)
--   * the loyalty ledger     -> transport_core.loyalty_txn (exclusive arc: one rail OR one air booking)
--   * the unified trip view  -> transport_core.v_trip_history
-- Run after 09_air_schema.sql. Safe to re-run.
CREATE DATABASE IF NOT EXISTS transport_core
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE transport_core;

-- 1. Add loyalty_points and a generated tier column to the existing users table (idempotent).
DROP PROCEDURE IF EXISTS sp_install_loyalty_columns;
DELIMITER $$
CREATE PROCEDURE sp_install_loyalty_columns()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'railway_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'loyalty_points'
  ) THEN
    ALTER TABLE railway_db.users
      ADD COLUMN loyalty_points INT UNSIGNED NOT NULL DEFAULT 0,
      ADD COLUMN tier ENUM('BASIC', 'SILVER', 'GOLD')
        GENERATED ALWAYS AS (
          CASE WHEN loyalty_points >= 5000 THEN 'GOLD'
               WHEN loyalty_points >= 1000 THEN 'SILVER'
               ELSE 'BASIC' END
        ) STORED;
  END IF;
END$$
DELIMITER ;
CALL sp_install_loyalty_columns();
DROP PROCEDURE sp_install_loyalty_columns;

-- 2. Loyalty ledger with an exclusive arc: exactly one of booking_id / air_booking_id is set.
CREATE TABLE IF NOT EXISTS loyalty_txn (
  loyalty_txn_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  passenger_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED NULL,
  air_booking_id BIGINT UNSIGNED NULL,
  points INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (loyalty_txn_id),
  KEY idx_loyalty_passenger (passenger_id, created_at),
  KEY idx_loyalty_rail_booking (booking_id),
  KEY idx_loyalty_air_booking (air_booking_id),
  CONSTRAINT fk_loyalty_passenger FOREIGN KEY (passenger_id) REFERENCES railway_db.users (user_id),
  CONSTRAINT fk_loyalty_rail_booking FOREIGN KEY (booking_id) REFERENCES railway_db.bookings (booking_id),
  CONSTRAINT fk_loyalty_air_booking FOREIGN KEY (air_booking_id) REFERENCES airline_db.air_bookings (air_booking_id),
  CONSTRAINT chk_loyalty_exclusive_arc CHECK ((booking_id IS NULL) <> (air_booking_id IS NULL)),
  CONSTRAINT chk_loyalty_points CHECK (points <> 0)
) ENGINE=InnoDB;

-- 3. One procedure used by every booking trigger (rail and air).
--    Positive points are an award; a negative value reverses what was earned for that booking
--    (never more than was actually earned, so old bookings without a ledger row are safe).
DROP PROCEDURE IF EXISTS sp_award_loyalty;
DELIMITER $$
CREATE PROCEDURE sp_award_loyalty(
  IN p_passenger_id BIGINT UNSIGNED,
  IN p_points INT,
  IN p_booking_id BIGINT UNSIGNED,
  IN p_air_booking_id BIGINT UNSIGNED
)
BEGIN
  DECLARE v_earned INT DEFAULT 0;

  IF p_points < 0 THEN
    SELECT COALESCE(SUM(points), 0) INTO v_earned
    FROM loyalty_txn
    WHERE passenger_id = p_passenger_id
      AND ((p_booking_id IS NOT NULL AND booking_id = p_booking_id)
        OR (p_air_booking_id IS NOT NULL AND air_booking_id = p_air_booking_id));
    SET p_points = -LEAST(v_earned, -p_points);
  END IF;

  IF p_points <> 0 THEN
    INSERT INTO loyalty_txn (passenger_id, booking_id, air_booking_id, points)
    VALUES (p_passenger_id, p_booking_id, p_air_booking_id, p_points);

    UPDATE railway_db.users
    SET loyalty_points = GREATEST(CAST(loyalty_points AS SIGNED) + p_points, 0)
    WHERE user_id = p_passenger_id;
  END IF;
END$$
DELIMITER ;

-- 4. Railway triggers: 1 point per 100 rupees of fare when a booking becomes CONFIRMED
--    (booked directly or promoted from the waitlist); reversed when it is cancelled.
USE railway_db;
DROP TRIGGER IF EXISTS trg_bookings_loyalty_after_insert;
DROP TRIGGER IF EXISTS trg_bookings_loyalty_after_update;
DELIMITER $$
CREATE TRIGGER trg_bookings_loyalty_after_insert
AFTER INSERT ON bookings
FOR EACH ROW
BEGIN
  IF NEW.status = 'CONFIRMED' THEN
    CALL transport_core.sp_award_loyalty(NEW.passenger_id, FLOOR(NEW.fare / 100), NEW.booking_id, NULL);
  END IF;
END$$

CREATE TRIGGER trg_bookings_loyalty_after_update
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
  IF OLD.status <> 'CONFIRMED' AND NEW.status = 'CONFIRMED' THEN
    CALL transport_core.sp_award_loyalty(NEW.passenger_id, FLOOR(NEW.fare / 100), NEW.booking_id, NULL);
  ELSEIF OLD.status = 'CONFIRMED' AND NEW.status IN ('CANCELLED', 'EXPIRED') THEN
    CALL transport_core.sp_award_loyalty(NEW.passenger_id, -FLOOR(NEW.fare / 100), NEW.booking_id, NULL);
  END IF;
END$$
DELIMITER ;

-- 5. Unified trip history (novelty S3): rail and air trips of a passenger in one list.
USE transport_core;
CREATE OR REPLACE VIEW v_trip_history AS
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
  ab.booking_time AS booking_time
FROM airline_db.air_bookings ab
JOIN airline_db.flight_schedules fs ON fs.flight_schedule_id = ab.flight_schedule_id
JOIN airline_db.flights f ON f.flight_id = fs.flight_id
JOIN airline_db.airlines al ON al.airline_id = f.airline_id
JOIN airline_db.airports o ON o.airport_id = f.origin_airport_id
JOIN airline_db.airports d ON d.airport_id = f.destination_airport_id;
