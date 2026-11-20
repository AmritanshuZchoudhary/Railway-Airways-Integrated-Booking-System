USE airline_db;
DROP FUNCTION IF EXISTS fn_free_baggage_kg;
DROP FUNCTION IF EXISTS fn_air_refund;
DROP FUNCTION IF EXISTS fn_air_fare;
DROP PROCEDURE IF EXISTS sp_air_create_booking;
DROP PROCEDURE IF EXISTS sp_air_cancel_booking;
DROP PROCEDURE IF EXISTS sp_air_add_baggage;
DROP PROCEDURE IF EXISTS sp_air_assert_aircraft_free;
DELIMITER $$

-- A3: free baggage allowance per booking (demonstration values).
CREATE FUNCTION fn_free_baggage_kg(p_cabin VARCHAR(10))
RETURNS DECIMAL(5,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE WHEN p_cabin = 'BUSINESS' THEN 30.00 ELSE 15.00 END;
END$$

-- Refund slabs by time before departure (demonstration values):
-- more than 48 h: 90 %, 12 to 48 h: 50 %, under 12 h: 0 %.
CREATE FUNCTION fn_air_refund(p_fare DECIMAL(10,2), p_hours_before INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN ROUND(p_fare * CASE WHEN p_hours_before > 48 THEN 0.90
                             WHEN p_hours_before >= 12 THEN 0.50
                             ELSE 0.00 END, 2);
END$$

-- A1: dynamic fare = base fare x occupancy factor x time factor.
--   occupancy factor = 1 + 0.5 x allocated seats / total seats of the cabin
--   time factor      = 1.3 when the flight is less than 7 days away, otherwise 1.0
CREATE FUNCTION fn_air_fare(p_schedule_id BIGINT UNSIGNED, p_cabin VARCHAR(10))
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
  DECLARE v_base DECIMAL(10,2) DEFAULT NULL;
  DECLARE v_total INT DEFAULT 0;
  DECLARE v_allocated INT DEFAULT 0;
  DECLARE v_date DATE DEFAULT NULL;

  SELECT MAX(r.base_fare), MAX(fs.flight_date)
    INTO v_base, v_date
  FROM flight_schedules fs
  JOIN fare_rules r ON r.flight_id = fs.flight_id AND r.cabin_class = p_cabin
  WHERE fs.flight_schedule_id = p_schedule_id;

  IF v_base IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM flight_seats WHERE flight_schedule_id = p_schedule_id AND cabin_class = p_cabin;

  SELECT COUNT(*) INTO v_allocated
  FROM air_seat_allocations a
  JOIN flight_seats s ON s.flight_seat_id = a.flight_seat_id
  WHERE a.flight_schedule_id = p_schedule_id AND s.cabin_class = p_cabin;

  RETURN ROUND(
    v_base
    * (1 + 0.5 * v_allocated / GREATEST(v_total, 1))
    * CASE WHEN DATEDIFF(v_date, CURDATE()) < 7 THEN 1.3 ELSE 1.0 END, 2);
END$$

-- A4: reject an aircraft assignment that overlaps another schedule of the same aircraft
-- (45 minutes turnaround required). Called by the flight_schedules triggers.
CREATE PROCEDURE sp_air_assert_aircraft_free(
  IN p_schedule_id BIGINT UNSIGNED,
  IN p_flight_id BIGINT UNSIGNED,
  IN p_aircraft_id BIGINT UNSIGNED,
  IN p_flight_date DATE,
  IN p_status VARCHAR(12)
)
BEGIN
  DECLARE v_dep TIME DEFAULT NULL;
  DECLARE v_arr TIME DEFAULT NULL;
  DECLARE v_flight_airline BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_aircraft_airline BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_start DATETIME;
  DECLARE v_end DATETIME;
  DECLARE v_conflicts INT DEFAULT 0;

  IF p_status = 'CANCELLED' THEN
    -- A cancelled schedule does not occupy the aircraft.
    SET v_conflicts = 0;
  ELSE
    SELECT MAX(departure_time), MAX(arrival_time), MAX(airline_id)
      INTO v_dep, v_arr, v_flight_airline
    FROM flights WHERE flight_id = p_flight_id;
    SELECT MAX(airline_id) INTO v_aircraft_airline FROM aircraft WHERE aircraft_id = p_aircraft_id;

    IF v_dep IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Flight was not found.';
    END IF;
    IF v_aircraft_airline IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Aircraft was not found.';
    END IF;
    IF v_aircraft_airline <> v_flight_airline THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This aircraft belongs to a different airline than the flight.';
    END IF;

    SET v_start = TIMESTAMP(p_flight_date, v_dep);
    SET v_end = TIMESTAMP(p_flight_date, v_arr);
    IF v_arr <= v_dep THEN
      SET v_end = v_end + INTERVAL 1 DAY;   -- arrival after midnight
    END IF;

    SELECT COUNT(*) INTO v_conflicts
    FROM flight_schedules x
    JOIN flights xf ON xf.flight_id = x.flight_id
    WHERE x.aircraft_id = p_aircraft_id
      AND x.schedule_status <> 'CANCELLED'
      AND (p_schedule_id IS NULL OR x.flight_schedule_id <> p_schedule_id)
      AND TIMESTAMP(x.flight_date, xf.departure_time) < v_end + INTERVAL 45 MINUTE
      AND TIMESTAMP(x.flight_date, xf.arrival_time)
          + INTERVAL (xf.arrival_time <= xf.departure_time) DAY
          + INTERVAL 45 MINUTE > v_start;
  END IF;

  IF v_conflicts > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'This aircraft is already assigned to an overlapping flight (45-minute turnaround required).';
  END IF;
END$$

-- Booking: confirmed if a seat is free, STANDBY (priority queue) while the overbooking
-- limit allows, otherwise rejected. One transaction; the schedule row is locked.
CREATE PROCEDURE sp_air_create_booking(
  IN p_user_id BIGINT UNSIGNED,
  IN p_schedule_id BIGINT UNSIGNED,
  IN p_cabin VARCHAR(10),
  OUT p_booking_id BIGINT UNSIGNED,
  OUT p_final_status VARCHAR(20)
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_date DATE DEFAULT NULL;
  DECLARE v_overbook INT DEFAULT 0;
  DECLARE v_seat_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_fare DECIMAL(10,2) DEFAULT NULL;
  DECLARE v_waiting INT DEFAULT 0;
  DECLARE v_priority TINYINT UNSIGNED DEFAULT 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_booking_id = NULL;
  SET p_final_status = NULL;
  IF p_cabin NOT IN ('ECONOMY', 'BUSINESS') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unsupported cabin class.';
  END IF;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_count FROM railway_db.users WHERE user_id = p_user_id AND role = 'PASSENGER';
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger account was not found.';
  END IF;

  SELECT COUNT(*) INTO v_count FROM flight_schedules WHERE flight_schedule_id = p_schedule_id;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Scheduled flight was not found.';
  END IF;

  -- Serialise bookings and cancellations for this flight.
  SELECT schedule_status, flight_date, overbook_limit
    INTO v_status, v_date, v_overbook
  FROM flight_schedules
  WHERE flight_schedule_id = p_schedule_id
  FOR UPDATE;

  IF v_status NOT IN ('SCHEDULED', 'DELAYED') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight is not open for booking.';
  END IF;
  IF v_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Past flights cannot be booked.';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM flight_seats WHERE flight_schedule_id = p_schedule_id AND cabin_class = p_cabin;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight does not offer the selected cabin.';
  END IF;

  SET v_fare = fn_air_fare(p_schedule_id, p_cabin);
  IF v_fare IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No fare is configured for this flight and cabin.';
  END IF;

  SELECT MIN(s.flight_seat_id) INTO v_seat_id
  FROM flight_seats s
  WHERE s.flight_schedule_id = p_schedule_id
    AND s.cabin_class = p_cabin
    AND NOT EXISTS (
      SELECT 1 FROM air_seat_allocations a
      WHERE a.flight_schedule_id = p_schedule_id AND a.flight_seat_id = s.flight_seat_id
    );

  IF v_seat_id IS NOT NULL THEN
    INSERT INTO air_bookings (passenger_id, flight_schedule_id, cabin_class, status, fare)
    VALUES (p_user_id, p_schedule_id, p_cabin, 'CONFIRMED', v_fare);
    SET p_booking_id = LAST_INSERT_ID();

    INSERT INTO air_seat_allocations (flight_schedule_id, flight_seat_id, air_booking_id)
    VALUES (p_schedule_id, v_seat_id, p_booking_id);
    SET p_final_status = 'CONFIRMED';
  ELSE
    SELECT COUNT(*) INTO v_waiting
    FROM air_standby_entries
    WHERE flight_schedule_id = p_schedule_id AND cabin_class = p_cabin AND status = 'WAITING';
    IF v_waiting >= v_overbook THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight is full and its standby list is full.';
    END IF;

    SELECT CASE tier WHEN 'GOLD' THEN 3 WHEN 'SILVER' THEN 2 ELSE 1 END
      INTO v_priority
    FROM railway_db.users WHERE user_id = p_user_id;

    INSERT INTO air_bookings (passenger_id, flight_schedule_id, cabin_class, status, fare)
    VALUES (p_user_id, p_schedule_id, p_cabin, 'STANDBY', v_fare);
    SET p_booking_id = LAST_INSERT_ID();

    INSERT INTO air_standby_entries (air_booking_id, flight_schedule_id, cabin_class, priority_score, status)
    VALUES (p_booking_id, p_schedule_id, p_cabin, v_priority, 'WAITING');
    SET p_final_status = 'STANDBY';
  END IF;

  COMMIT;
END$$

-- Cancellation: owner check, refund slab, seat release. The AFTER INSERT trigger on
-- air_cancellations promotes the highest-priority standby booking into the freed seat.
CREATE PROCEDURE sp_air_cancel_booking(
  IN p_booking_id BIGINT UNSIGNED,
  IN p_requester_id BIGINT UNSIGNED,
  OUT p_refund DECIMAL(10,2)
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_schedule_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_lock_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_flight_date DATE DEFAULT NULL;
  DECLARE v_departure DATETIME DEFAULT NULL;
  DECLARE v_owner_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_cabin VARCHAR(10) DEFAULT NULL;
  DECLARE v_fare DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_seat_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_hours INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_refund = 0.00;
  START TRANSACTION;

  SELECT COUNT(*) INTO v_count FROM air_bookings WHERE air_booking_id = p_booking_id;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking was not found.';
  END IF;

  SELECT flight_schedule_id INTO v_schedule_id FROM air_bookings WHERE air_booking_id = p_booking_id;
  SELECT fs.flight_schedule_id, fs.flight_date, TIMESTAMP(fs.flight_date, f.departure_time)
    INTO v_lock_id, v_flight_date, v_departure
  FROM flight_schedules fs
  JOIN flights f ON f.flight_id = fs.flight_id
  WHERE fs.flight_schedule_id = v_schedule_id
  FOR UPDATE;
  IF v_flight_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Past flights cannot be cancelled through the demo application.';
  END IF;

  SELECT passenger_id, status, cabin_class, fare
    INTO v_owner_id, v_status, v_cabin, v_fare
  FROM air_bookings WHERE air_booking_id = p_booking_id FOR UPDATE;

  IF v_owner_id <> p_requester_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You may cancel only your own booking.';
  END IF;
  IF v_status = 'CANCELLED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This booking has already been cancelled.';
  END IF;

  SELECT MAX(flight_seat_id) INTO v_seat_id FROM air_seat_allocations WHERE air_booking_id = p_booking_id;
  IF v_status = 'CONFIRMED' AND v_seat_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Confirmed booking has no active seat allocation; please contact the administrator.';
  END IF;

  -- Refund: standby bookings never held a seat, so they are refunded in full.
  IF v_status = 'STANDBY' THEN
    SET p_refund = v_fare;
  ELSE
    SET v_hours = GREATEST(TIMESTAMPDIFF(HOUR, NOW(), v_departure), 0);
    SET p_refund = fn_air_refund(v_fare, v_hours);
  END IF;

  UPDATE air_bookings SET status = 'CANCELLED', refund_amount = p_refund WHERE air_booking_id = p_booking_id;

  IF v_status = 'STANDBY' THEN
    UPDATE air_standby_entries SET status = 'CANCELLED'
    WHERE air_booking_id = p_booking_id AND status = 'WAITING';
  END IF;

  IF v_seat_id IS NOT NULL THEN
    DELETE FROM air_seat_allocations WHERE air_booking_id = p_booking_id;
  END IF;

  INSERT INTO air_cancellations (air_booking_id, flight_schedule_id, cabin_class, released_flight_seat_id, refund_amount, reason)
  VALUES (p_booking_id, v_schedule_id, v_cabin, v_seat_id, p_refund, 'Passenger requested cancellation');

  COMMIT;
END$$

-- A3: add one bag to a confirmed booking. The BEFORE INSERT trigger on baggage computes the fee.
CREATE PROCEDURE sp_air_add_baggage(
  IN p_booking_id BIGINT UNSIGNED,
  IN p_requester_id BIGINT UNSIGNED,
  IN p_weight DECIMAL(5,2),
  OUT p_bag_no TINYINT UNSIGNED,
  OUT p_fee DECIMAL(10,2)
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_owner_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_date DATE DEFAULT NULL;
  DECLARE v_next INT DEFAULT 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_bag_no = NULL;
  SET p_fee = 0.00;
  IF p_weight IS NULL OR p_weight <= 0 OR p_weight > 50 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A bag must weigh more than 0 kg and at most 50 kg.';
  END IF;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_count FROM air_bookings WHERE air_booking_id = p_booking_id;
  IF v_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking was not found.';
  END IF;

  SELECT b.passenger_id, b.status, fs.flight_date
    INTO v_owner_id, v_status, v_date
  FROM air_bookings b
  JOIN flight_schedules fs ON fs.flight_schedule_id = b.flight_schedule_id
  WHERE b.air_booking_id = p_booking_id
  FOR UPDATE;

  IF v_owner_id <> p_requester_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You may add baggage only to your own booking.';
  END IF;
  IF v_status <> 'CONFIRMED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Baggage can be added only to a confirmed booking.';
  END IF;
  IF v_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This flight has already departed.';
  END IF;

  SELECT COALESCE(MAX(bag_no), 0) + 1 INTO v_next FROM baggage WHERE air_booking_id = p_booking_id;
  IF v_next > 6 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A maximum of 6 bags can be added to one booking.';
  END IF;

  INSERT INTO baggage (air_booking_id, bag_no, weight_kg) VALUES (p_booking_id, v_next, p_weight);
  SET p_bag_no = v_next;
  SELECT excess_fee INTO p_fee FROM baggage WHERE air_booking_id = p_booking_id AND bag_no = v_next;

  COMMIT;
END$$
DELIMITER ;
