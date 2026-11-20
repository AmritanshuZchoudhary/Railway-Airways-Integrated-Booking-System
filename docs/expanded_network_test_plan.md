# Expanded Railways + Airways route-coverage test plan

## What the expansion guarantees

For every ordered pair of distinct stations currently present in `railway_db.stations`, the migration creates two synthetic direct train services. Each service receives a schedule on every calendar date from today through today + 29 days.

For every ordered pair of distinct airports currently present in `airline_db.airports`, the migration creates two synthetic direct flights, each scheduled on the same 30-day date window.

This is a deliberately broad academic demonstration network. Generated routes, operators, flight numbers, distances, fares, timings, aircraft, and schedules are fictional; they are not real-world transport services or timetable guarantees.

## Existing databases

1. Back up `railway_db` and `airline_db`.
2. Run `database/22_expand_rail_routes_30_days.sql` in MySQL Workbench. It selects `railway_db` itself.
3. Run `database/23_expand_air_routes_30_days.sql`. It selects `airline_db` itself and installs a set-based seat-generation trigger for subsequent generated schedules.
4. Optionally run the fixed `database/07_probability_history.sql` and `database/20_air_probability_history.sql` after the route migrations if you want synthetic probability observations for every generated route. These scripts replace only `SIMULATED_DEMO` rows and preserve `RECORDED_OUTCOME` rows. With the fully expanded network, the probability datasets become large (hundreds of thousands of observations), so this is optional and may take time/storage.
5. Restart the Express backend and Vite frontend.

Do not rerun the entire `06_seed_data.sql` or `14_air_seed_data.sql` on an already populated database just to add the monthly network. Those files include the original fixed-ID demonstrations as well as the expanded network for fresh installations. Existing installations should use only migrations 22 and 23.

## Expected counts with the supplied demo stations/airports

The supplied seed data contains 23 stations and 22 airports.

- Railway: 23 × 22 = 506 ordered station pairs; two services per pair = 1,012 generated trains/routes; up to 30,360 generated schedule rows in the 30-day window. Each generated train has 100 physical seats: 40 Sleeper, 24 AC, and 36 Chair Car.
- Airways: 22 × 21 = 462 ordered airport pairs; two flights per pair = 924 generated flights; up to 27,720 dated flight schedules. Each generated flight schedule gets 60 seats (48 Economy and 12 Business), approximately 1.66 million flight-seat rows in total.

Existing original/demo services may add more results for some route/date combinations. The actual totals depend on the number of stations and airports currently present when the migrations run.

The Airways migration creates a sizeable dataset. It may take several minutes and needs sufficient MySQL disk space. It is reasonable to run the railway and air migrations separately and verify each before proceeding.

## Verify all ordered railway pairs have two services

This should return zero rows:

```sql
USE railway_db;
SELECT o.station_id AS origin_id, o.city AS origin_city,
       d.station_id AS destination_id, d.city AS destination_city,
       COUNT(DISTINCT t.train_id) AS direct_train_options
FROM stations o
CROSS JOIN stations d
LEFT JOIN train_routes r
  ON r.origin_station_id = o.station_id
 AND r.destination_station_id = d.station_id
LEFT JOIN trains t
  ON t.train_id = r.train_id
 AND t.train_number REGEXP '^TR[0-9]{7}$'
WHERE o.station_id <> d.station_id
GROUP BY o.station_id, o.city, d.station_id, d.city
HAVING COUNT(DISTINCT t.train_id) < 2;
```

## Verify all ordered airline pairs have two flights

This should return zero rows:

```sql
USE airline_db;
SELECT o.airport_id AS origin_id, o.city AS origin_city,
       d.airport_id AS destination_id, d.city AS destination_city,
       COUNT(DISTINCT f.flight_id) AS direct_flight_options
FROM airports o
CROSS JOIN airports d
LEFT JOIN flights f
  ON f.origin_airport_id = o.airport_id
 AND f.destination_airport_id = d.airport_id
 AND f.flight_number REGEXP '^AX[0-9]{5}$'
WHERE o.airport_id <> d.airport_id
GROUP BY o.airport_id, o.city, d.airport_id, d.city
HAVING COUNT(DISTINCT f.flight_id) < 2;
```

## Verify schedules in the 30-day window

```sql
USE railway_db;
SELECT MIN(s.journey_date) AS first_day, MAX(s.journey_date) AS last_day,
       COUNT(*) AS generated_schedules
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
WHERE t.train_number REGEXP '^TR[0-9]{7}$'
  AND s.journey_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);

USE airline_db;
SELECT MIN(fs.flight_date) AS first_day, MAX(fs.flight_date) AS last_day,
       COUNT(*) AS generated_flight_schedules
FROM flight_schedules fs
JOIN flights f ON f.flight_id = fs.flight_id
WHERE f.flight_number REGEXP '^AX[0-9]{5}$'
  AND fs.flight_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);
```

## Test Indore → Jaipur

### Railway (Indore station ID 18; Jaipur station ID 5 in the supplied seed)

```sql
USE railway_db;
SELECT t.train_number, t.train_name, s.journey_date,
       TIME_FORMAT(s.departure_time, '%H:%i') AS departure_time,
       TIME_FORMAT(s.arrival_time, '%H:%i') AS arrival_time,
       s.base_fare
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
JOIN stations o ON o.station_id = r.origin_station_id
JOIN stations d ON d.station_id = r.destination_station_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
  AND s.journey_date = DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY s.departure_time;
```

### Airways (Indore airport ID 17; Jaipur airport ID 3 in the supplied seed)

```sql
USE airline_db;
SELECT f.flight_number, al.airline_name, fs.flight_date,
       TIME_FORMAT(f.departure_time, '%H:%i') AS departure_time,
       TIME_FORMAT(f.arrival_time, '%H:%i') AS arrival_time
FROM flight_schedules fs
JOIN flights f ON f.flight_id = fs.flight_id
JOIN airlines al ON al.airline_id = f.airline_id
JOIN airports o ON o.airport_id = f.origin_airport_id
JOIN airports d ON d.airport_id = f.destination_airport_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
  AND fs.flight_date = DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY f.departure_time;
```

For the supplied seed, each query should return at least two generated choices for the selected date. The website displays every matching schedule returned by the search endpoint. For today's date, departures whose departure time has already passed are hidden.
