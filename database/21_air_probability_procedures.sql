USE airline_db;
DROP PROCEDURE IF EXISTS sp_air_finalize_standby_history;
DELIMITER $$
CREATE PROCEDURE sp_air_finalize_standby_history(OUT p_inserted INT)
BEGIN
  INSERT INTO air_waitlist_probability_history
    (source_air_booking_id, origin_airport_id, destination_airport_id, cabin_class,
     standby_position_at_observation, days_remaining_at_observation, final_outcome,
     observation_date, data_source)
  SELECT ranked.air_booking_id, ranked.origin_airport_id, ranked.destination_airport_id,
         ranked.cabin_class, ranked.standby_position, ranked.days_remaining,
         ranked.final_outcome, ranked.observation_date, 'RECORDED_OUTCOME'
  FROM (
    SELECT b.air_booking_id, f.origin_airport_id, f.destination_airport_id,
           e.cabin_class,
           ROW_NUMBER() OVER (PARTITION BY e.flight_schedule_id, e.cabin_class
                              ORDER BY e.priority_score DESC, e.queued_at ASC, e.standby_id ASC) AS standby_position,
           GREATEST(DATEDIFF(fs.flight_date, DATE(e.queued_at)), 0) AS days_remaining,
           CASE
             WHEN EXISTS (
               SELECT 1 FROM air_booking_history h
               WHERE h.air_booking_id = b.air_booking_id AND h.event_type = 'PROMOTED'
             ) OR b.status = 'CONFIRMED' THEN 'CONFIRMED'
             WHEN b.status = 'CANCELLED' THEN 'PASSENGER_CANCELLED'
             ELSE 'NOT_CONFIRMED'
           END AS final_outcome,
           DATE(e.queued_at) AS observation_date,
           fs.flight_date,
           b.status
    FROM air_standby_entries e
    JOIN air_bookings b ON b.air_booking_id = e.air_booking_id
    JOIN flight_schedules fs ON fs.flight_schedule_id = e.flight_schedule_id
    JOIN flights f ON f.flight_id = fs.flight_id
    WHERE fs.flight_date < CURDATE()
  ) ranked
  WHERE NOT EXISTS (
    SELECT 1 FROM air_waitlist_probability_history h
    WHERE h.source_air_booking_id = ranked.air_booking_id
  );
  SET p_inserted = ROW_COUNT();
END$$
DELIMITER ;
