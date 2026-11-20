-- Inventory for the two-tab "waiting list to confirmed" demonstration (railway).
-- Run after 01-06. This file creates NO accounts and NO tickets: you register two passengers
-- yourself, in two browser tabs, and book and cancel by hand (see docs/two_tab_upgrade_demo.md).
--
-- It adds one train with exactly ONE AC seat, so the first booking is CONFIRMED and the second
-- booking on the same journey is WAITLISTED:
--   train 90004 "Demo One-Seat Express", New Delhi -> Jaipur, two days from today, class AC.
-- Re-running this file moves the journey to two days from today and clears the bookings made on it,
-- so the demonstration can be repeated.
USE railway_db;
SET @old_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

INSERT INTO trains (train_id, train_number, train_name, status) VALUES
  (4, '90004', 'Demo One-Seat Express', 'ACTIVE')
ON DUPLICATE KEY UPDATE train_number=VALUES(train_number), train_name=VALUES(train_name), status=VALUES(status);

INSERT INTO train_routes (route_id, train_id, origin_station_id, destination_station_id, distance_km) VALUES
  (6, 4, 1, 5, 310.00)
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), origin_station_id=VALUES(origin_station_id), destination_station_id=VALUES(destination_station_id), distance_km=VALUES(distance_km);

INSERT INTO train_seats (seat_id, train_id, coach_number, seat_number, class_type) VALUES
  (17, 4, 'A1', '01', 'AC')
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), coach_number=VALUES(coach_number), seat_number=VALUES(seat_number), class_type=VALUES(class_type);

INSERT INTO train_schedules (schedule_id, route_id, journey_date, departure_time, arrival_time, base_fare, booking_status) VALUES
  (1101, 6, DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:00:00', '13:30:00', 799.00, 'OPEN')
ON DUPLICATE KEY UPDATE route_id=VALUES(route_id), journey_date=VALUES(journey_date), departure_time=VALUES(departure_time), arrival_time=VALUES(arrival_time), base_fare=VALUES(base_fare), booking_status=VALUES(booking_status);

-- Reset: remove earlier bookings made on schedule 1101 (child rows first).
DROP PROCEDURE IF EXISTS sp_demo_reset_railway_one_seat;
DELIMITER $$
CREATE PROCEDURE sp_demo_reset_railway_one_seat()
BEGIN
  DECLARE v_has_ledger INT DEFAULT 0;
  SELECT COUNT(*) INTO v_has_ledger FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'transport_core' AND TABLE_NAME = 'loyalty_txn';

  -- If the shared loyalty ledger is installed (file 10), take back the points of those bookings.
  IF v_has_ledger > 0 THEN
    UPDATE users u
    JOIN (SELECT passenger_id, SUM(points) AS earned FROM transport_core.loyalty_txn
          WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101)
          GROUP BY passenger_id) x ON x.passenger_id = u.user_id
    SET u.loyalty_points = GREATEST(CAST(u.loyalty_points AS SIGNED) - x.earned, 0);
    DELETE FROM transport_core.loyalty_txn
    WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101);
  END IF;

  DELETE FROM waitlist_probability_history WHERE source_booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101);
  DELETE FROM cancellations WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101);
  DELETE FROM seat_allocations WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101);
  DELETE FROM waitlist_entries WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1101);
  DELETE FROM bookings WHERE schedule_id = 1101;
END$$
DELIMITER ;
CALL sp_demo_reset_railway_one_seat();
DROP PROCEDURE sp_demo_reset_railway_one_seat;

SET SQL_SAFE_UPDATES = @old_safe_updates;

SELECT s.schedule_id, t.train_name, st1.station_name AS origin, st2.station_name AS destination,
       s.journey_date, s.departure_time,
       (SELECT COUNT(*) FROM train_seats ts WHERE ts.train_id = t.train_id AND ts.class_type = 'AC') AS ac_seats,
       (SELECT COUNT(*) FROM bookings b WHERE b.schedule_id = s.schedule_id) AS bookings_now
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
JOIN stations st1 ON st1.station_id = r.origin_station_id
JOIN stations st2 ON st2.station_id = r.destination_station_id
WHERE s.schedule_id = 1101;
