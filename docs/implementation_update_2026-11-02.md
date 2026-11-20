# Implementation update — 2 November 2026

The supplied project has been enhanced for an expanded Railways + Airways academic demonstration.

- Expanded the rail network with additional city stations, 72 new directional train services, two service times per direction, 21 days of future schedules, and additional seat inventory for standard network trains. The expansion uses IDs 100+ to preserve the optional one-seat demo records.
- Expanded the air network with 17 new airports, 48 new direct flight services, dedicated aircraft, 14 days of future schedules, and 48 economy + 12 business seats per aircraft schedule. The expansion uses IDs 100+ to preserve the optional low-capacity air demo records.
- Rebuilt railway simulated probability history as a deterministic, repeatable dataset covering every seeded route, class, waitlist-position band, and days-to-departure band.
- Added the missing `air_waitlist_probability_history` table to `09_air_schema.sql`; expanded the air history seed to 30 observations per route/cabin/position/lead-time group.
- Added an authenticated Airways standby-probability API endpoint using the existing air estimator and the current priority-derived standby position.
- Added an admin endpoint to finalize completed Airways standby outcomes into recorded history.
- Updated login/register branding to explicitly welcome Railways + Airways users.
- Changed availability labels to `Available · N seats`, and waitlist/standby ranks to `WL-n` in both modules.
- Added the same historical probability card and action to Airways standby bookings.
- Removed the old `Worth knowing` sidebar cards, railway waitlist-insights navigation/explainer, and the overview method note.

All added network names and synthetic probability observations are fictional academic demonstration data. Static checks are performed locally; database imports and complete live API tests must still be run on the team's MySQL 8.0.46 instance.
