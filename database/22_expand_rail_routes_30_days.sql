-- Expand the railway demo network so every ordered station pair has two direct services.
-- For every station currently in railway_db.stations, this creates two train choices
-- in each direction and a schedule for each of the next 30 calendar days (today + 29).
-- All names, distances, timings and fares are synthetic academic demo data, not real services.
-- Safe to re-run: train numbers, routes, physical seats and route/date/time schedules are upserted/idempotent.
USE railway_db;

START TRANSACTION;

-- Two distinct train services for every ordered origin/destination pair.
INSERT INTO trains (train_number, train_name, status)
SELECT
  CONCAT('TR', LPAD(o.station_id, 3, '0'), LPAD(d.station_id, 3, '0'), svc.service_no) AS train_number,
  CONCAT('Demo ', o.city, ' to ', d.city, ' ', svc.service_label) AS train_name,
  'ACTIVE'
FROM stations o
CROSS JOIN stations d
CROSS JOIN (
  SELECT 1 AS service_no, 'Morning Express' AS service_label
  UNION ALL SELECT 2, 'Afternoon Express'
) svc
WHERE o.station_id <> d.station_id
ON DUPLICATE KEY UPDATE
  train_name = VALUES(train_name),
  status = 'ACTIVE';

-- Each service gets its own route row, so the passenger sees separate train choices.
INSERT INTO train_routes (train_id, origin_station_id, destination_station_id, distance_km)
SELECT
  t.train_id,
  o.station_id,
  d.station_id,
  GREATEST(
    80.00,
    160.00
      + ABS(CAST(o.station_id AS SIGNED) - CAST(d.station_id AS SIGNED)) * 75.00
      + MOD(o.station_id * d.station_id, 90)
  ) AS distance_km
FROM stations o
CROSS JOIN stations d
CROSS JOIN (
  SELECT 1 AS service_no
  UNION ALL SELECT 2
) svc
JOIN trains t
  ON t.train_number = CONCAT('TR', LPAD(o.station_id, 3, '0'), LPAD(d.station_id, 3, '0'), svc.service_no)
WHERE o.station_id <> d.station_id
ON DUPLICATE KEY UPDATE distance_km = VALUES(distance_km);

-- Give each generated train 100 physical seats: 40 Sleeper, 24 AC and 36 Chair Car.
INSERT IGNORE INTO train_seats (train_id, coach_number, seat_number, class_type)
SELECT
  t.train_id,
  CONCAT(cfg.coach_prefix, LPAD(FLOOR((seq.seat_no - 1) / 10) + 1, 2, '0')),
  LPAD(MOD(seq.seat_no - 1, 10) + 1, 2, '0'),
  cfg.class_type
FROM trains t
CROSS JOIN (
  SELECT ones.n + tens.n * 10 + 1 AS seat_no
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) tens
) seq
CROSS JOIN (
  SELECT 'SLEEPER' AS class_type, 'S' AS coach_prefix, 40 AS seat_count
  UNION ALL SELECT 'AC', 'A', 24
  UNION ALL SELECT 'CHAIR_CAR', 'CC', 36
) cfg
WHERE t.train_number REGEXP '^TR[0-9]{7}$'
  AND seq.seat_no <= cfg.seat_count;

-- Keep a full rolling 30-day schedule window for every generated service.
-- Service 1 departs in the morning; service 2 departs in the afternoon.
INSERT INTO train_schedules
  (route_id, journey_date, departure_time, arrival_time, base_fare, booking_status)
SELECT
  r.route_id,
  DATE_ADD(CURDATE(), INTERVAL day_grid.day_offset DAY),
  CASE WHEN RIGHT(t.train_number, 1) = '1' THEN '06:30:00' ELSE '15:00:00' END,
  ADDTIME(
    CASE WHEN RIGHT(t.train_number, 1) = '1' THEN '06:30:00' ELSE '15:00:00' END,
    SEC_TO_TIME((2 + MOD(r.origin_station_id + r.destination_station_id, 5)) * 3600)
  ),
  GREATEST(250.00, ROUND(r.distance_km * 0.95, 2)),
  'OPEN'
FROM train_routes r
JOIN trains t ON t.train_id = r.train_id
CROSS JOIN (
  SELECT ones.n + tens.n * 10 AS day_offset
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2) tens
  WHERE ones.n + tens.n * 10 < 30
) day_grid
WHERE t.train_number REGEXP '^TR[0-9]{7}$'
  AND NOT EXISTS (
    SELECT 1
    FROM train_schedules existing
    WHERE existing.route_id = r.route_id
      AND existing.journey_date = DATE_ADD(CURDATE(), INTERVAL day_grid.day_offset DAY)
      AND existing.departure_time = CASE WHEN RIGHT(t.train_number, 1) = '1' THEN '06:30:00' ELSE '15:00:00' END
  );

COMMIT;

-- Verification: every ordered station pair should show at least two generated trains.
SELECT COUNT(*) AS station_count FROM stations;
SELECT COUNT(*) AS generated_train_services FROM trains WHERE train_number REGEXP '^TR[0-9]{7}$';
SELECT COUNT(*) AS generated_route_services
FROM train_routes r JOIN trains t ON t.train_id = r.train_id
WHERE t.train_number REGEXP '^TR[0-9]{7}$';
SELECT COUNT(*) AS generated_30_day_schedules
FROM train_schedules s JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
WHERE t.train_number REGEXP '^TR[0-9]{7}$'
  AND s.journey_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);

-- Example check requested by the team: Indore to Jaipur (if both stations exist).
SELECT o.city AS origin_city, d.city AS destination_city, COUNT(DISTINCT t.train_id) AS train_options
FROM stations o
JOIN train_routes r ON r.origin_station_id = o.station_id
JOIN stations d ON d.station_id = r.destination_station_id
JOIN trains t ON t.train_id = r.train_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
GROUP BY o.city, d.city;
