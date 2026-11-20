USE railway_db;

-- Synthetic academic demonstration records only; these are not real railway statistics.
-- Re-running this file replaces SIMULATED_DEMO rows and preserves RECORDED_OUTCOME rows.
SET @old_rail_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
DELETE FROM waitlist_probability_history
WHERE data_source = 'SIMULATED_DEMO';
SET SQL_SAFE_UPDATES = @old_rail_safe_updates;

-- Generate 20 observations for every route, class, queue-position band and lead-time band.
-- This gives the estimator a varied comparison group for each seeded route.
INSERT INTO waitlist_probability_history
  (route_id, class_type, waitlist_position_at_observation, days_remaining_at_observation,
   final_outcome, observation_date, data_source)
SELECT
  r.route_id,
  c.class_type,
  p.min_position + MOD(samples.n + r.route_id + c.class_offset, p.position_span),
  d.min_days + MOD(samples.n + r.route_id + c.class_offset, d.day_span),
  CASE
    WHEN MOD(samples.n + r.route_id + c.class_offset + p.band_id + d.band_id, 20) <
      GREATEST(
        0,
        LEAST(
          20,
          CAST(p.base_successes AS SIGNED)
            + CAST(d.success_adjustment AS SIGNED)
            + CAST(c.success_adjustment AS SIGNED)
            + CAST(MOD(r.route_id, 3) AS SIGNED)
            - 1
        )
      )
    THEN 'CONFIRMED'
    ELSE 'NOT_CONFIRMED'
  END,
  DATE_SUB(CURDATE(), INTERVAL (samples.n * 5 + r.route_id + d.band_id) DAY),
  'SIMULATED_DEMO'
FROM train_routes AS r
CROSS JOIN (
  SELECT 'SLEEPER' AS class_type, 0 AS class_offset, 0 AS success_adjustment
  UNION ALL SELECT 'AC', 1, 1
  UNION ALL SELECT 'CHAIR_CAR', 2, -1
) AS c
CROSS JOIN (
  SELECT 1 AS band_id, 1 AS min_position, 2 AS position_span, 17 AS base_successes
  UNION ALL SELECT 2, 3, 3, 12
  UNION ALL SELECT 3, 6, 5, 7
  UNION ALL SELECT 4, 11, 10, 3
  UNION ALL SELECT 5, 21, 10, 1
) AS p
CROSS JOIN (
  SELECT 1 AS band_id, 0 AS min_days, 2 AS day_span, -2 AS success_adjustment
  UNION ALL SELECT 2, 2, 2, 0
  UNION ALL SELECT 3, 4, 4, 1
  UNION ALL SELECT 4, 8, 23, 2
) AS d
CROSS JOIN (
  SELECT ones.n + tens.n * 10 AS n
  FROM (
    SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
  ) AS ones
  CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1) AS tens
) AS samples;

SELECT data_source, final_outcome, COUNT(*) AS observations
FROM waitlist_probability_history
GROUP BY data_source, final_outcome
ORDER BY data_source, final_outcome;
