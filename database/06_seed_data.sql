USE railway_db;
-- All train/station names and routes below are fictional demonstration data.
-- IDs are explicit so the demo walkthrough is reproducible on a fresh database.
START TRANSACTION;

INSERT INTO stations (station_id, station_code, station_name, city) VALUES
  (1, 'NDS', 'New Delhi Demo Terminal', 'New Delhi'),
  (2, 'AGD', 'Agra Demo Junction', 'Agra'),
  (3, 'BPD', 'Bhopal Demo Central', 'Bhopal'),
  (4, 'MCD', 'Mumbai Demo Central', 'Mumbai'),
  (5, 'JPD', 'Jaipur Demo Junction', 'Jaipur'),
  (6, 'LSD', 'Lucknow Demo Station', 'Lucknow')
ON DUPLICATE KEY UPDATE station_code=VALUES(station_code), station_name=VALUES(station_name), city=VALUES(city);

INSERT INTO trains (train_id, train_number, train_name, status) VALUES
  (1, '90001', 'Capital–Coast Demo Express', 'ACTIVE'),
  (2, '90002', 'Agra Intercity Demo', 'ACTIVE'),
  (3, '90003', 'Central Connector Demo', 'ACTIVE')
ON DUPLICATE KEY UPDATE train_number=VALUES(train_number), train_name=VALUES(train_name), status=VALUES(status);

INSERT INTO train_routes (route_id, train_id, origin_station_id, destination_station_id, distance_km) VALUES
  (1, 1, 1, 4, 1380.00),
  (2, 2, 1, 2, 230.00),
  (3, 3, 2, 3, 590.00),
  (4, 1, 1, 5, 310.00),
  (5, 3, 3, 4, 780.00)
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), origin_station_id=VALUES(origin_station_id), destination_station_id=VALUES(destination_station_id), distance_km=VALUES(distance_km);

INSERT INTO train_seats (seat_id, train_id, coach_number, seat_number, class_type) VALUES
  (1, 1, 'S1', '01', 'SLEEPER'),
  (2, 1, 'S1', '02', 'SLEEPER'),
  (3, 1, 'S1', '03', 'SLEEPER'),
  (4, 1, 'A1', '01', 'AC'),
  (5, 1, 'A1', '02', 'AC'),
  (6, 2, 'C1', '01', 'CHAIR_CAR'),
  (7, 2, 'C1', '02', 'CHAIR_CAR'),
  (8, 2, 'C1', '03', 'CHAIR_CAR'),
  (9, 2, 'C1', '04', 'CHAIR_CAR'),
  (10, 2, 'S1', '01', 'SLEEPER'),
  (11, 2, 'S1', '02', 'SLEEPER'),
  (12, 3, 'S1', '01', 'SLEEPER'),
  (13, 3, 'S1', '02', 'SLEEPER'),
  (14, 3, 'S1', '03', 'SLEEPER'),
  (15, 3, 'A1', '01', 'AC'),
  (16, 3, 'A1', '02', 'AC')
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), coach_number=VALUES(coach_number), seat_number=VALUES(seat_number), class_type=VALUES(class_type);

INSERT INTO train_schedules (schedule_id, route_id, journey_date, departure_time, arrival_time, base_fare, booking_status) VALUES
  (1001, 1, DATE_ADD(CURDATE(), INTERVAL 3 DAY), '06:30:00', '08:45:00', 1299.00, 'OPEN'),
  (1002, 1, DATE_ADD(CURDATE(), INTERVAL 4 DAY), '18:15:00', '21:00:00', 1199.00, 'OPEN'),
  (1003, 2, DATE_ADD(CURDATE(), INTERVAL 2 DAY), '08:00:00', '11:00:00', 349.00, 'OPEN'),
  (1004, 3, DATE_ADD(CURDATE(), INTERVAL 5 DAY), '09:20:00', '16:40:00', 699.00, 'OPEN'),
  (1005, 4, DATE_ADD(CURDATE(), INTERVAL 3 DAY), '07:10:00', '12:30:00', 499.00, 'OPEN'),
  (1006, 5, DATE_ADD(CURDATE(), INTERVAL 6 DAY), '10:00:00', '20:30:00', 899.00, 'OPEN')
ON DUPLICATE KEY UPDATE route_id=VALUES(route_id), journey_date=VALUES(journey_date), departure_time=VALUES(departure_time), arrival_time=VALUES(arrival_time), base_fare=VALUES(base_fare), booking_status=VALUES(booking_status);

COMMIT;


-- EXPANDED DEMO NETWORK (fictional academic data; safe to re-run).
-- Adds broad city coverage, two services in each direction for every corridor,
-- 21 days of schedules, and 100 additional seats for standard network trains.
-- IDs 100-171 and schedule IDs 10000+ are reserved for this expanded network;
-- IDs used by optional one-seat demo scripts (train 4/5, route 6/7, schedules 1101/1102) stay free.

INSERT INTO stations (station_id, station_code, station_name, city) VALUES
  (7, 'MAS', 'Chennai Demo Central', 'Chennai'),
  (8, 'SBC', 'Bengaluru Demo City', 'Bengaluru'),
  (9, 'HYD', 'Hyderabad Demo Junction', 'Hyderabad'),
  (10, 'PUN', 'Pune Demo Junction', 'Pune'),
  (11, 'AMD', 'Ahmedabad Demo Central', 'Ahmedabad'),
  (12, 'KOL', 'Kolkata Demo Terminal', 'Kolkata'),
  (13, 'PAT', 'Patna Demo Junction', 'Patna'),
  (14, 'VNS', 'Varanasi Demo Junction', 'Varanasi'),
  (15, 'CDG', 'Chandigarh Demo Terminal', 'Chandigarh'),
  (16, 'ASR', 'Amritsar Demo Junction', 'Amritsar'),
  (17, 'DDN', 'Dehradun Demo Terminal', 'Dehradun'),
  (18, 'IDR', 'Indore Demo Junction', 'Indore'),
  (19, 'NGP', 'Nagpur Demo Central', 'Nagpur'),
  (20, 'STV', 'Surat Demo Terminal', 'Surat'),
  (21, 'KOC', 'Kochi Demo Junction', 'Kochi'),
  (22, 'GHY', 'Guwahati Demo Terminal', 'Guwahati'),
  (23, 'GOA', 'Goa Demo Central', 'Goa')
ON DUPLICATE KEY UPDATE station_code=VALUES(station_code), station_name=VALUES(station_name), city=VALUES(city);

INSERT INTO trains (train_id, train_number, train_name, status) VALUES
  (100, '91001', 'Capital Coast Demo Outbound Morning', 'ACTIVE'),
  (101, '91002', 'Capital Coast Demo Outbound Evening', 'ACTIVE'),
  (102, '91003', 'Capital Coast Demo Return Morning', 'ACTIVE'),
  (103, '91004', 'Capital Coast Demo Return Evening', 'ACTIVE'),
  (104, '91005', 'Pink City Demo Outbound Morning', 'ACTIVE'),
  (105, '91006', 'Pink City Demo Outbound Evening', 'ACTIVE'),
  (106, '91007', 'Pink City Demo Return Morning', 'ACTIVE'),
  (107, '91008', 'Pink City Demo Return Evening', 'ACTIVE'),
  (108, '91009', 'Yamuna Intercity Demo Outbound Morning', 'ACTIVE'),
  (109, '91010', 'Yamuna Intercity Demo Outbound Evening', 'ACTIVE'),
  (110, '91011', 'Yamuna Intercity Demo Return Morning', 'ACTIVE'),
  (111, '91012', 'Yamuna Intercity Demo Return Evening', 'ACTIVE'),
  (112, '91013', 'Awadh Link Demo Outbound Morning', 'ACTIVE'),
  (113, '91014', 'Awadh Link Demo Outbound Evening', 'ACTIVE'),
  (114, '91015', 'Awadh Link Demo Return Morning', 'ACTIVE'),
  (115, '91016', 'Awadh Link Demo Return Evening', 'ACTIVE'),
  (116, '91017', 'Ganga Capital Demo Outbound Morning', 'ACTIVE'),
  (117, '91018', 'Ganga Capital Demo Outbound Evening', 'ACTIVE'),
  (118, '91019', 'Ganga Capital Demo Return Morning', 'ACTIVE'),
  (119, '91020', 'Ganga Capital Demo Return Evening', 'ACTIVE'),
  (120, '91021', 'Kashi Express Demo Outbound Morning', 'ACTIVE'),
  (121, '91022', 'Kashi Express Demo Outbound Evening', 'ACTIVE'),
  (122, '91023', 'Kashi Express Demo Return Morning', 'ACTIVE'),
  (123, '91024', 'Kashi Express Demo Return Evening', 'ACTIVE'),
  (124, '91025', 'Northern Plains Demo Outbound Morning', 'ACTIVE'),
  (125, '91026', 'Northern Plains Demo Outbound Evening', 'ACTIVE'),
  (126, '91027', 'Northern Plains Demo Return Morning', 'ACTIVE'),
  (127, '91028', 'Northern Plains Demo Return Evening', 'ACTIVE'),
  (128, '91029', 'Doon Valley Demo Outbound Morning', 'ACTIVE'),
  (129, '91030', 'Doon Valley Demo Outbound Evening', 'ACTIVE'),
  (130, '91031', 'Doon Valley Demo Return Morning', 'ACTIVE'),
  (131, '91032', 'Doon Valley Demo Return Evening', 'ACTIVE'),
  (132, '91033', 'Punjab Mail Demo Outbound Morning', 'ACTIVE'),
  (133, '91034', 'Punjab Mail Demo Outbound Evening', 'ACTIVE'),
  (134, '91035', 'Punjab Mail Demo Return Morning', 'ACTIVE'),
  (135, '91036', 'Punjab Mail Demo Return Evening', 'ACTIVE'),
  (136, '91037', 'Deccan Connector Demo Outbound Morning', 'ACTIVE'),
  (137, '91038', 'Deccan Connector Demo Outbound Evening', 'ACTIVE'),
  (138, '91039', 'Deccan Connector Demo Return Morning', 'ACTIVE'),
  (139, '91040', 'Deccan Connector Demo Return Evening', 'ACTIVE'),
  (140, '91041', 'Western Coast Demo Outbound Morning', 'ACTIVE'),
  (141, '91042', 'Western Coast Demo Outbound Evening', 'ACTIVE'),
  (142, '91043', 'Western Coast Demo Return Morning', 'ACTIVE'),
  (143, '91044', 'Western Coast Demo Return Evening', 'ACTIVE'),
  (144, '91045', 'Konkan Coast Demo Outbound Morning', 'ACTIVE'),
  (145, '91046', 'Konkan Coast Demo Outbound Evening', 'ACTIVE'),
  (146, '91047', 'Konkan Coast Demo Return Morning', 'ACTIVE'),
  (147, '91048', 'Konkan Coast Demo Return Evening', 'ACTIVE'),
  (148, '91049', 'Eastern Ganga Demo Outbound Morning', 'ACTIVE'),
  (149, '91050', 'Eastern Ganga Demo Outbound Evening', 'ACTIVE'),
  (150, '91051', 'Eastern Ganga Demo Return Morning', 'ACTIVE'),
  (151, '91052', 'Eastern Ganga Demo Return Evening', 'ACTIVE'),
  (152, '91053', 'Southern Connector Demo Outbound Morning', 'ACTIVE'),
  (153, '91054', 'Southern Connector Demo Outbound Evening', 'ACTIVE'),
  (154, '91055', 'Southern Connector Demo Return Morning', 'ACTIVE'),
  (155, '91056', 'Southern Connector Demo Return Evening', 'ACTIVE'),
  (156, '91057', 'Deccan Southern Demo Outbound Morning', 'ACTIVE'),
  (157, '91058', 'Deccan Southern Demo Outbound Evening', 'ACTIVE'),
  (158, '91059', 'Deccan Southern Demo Return Morning', 'ACTIVE'),
  (159, '91060', 'Deccan Southern Demo Return Evening', 'ACTIVE'),
  (160, '91061', 'Coromandel Link Demo Outbound Morning', 'ACTIVE'),
  (161, '91062', 'Coromandel Link Demo Outbound Evening', 'ACTIVE'),
  (162, '91063', 'Coromandel Link Demo Return Morning', 'ACTIVE'),
  (163, '91064', 'Coromandel Link Demo Return Evening', 'ACTIVE'),
  (164, '91065', 'Malwa Intercity Demo Outbound Morning', 'ACTIVE'),
  (165, '91066', 'Malwa Intercity Demo Outbound Evening', 'ACTIVE'),
  (166, '91067', 'Malwa Intercity Demo Return Morning', 'ACTIVE'),
  (167, '91068', 'Malwa Intercity Demo Return Evening', 'ACTIVE'),
  (168, '91069', 'Central India Demo Outbound Morning', 'ACTIVE'),
  (169, '91070', 'Central India Demo Outbound Evening', 'ACTIVE'),
  (170, '91071', 'Central India Demo Return Morning', 'ACTIVE'),
  (171, '91072', 'Central India Demo Return Evening', 'ACTIVE')
ON DUPLICATE KEY UPDATE train_number=VALUES(train_number), train_name=VALUES(train_name), status=VALUES(status);

INSERT INTO train_routes (route_id, train_id, origin_station_id, destination_station_id, distance_km) VALUES
  (100, 100, 1, 4, 1380.00),
  (101, 101, 1, 4, 1380.00),
  (102, 102, 4, 1, 1380.00),
  (103, 103, 4, 1, 1380.00),
  (104, 104, 1, 5, 310.00),
  (105, 105, 1, 5, 310.00),
  (106, 106, 5, 1, 310.00),
  (107, 107, 5, 1, 310.00),
  (108, 108, 1, 2, 230.00),
  (109, 109, 1, 2, 230.00),
  (110, 110, 2, 1, 230.00),
  (111, 111, 2, 1, 230.00),
  (112, 112, 1, 6, 510.00),
  (113, 113, 1, 6, 510.00),
  (114, 114, 6, 1, 510.00),
  (115, 115, 6, 1, 510.00),
  (116, 116, 1, 13, 1000.00),
  (117, 117, 1, 13, 1000.00),
  (118, 118, 13, 1, 1000.00),
  (119, 119, 13, 1, 1000.00),
  (120, 120, 1, 14, 780.00),
  (121, 121, 1, 14, 780.00),
  (122, 122, 14, 1, 780.00),
  (123, 123, 14, 1, 780.00),
  (124, 124, 1, 15, 245.00),
  (125, 125, 1, 15, 245.00),
  (126, 126, 15, 1, 245.00),
  (127, 127, 15, 1, 245.00),
  (128, 128, 1, 17, 250.00),
  (129, 129, 1, 17, 250.00),
  (130, 130, 17, 1, 250.00),
  (131, 131, 17, 1, 250.00),
  (132, 132, 1, 16, 450.00),
  (133, 133, 1, 16, 450.00),
  (134, 134, 16, 1, 450.00),
  (135, 135, 16, 1, 450.00),
  (136, 136, 4, 10, 150.00),
  (137, 137, 4, 10, 150.00),
  (138, 138, 10, 4, 150.00),
  (139, 139, 10, 4, 150.00),
  (140, 140, 4, 11, 530.00),
  (141, 141, 4, 11, 530.00),
  (142, 142, 11, 4, 530.00),
  (143, 143, 11, 4, 530.00),
  (144, 144, 4, 23, 590.00),
  (145, 145, 4, 23, 590.00),
  (146, 146, 23, 4, 590.00),
  (147, 147, 23, 4, 590.00),
  (148, 148, 12, 13, 580.00),
  (149, 149, 12, 13, 580.00),
  (150, 150, 13, 12, 580.00),
  (151, 151, 13, 12, 580.00),
  (152, 152, 8, 7, 350.00),
  (153, 153, 8, 7, 350.00),
  (154, 154, 7, 8, 350.00),
  (155, 155, 7, 8, 350.00),
  (156, 156, 9, 8, 570.00),
  (157, 157, 9, 8, 570.00),
  (158, 158, 8, 9, 570.00),
  (159, 159, 8, 9, 570.00),
  (160, 160, 7, 9, 630.00),
  (161, 161, 7, 9, 630.00),
  (162, 162, 9, 7, 630.00),
  (163, 163, 9, 7, 630.00),
  (164, 164, 3, 18, 190.00),
  (165, 165, 3, 18, 190.00),
  (166, 166, 18, 3, 190.00),
  (167, 167, 18, 3, 190.00),
  (168, 168, 19, 3, 350.00),
  (169, 169, 19, 3, 350.00),
  (170, 170, 3, 19, 350.00),
  (171, 171, 3, 19, 350.00)
ON DUPLICATE KEY UPDATE train_id=VALUES(train_id), origin_station_id=VALUES(origin_station_id), destination_station_id=VALUES(destination_station_id), distance_km=VALUES(distance_km);

-- Increase seat inventory without changing the original physical seats.
-- Each train receives 40 SLEEPER, 24 AC and 36 CHAIR_CAR seats in additional coaches.
INSERT IGNORE INTO train_seats (train_id, coach_number, seat_number, class_type)
SELECT t.train_id,
       CONCAT(cfg.coach_prefix, FLOOR((seq.n - 1) / 10) + 2),
       LPAD(MOD(seq.n - 1, 10) + 1, 2, '0'),
       cfg.class_type
FROM trains t
CROSS JOIN (
  SELECT ones.n + tens.n * 10 + 1 AS n
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) tens
  WHERE ones.n + tens.n * 10 < 40
) seq
CROSS JOIN (
  SELECT 'SLEEPER' AS class_type, 'S' AS coach_prefix, 40 AS seat_count
  UNION ALL SELECT 'AC', 'A', 24
  UNION ALL SELECT 'CHAIR_CAR', 'CC', 36
) cfg
WHERE (t.train_id BETWEEN 1 AND 3 OR t.train_id BETWEEN 100 AND 171)
  AND seq.n <= cfg.seat_count;

-- Every expanded train has one daily schedule for the next 21 days.
-- The two services for a corridor use morning and evening departure times.
INSERT INTO train_schedules (schedule_id, route_id, journey_date, departure_time, arrival_time, base_fare, booking_status)
SELECT 10000 + (r.route_id - 100) * 21 + days.day_offset, r.route_id,
       DATE_ADD(CURDATE(), INTERVAL days.day_offset DAY),
       CASE WHEN MOD(r.route_id, 2) = 0 THEN '06:30:00' ELSE '18:15:00' END,
       CASE WHEN MOD(r.route_id, 2) = 0 THEN '14:30:00' ELSE '02:15:00' END,
       GREATEST(250.00, ROUND(r.distance_km * 0.90, 2)),
       'OPEN'
FROM train_routes r
JOIN trains t ON t.train_id = r.train_id
CROSS JOIN (
  SELECT ones.n + tens.n * 10 + 1 AS day_offset
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2) tens
  WHERE ones.n + tens.n * 10 < 21
) days
WHERE r.route_id BETWEEN 100 AND 171
  AND NOT EXISTS (
    SELECT 1 FROM train_schedules existing
    WHERE existing.route_id = r.route_id
      AND existing.journey_date = DATE_ADD(CURDATE(), INTERVAL days.day_offset DAY)
      AND existing.departure_time = CASE WHEN MOD(r.route_id, 2) = 0 THEN '06:30:00' ELSE '18:15:00' END
  );

-- FULL DIRECT-PAIR NETWORK: TWO OPTIONS PER DIRECTION, DAILY FOR 30 DAYS
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
