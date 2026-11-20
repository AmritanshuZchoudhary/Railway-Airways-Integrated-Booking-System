-- Novelty S4: role separation between the railway module, the airline module and passengers.
-- Roles carry no password, so this file is safe to run as it is. Creating login users needs a
-- password: replace the placeholder and uncomment the CREATE USER / GRANT ... TO lines before running.
-- Run as a sufficiently privileged MySQL administrator. Never commit real credentials to GitHub.
CREATE ROLE IF NOT EXISTS 'rail_admin', 'air_admin', 'passenger_user';

-- Each module administrator may write only to its own database.
GRANT ALL PRIVILEGES ON railway_db.* TO 'rail_admin';
GRANT ALL PRIVILEGES ON airline_db.* TO 'air_admin';
-- Both can read the shared ledger and trip history; the airline side may read passenger names and tiers.
GRANT SELECT ON transport_core.* TO 'rail_admin', 'air_admin';
GRANT SELECT (user_id, full_name, email, role, loyalty_points, tier) ON railway_db.users TO 'air_admin';

-- Passengers read views and call the booking procedures only; they cannot write tables directly.
GRANT SELECT ON railway_db.vw_booking_overview TO 'passenger_user';
GRANT SELECT ON railway_db.vw_schedule_occupancy TO 'passenger_user';
GRANT SELECT ON airline_db.vw_air_booking_overview TO 'passenger_user';
GRANT SELECT ON airline_db.vw_flight_occupancy TO 'passenger_user';
GRANT SELECT ON transport_core.v_trip_history TO 'passenger_user';
GRANT EXECUTE ON PROCEDURE railway_db.sp_create_booking TO 'passenger_user';
GRANT EXECUTE ON PROCEDURE railway_db.sp_cancel_booking TO 'passenger_user';
GRANT EXECUTE ON PROCEDURE airline_db.sp_air_create_booking TO 'passenger_user';
GRANT EXECUTE ON PROCEDURE airline_db.sp_air_cancel_booking TO 'passenger_user';
GRANT EXECUTE ON PROCEDURE airline_db.sp_air_add_baggage TO 'passenger_user';

-- Example login accounts (uncomment, set strong passwords, then run):
-- CREATE USER IF NOT EXISTS 'air_ops'@'localhost' IDENTIFIED BY 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD';
-- GRANT 'air_admin' TO 'air_ops'@'localhost';
-- SET DEFAULT ROLE 'air_admin' TO 'air_ops'@'localhost';
