USE airline_db;
DROP TRIGGER IF EXISTS trg_air_schedule_before_insert;
DROP TRIGGER IF EXISTS trg_air_schedule_before_update;
DROP TRIGGER IF EXISTS trg_air_schedule_generate_seats;
DROP TRIGGER IF EXISTS trg_air_bookings_after_insert;
DROP TRIGGER IF EXISTS trg_air_bookings_after_update;
DROP TRIGGER IF EXISTS trg_air_promote_standby_after_cancellation;
DROP TRIGGER IF EXISTS trg_air_baggage_before_insert;
DELIMITER $$

-- A4: aircraft assignment conflict check (insert and update).
CREATE TRIGGER trg_air_schedule_before_insert
BEFORE INSERT ON flight_schedules
FOR EACH ROW
BEGIN
  CALL sp_air_assert_aircraft_free(NULLIF(NEW.flight_schedule_id, 0), NEW.flight_id, NEW.aircraft_id,
                                   NEW.flight_date, NEW.schedule_status);
END$$

CREATE TRIGGER trg_air_schedule_before_update
BEFORE UPDATE ON flight_schedules
FOR EACH ROW
BEGIN
  CALL sp_air_assert_aircraft_free(OLD.flight_schedule_id, NEW.flight_id, NEW.aircraft_id,
                                   NEW.flight_date, NEW.schedule_status);
END$$

-- Seat map: generate all cabin seats in one set-based INSERT per schedule.
-- This is much faster when the demo network seeds thousands of daily schedules.
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

-- Booking history + loyalty points (S1) when a booking is created.
CREATE TRIGGER trg_air_bookings_after_insert
AFTER INSERT ON air_bookings
FOR EACH ROW
BEGIN
  INSERT INTO air_booking_history (air_booking_id, old_status, new_status, event_type)
  VALUES (NEW.air_booking_id, NULL, NEW.status,
          CASE WHEN NEW.status = 'STANDBY' THEN 'STANDBY_JOINED' ELSE 'BOOKED' END);

  IF NEW.status = 'CONFIRMED' THEN
    CALL transport_core.sp_award_loyalty(NEW.passenger_id, FLOOR(NEW.fare / 100), NULL, NEW.air_booking_id);
  END IF;
END$$

-- Booking history + loyalty points when the status changes (promotion or cancellation).
CREATE TRIGGER trg_air_bookings_after_update
AFTER UPDATE ON air_bookings
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO air_booking_history (air_booking_id, old_status, new_status, event_type)
    VALUES (NEW.air_booking_id, OLD.status, NEW.status,
            CASE WHEN NEW.status = 'CONFIRMED' THEN 'PROMOTED'
                 WHEN NEW.status = 'CANCELLED' THEN 'CANCELLED'
                 ELSE 'STANDBY_JOINED' END);

    IF OLD.status = 'STANDBY' AND NEW.status = 'CONFIRMED' THEN
      CALL transport_core.sp_award_loyalty(NEW.passenger_id, FLOOR(NEW.fare / 100), NULL, NEW.air_booking_id);
    ELSEIF OLD.status = 'CONFIRMED' AND NEW.status = 'CANCELLED' THEN
      CALL transport_core.sp_award_loyalty(NEW.passenger_id, -FLOOR(NEW.fare / 100), NULL, NEW.air_booking_id);
    END IF;
  END IF;
END$$

-- A2: when a cancellation really released a seat, promote the highest-priority standby
-- booking of the same flight and cabin (priority_score DESC, queued_at ASC, standby_id ASC).
CREATE TRIGGER trg_air_promote_standby_after_cancellation
AFTER INSERT ON air_cancellations
FOR EACH ROW
BEGIN
  DECLARE v_standby_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_booking_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_none TINYINT DEFAULT 0;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_none = 1;

  IF NEW.released_flight_seat_id IS NOT NULL THEN
    SELECT e.standby_id, e.air_booking_id
      INTO v_standby_id, v_booking_id
    FROM air_standby_entries e
    JOIN air_bookings b ON b.air_booking_id = e.air_booking_id
    WHERE e.flight_schedule_id = NEW.flight_schedule_id
      AND e.cabin_class = NEW.cabin_class
      AND e.status = 'WAITING'
      AND b.status = 'STANDBY'
    ORDER BY e.priority_score DESC, e.queued_at ASC, e.standby_id ASC
    LIMIT 1;

    IF v_none = 0 AND v_standby_id IS NOT NULL AND v_booking_id IS NOT NULL THEN
      INSERT INTO air_seat_allocations (flight_schedule_id, flight_seat_id, air_booking_id)
      VALUES (NEW.flight_schedule_id, NEW.released_flight_seat_id, v_booking_id);

      UPDATE air_bookings SET status = 'CONFIRMED'
      WHERE air_booking_id = v_booking_id AND status = 'STANDBY';

      UPDATE air_standby_entries SET status = 'PROMOTED', promoted_at = CURRENT_TIMESTAMP
      WHERE standby_id = v_standby_id AND status = 'WAITING';
    END IF;
  END IF;
END$$

-- A3: excess baggage fee = 400 per kg above the cabin allowance (shared by all bags of the booking).
CREATE TRIGGER trg_air_baggage_before_insert
BEFORE INSERT ON baggage
FOR EACH ROW
BEGIN
  DECLARE v_cabin VARCHAR(10) DEFAULT NULL;
  DECLARE v_previous DECIMAL(7,2) DEFAULT 0;
  DECLARE v_allowance DECIMAL(5,2) DEFAULT 0;

  SELECT MAX(cabin_class) INTO v_cabin FROM air_bookings WHERE air_booking_id = NEW.air_booking_id;
  SELECT COALESCE(SUM(weight_kg), 0) INTO v_previous FROM baggage WHERE air_booking_id = NEW.air_booking_id;
  SET v_allowance = fn_free_baggage_kg(v_cabin);

  SET NEW.excess_fee = ROUND(
    (GREATEST(v_previous + NEW.weight_kg - v_allowance, 0) - GREATEST(v_previous - v_allowance, 0)) * 400.00, 2);
END$$
DELIMITER ;
