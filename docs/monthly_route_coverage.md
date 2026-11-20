# 30-day direct route coverage update

## What this adds

- Every ordered pair of stations currently in `railway_db.stations` gets two separate direct demo train services.
- Every generated train gets 100 seats (40 Sleeper, 24 AC, 36 Chair Car).
- Each generated train service is scheduled daily from `CURDATE()` through `CURDATE() + 29 days` (30 calendar dates).
- Every ordered pair of airports currently in `airline_db.airports` gets two separate direct demo flights.
- Each generated aircraft has 48 Economy and 12 Business seats; each generated flight is scheduled daily for the same 30-day window.
- The passenger date pickers and backend search endpoints both enforce the 30-day range. For a search on today, departures whose departure time has already passed are hidden; future dates show both daily options.

All generated trains, flights, airline assignments, distances, times, fares and schedules are synthetic academic demonstration data. They are not real transport timetables and do not imply that every pair of Indian cities has a real-world direct service.

## Existing database: apply only the additive migrations

Back up your databases first. Do not drop either database.

1. Confirm the original station and airport seed files have been run:
   - `database/06_seed_data.sql`
   - `database/14_air_seed_data.sql`
2. In MySQL Workbench, run `database/22_expand_rail_routes_30_days.sql` against the current installation. It selects `railway_db` itself.
3. Run `database/23_expand_air_routes_30_days.sql`. It selects `airline_db` itself and recreates the seat-generation trigger with a set-based insert before generating the large schedule set. This trigger change applies to future flight schedules; existing seat maps are left untouched.
4. After new routes/flights exist, optionally rerun `07_probability_history.sql` and `20_air_probability_history.sql` to generate simulated historical observations for the expanded network. These scripts replace only `SIMULATED_DEMO` rows and preserve `RECORDED_OUTCOME` rows. Large route networks can produce a substantial probability-history table, so allow the inserts to complete.
5. Restart the Express backend and Vite frontend. The search date pickers now allow today through 29 days from today.

The two migration scripts are designed to be safe to rerun: deterministic service identifiers, unique route/flight numbers, `INSERT IGNORE` seat creation, and `NOT EXISTS` date checks prevent duplicate demo services and schedules.

## Expected coverage with the currently seeded network

The base seed files currently provide 23 railway stations and 22 airports.

- Railway: 23 × 22 = 506 ordered direct station pairs; 2 services per pair = 1,012 generated trains/routes; up to 30,360 generated schedule rows in the 30-day window.
- Airways: 22 × 21 = 462 ordered direct airport pairs; 2 flights per pair = 924 generated flights; up to 27,720 generated flight schedule rows in the 30-day window.

Existing original/demo services may add more choices for some pairs. The final totals depend on how many stations/airports are in the databases when the migration runs. For the supplied 23-station and 22-airport demo data, Indore → Jaipur is included in both networks and returns two generated options for each date in the window.

## Verification SQL

### Railway: every ordered pair has at least two generated services

```sql
USE railway_db;
SELECT o.city AS origin_city, d.city AS destination_city,
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

This query should return **zero rows**.

```sql
SELECT MIN(journey_date) AS first_day, MAX(journey_date) AS last_day,
       COUNT(*) AS generated_schedules
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
WHERE t.train_number REGEXP '^TR[0-9]{7}$'
  AND s.journey_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);
```

### Airways: every ordered pair has at least two generated flights

```sql
USE airline_db;
SELECT o.city AS origin_city, d.city AS destination_city,
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

This query should return **zero rows**.

```sql
SELECT MIN(fs.flight_date) AS first_day, MAX(fs.flight_date) AS last_day,
       COUNT(*) AS generated_flight_schedules
FROM flight_schedules fs
JOIN flights f ON f.flight_id = fs.flight_id
WHERE f.flight_number REGEXP '^AX[0-9]{5}$'
  AND fs.flight_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 29 DAY);
```

### Example: Indore to Jaipur

Railway cities:

```sql
USE railway_db;
SELECT t.train_number, t.train_name, s.journey_date, s.departure_time,
       s.arrival_time, s.base_fare
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN trains t ON t.train_id = r.train_id
JOIN stations o ON o.station_id = r.origin_station_id
JOIN stations d ON d.station_id = r.destination_station_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
  AND s.journey_date = DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY s.departure_time;
```

Airports:

```sql
USE airline_db;
SELECT f.flight_number, al.airline_name, fs.flight_date,
       f.departure_time, f.arrival_time
FROM flight_schedules fs
JOIN flights f ON f.flight_id = fs.flight_id
JOIN airlines al ON al.airline_id = f.airline_id
JOIN airports o ON o.airport_id = f.origin_airport_id
JOIN airports d ON d.airport_id = f.destination_airport_id
WHERE o.city = 'Indore' AND d.city = 'Jaipur'
  AND fs.flight_date = DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY f.departure_time;
```

You should see at least two generated options in each module for the selected date.
