USE airline_db;

-- Synthetic academic demonstration records only; these are not real airline statistics.
-- Re-running this file replaces SIMULATED_DEMO rows and preserves RECORDED_OUTCOME rows.
SET @old_air_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
DELETE FROM air_waitlist_probability_history
WHERE data_source = 'SIMULATED_DEMO';
SET SQL_SAFE_UPDATES = @old_air_safe_updates;

-- Generate 30 observations for every route, cabin, standby-position band and lead-time band.
-- The alias lead_band is used because LEAD is a MySQL window function name.
INSERT INTO air_waitlist_probability_history
  (origin_airport_id, destination_airport_id, cabin_class, standby_position_at_observation,
   days_remaining_at_observation, final_outcome, observation_date, data_source)
SELECT
  routes.origin_airport_id,
  routes.destination_airport_id,
  cabins.cabin_class,
  positions.min_position + MOD(samples.n + routes.origin_airport_id + routes.destination_airport_id, positions.position_span),
  lead_band.min_days + MOD(samples.n + routes.origin_airport_id, lead_band.day_span),
  CASE
    WHEN MOD(samples.n + routes.origin_airport_id + routes.destination_airport_id + cabins.class_offset + positions.band_id + lead_band.band_id, 30) <
      GREATEST(
        0,
        LEAST(
          30,
          CAST(positions.base_successes AS SIGNED)
            + CAST(lead_band.success_adjustment AS SIGNED)
            + CAST(cabins.success_adjustment AS SIGNED)
            + CAST(MOD(routes.origin_airport_id + routes.destination_airport_id, 3) AS SIGNED)
            - 1
        )
      )
    THEN 'CONFIRMED'
    ELSE 'NOT_CONFIRMED'
  END,
  DATE_SUB(CURDATE(), INTERVAL (samples.n * 4 + routes.origin_airport_id + routes.destination_airport_id + lead_band.band_id) DAY),
  'SIMULATED_DEMO'
FROM (
  SELECT DISTINCT origin_airport_id, destination_airport_id
  FROM flights
) AS routes
CROSS JOIN (
  SELECT 'ECONOMY' AS cabin_class, 0 AS class_offset, 0 AS success_adjustment
  UNION ALL SELECT 'BUSINESS', 1, -1
) AS cabins
CROSS JOIN (
  SELECT 1 AS band_id, 1 AS min_position, 2 AS position_span, 25 AS base_successes
  UNION ALL SELECT 2, 3, 3, 20
  UNION ALL SELECT 3, 6, 5, 13
  UNION ALL SELECT 4, 11, 10, 7
  UNION ALL SELECT 5, 21, 10, 3
) AS positions
CROSS JOIN (
  SELECT 1 AS band_id, 0 AS min_days, 2 AS day_span, -3 AS success_adjustment
  UNION ALL SELECT 2, 2, 2, 0
  UNION ALL SELECT 3, 4, 4, 1
  UNION ALL SELECT 4, 8, 23, 2
) AS lead_band
CROSS JOIN (
  SELECT ones.n + tens.n * 10 AS n
  FROM (
    SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
  ) AS ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2) AS tens
) AS samples;

SELECT data_source, final_outcome, COUNT(*) AS observations
FROM air_waitlist_probability_history
GROUP BY data_source, final_outcome
ORDER BY data_source, final_outcome;
