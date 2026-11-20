-- Inventory for the "low waitlist probability -> suggest a flight at about the same price" demonstration (railway side).
-- Run after 01-07 (file 19 adds the matching flights and needs the airline module, files 09-15).
-- Like files 16 and 17 this file creates NO accounts and NO tickets: you register two passengers yourself.
--
-- It adds one train with exactly ONE AC seat on a journey that is almost never freed up:
--   train 90005 "Demo Festival Express", New Delhi -> Lucknow, two days from today, class AC, fare 2200.
--   Past waitlist outcomes for this route and class (24 simulated cases, positions 1-2, 2-3 days before
--   departure) show only 3 confirmations: 12.5 %, below the 30 % "very low" threshold.
-- The first booking is CONFIRMED, the second is WAITLISTED at position 1, and its probability card then
-- offers same-day New Delhi -> Lucknow flights priced within 25 % of 2200 (see file 19).
-- Re-running this file moves the journey to two days from today and clears the bookings made on it.
-- NOTE: file 07 deletes every SIMULATED_DEMO history row, so run this file again after re-running 07.
USE railway_db;
SET @old_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

INSERT INTO trains (train_id, train_number, train_name, status) VALUES
  (5, '90005', 'Demo Festival Express', 'ACTIVE')
ON DUPLICATE KEY UPDATE train_number=VALUES(train_number), train_name=VALUES(train_name), status=VALUES(status);

INSERT INTO train_routes (route_id, train_id, origin_station_id, destination_station_id, distance_km) VALUES
  (7, 5, 1, 6, 500.00)
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), origin_station_id=VALUES(origin_station_id), destination_station_id=VALUES(destination_station_id), distance_km=VALUES(distance_km);

INSERT INTO train_seats (seat_id, train_id, coach_number, seat_number, class_type) VALUES
  (18, 5, 'A1', '01', 'AC')
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), coach_number=VALUES(coach_number), seat_number=VALUES(seat_number), class_type=VALUES(class_type);

INSERT INTO train_schedules (schedule_id, route_id, journey_date, departure_time, arrival_time, base_fare, booking_status) VALUES
  (1102, 7, DATE_ADD(CURDATE(), INTERVAL 2 DAY), '09:00:00', '17:30:00', 2200.00, 'OPEN')
ON DUPLICATE KEY UPDATE route_id=VALUES(route_id), journey_date=VALUES(journey_date), departure_time=VALUES(departure_time), arrival_time=VALUES(arrival_time), base_fare=VALUES(base_fare), booking_status=VALUES(booking_status);

-- Reset: remove earlier bookings made on schedule 1102 (child rows first).
DROP PROCEDURE IF EXISTS sp_demo_reset_railway_low_probability;
DELIMITER $$
CREATE PROCEDURE sp_demo_reset_railway_low_probability()
BEGIN
  DECLARE v_has_ledger INT DEFAULT 0;
  SELECT COUNT(*) INTO v_has_ledger FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'transport_core' AND TABLE_NAME = 'loyalty_txn';

  IF v_has_ledger > 0 THEN
    UPDATE users u
    JOIN (SELECT passenger_id, SUM(points) AS earned FROM transport_core.loyalty_txn
          WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102)
          GROUP BY passenger_id) x ON x.passenger_id = u.user_id
    SET u.loyalty_points = GREATEST(CAST(u.loyalty_points AS SIGNED) - x.earned, 0);
    DELETE FROM transport_core.loyalty_txn
    WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102);
  END IF;

  DELETE FROM waitlist_probability_history WHERE source_booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102);
  DELETE FROM cancellations WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102);
  DELETE FROM seat_allocations WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102);
  DELETE FROM waitlist_entries WHERE booking_id IN (SELECT booking_id FROM bookings WHERE schedule_id = 1102);
  DELETE FROM bookings WHERE schedule_id = 1102;
END$$
DELIMITER ;
CALL sp_demo_reset_railway_low_probability();
DROP PROCEDURE sp_demo_reset_railway_low_probability;

-- DEMO ONLY: synthetic history, not real railway data. Only this route's simulated rows are replaced.
DELETE FROM waitlist_probability_history WHERE route_id = 7 AND data_source = 'SIMULATED_DEMO';
INSERT INTO waitlist_probability_history (route_id, class_type, waitlist_position_at_observation, days_remaining_at_observation, final_outcome, observation_date, data_source) VALUES
  (7, 'AC', 1, 3, 'NOT_CONFIRMED', '2026-10-25', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-10-18', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-10-11', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 3, 'NOT_CONFIRMED', '2026-10-04', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-09-27', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'CONFIRMED', '2026-09-20', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 3, 'NOT_CONFIRMED', '2026-09-13', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-09-06', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-08-30', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 3, 'NOT_CONFIRMED', '2026-08-23', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-08-16', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-08-09', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 3, 'NOT_CONFIRMED', '2026-08-02', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'CONFIRMED', '2026-07-26', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-07-19', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 3, 'NOT_CONFIRMED', '2026-07-12', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-07-05', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-06-28', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 3, 'NOT_CONFIRMED', '2026-06-21', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-06-14', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-06-07', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 3, 'CONFIRMED', '2026-05-31', 'SIMULATED_DEMO'),
  (7, 'AC', 1, 2, 'NOT_CONFIRMED', '2026-05-24', 'SIMULATED_DEMO'),
  (7, 'AC', 2, 2, 'NOT_CONFIRMED', '2026-05-17', 'SIMULATED_DEMO');

SET SQL_SAFE_UPDATES = @old_safe_updates;

SELECT s.schedule_id, t.train_name, st1.station_name AS origin, st2.station_name AS destination,
       s.journey_date, s.departure_time, s.base_fare,
       (SELECT COUNT(*) FROM train_seats ts WHERE ts.train_id = t.train_id AND ts.class_type = 'AC') AS ac_seats,
       (SELECT COUNT(*) FROM bookings b WHERE b.schedule_id = s.schedule_id) AS bookings_now,
       (SELECT COUNT(*) FROM waitlist_probability_history h WHERE h.route_id = r.route_id AND h.class_type = 'AC') AS history_rows,
       (SELECT SUM(h.final_outcome = 'CONFIRMED') FROM waitlist_probability_history h WHERE h.route_id = r.route_id AND h.class_type = 'AC') AS history_confirmed
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
JOIN stations st1 ON st1.station_id = r.origin_station_id
JOIN stations st2 ON st2.station_id = r.destination_station_id
WHERE s.schedule_id = 1102;
