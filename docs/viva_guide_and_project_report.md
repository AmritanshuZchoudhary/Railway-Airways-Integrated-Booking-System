# Railway+ — Project Report and Viva Guide

## Project title
**Railway Reservation System with Automatic Waitlist Management and Historical Confirmation Probability Estimation**

## Problem statement
Railway bookings involve related passenger, train, schedule, seat, booking, cancellation, and waitlist data. Without clear constraints and coordinated updates, seat records can become inconsistent or a released seat may not be assigned to the next eligible waitlisted passenger. This project develops a simplified relational database-backed prototype to manage those operations consistently and demonstrate SQL and transaction concepts.

## Objectives
- Maintain related passenger, route, schedule, seat, booking, cancellation, and waitlist records.
- Search schedules and calculate availability from active MySQL allocations.
- Prevent duplicate active seat assignments for the same scheduled journey.
- Create bookings using a stored procedure and transaction.
- Automatically promote the first eligible waitlisted booking when a confirmed seat is released.
- Estimate a waitlisted booking's confirmation percentage from comparable historical outcomes.
- Demonstrate SQL DDL, DML, DCL, joins, aggregate queries, views, triggers, constraints, and transaction handling.

## Modules
1. Account management and authentication.
2. Station, train, route, and schedule search.
3. Seat availability and reservation.
4. Booking cancellation and queue promotion.
5. Historical confirmation estimator.
6. Passenger dashboard, reporting, and admin metrics.

## Main tables
`users`, `stations`, `trains`, `train_routes`, `train_schedules`, `train_seats`, `bookings`, `seat_allocations`, `waitlist_entries`, `cancellations`, and `waitlist_probability_history`.

## Automatic waitlist promotion
A stored procedure locks the target schedule so bookings and cancellations for that journey are serialized. On cancellation, it validates ownership/status, removes the current allocation when a confirmed ticket is cancelled, and inserts an audit record in `cancellations`. The `AFTER INSERT` trigger checks that a seat was really released, selects the earliest `WAITING` entry for the same schedule and class, creates an allocation for the released seat, changes the booking to `CONFIRMED`, and marks the waitlist entry `PROMOTED`. These changes participate in the calling procedure's transaction. A cancellation of a waitlisted booking has no released seat and therefore cannot trigger an unrelated promotion.

## Historical probability method
For a current active waitlisted booking, the service reads the route, class, queue position, and days until departure. Position and lead time are mapped to documented bands. It counts confirmed and not-confirmed comparable history rows and excludes passenger-initiated cancellations. The first comparison group is the same route, class, position band, and lead-time band. If it has fewer than 20 outcomes, the service broadens the comparison first across all lead times for the same route/class/position band, then across routes for the same class/position band. If the sample is still below 20, it returns an insufficient-data message.

`Probability (%) = confirmed comparable cases ÷ known comparable outcomes × 100`.

The supplied records use `SIMULATED_DEMO`; they are synthetic, not railway statistics. An admin-only stored procedure can finalize the outcomes of past waitlist entries, write one `RECORDED_OUTCOME` row per source booking, and expire entries that were still waiting after departure. A unique source-booking key makes finalization idempotent. The estimate is an empirical historical ratio, not a machine-learning prediction or a guarantee.

## DBMS concepts used
- **DDL:** create database/tables and indexes.
- **DML:** insert, select, and update application records.
- **DCL:** GRANT/REVOKE examples are in `database/08_dcl_permissions.sql` and are commented until a safe password is provided.
- **Primary/foreign keys:** identify rows and protect relationships.
- **Constraints:** unique active seat allocation, unique booking allocation, supported state values, and valid queue positions.
- **Joins:** combine bookings with passengers, routes, schedules, and seats.
- **Aggregate functions:** count bookings, seats, and historical outcomes.
- **Views:** `vw_booking_overview`, `vw_schedule_occupancy`, and `vw_probability_outcome_summary`.
- **Stored procedures:** `sp_create_booking` and `sp_cancel_booking`.
- **Trigger:** `trg_promote_waitlist_after_cancellation`.
- **Transactions/locking:** coordinate multi-step updates and serialize operations by schedule.

## Suggested viva questions and answers

**Why are Passenger and Booking separate tables?**  
A passenger can make multiple bookings. A separate user/passenger record avoids repeating personal details in every booking and lets a foreign key connect the records.

**What prevents two passengers receiving the same seat?**  
A unique constraint on `(schedule_id, seat_id)` in `seat_allocations`, together with schedule-row locking in the booking procedure, prevents two active allocations for the same seat on the same schedule.

**What is the role of the trigger?**  
It automatically selects and promotes the first eligible waitlisted booking when a cancellation record identifies a released seat.

**Why is a stored procedure also used?**  
The procedure validates the operation, coordinates the transaction, handles errors, and commits or rolls back the whole cancellation workflow. The trigger participates in that same transaction.

**What if no one is on the waitlist?**  
The trigger finds no eligible row and does not create an allocation. The released seat stays available for another booking.

**What if someone cancels their waitlisted booking?**  
That booking had no allocated seat; its queue entry is marked cancelled. The cancellation record has `released_seat_id = NULL`, so the promotion trigger does nothing.

**How is the probability calculated?**  
It is the number of comparable cases confirmed before departure divided by the number of comparable known outcomes, multiplied by 100. Passenger-initiated cancellations are excluded from the denominator.

**Why is the probability not a guarantee?**  
The calculation describes historical cases, not the exact future of an individual journey. Current cancellations and demand can differ from the historical sample.

**Why does the app sometimes say there is insufficient data?**  
A comparison group needs at least 20 known outcomes. The service broadens the comparison using documented rules, and if there still are too few records it avoids presenting an unreliable percentage.

**Are the historical numbers real?**  
No. Seeded observations are clearly marked `SIMULATED_DEMO` so the feature can be demonstrated without claiming access to authentic railway data.

## Airline module (added)

The airline module is a second, separate module (database `airline_db`) that follows the same pattern as the railway module: a booking is CONFIRMED when a seat is free; otherwise it joins a queue; a cancellation releases the seat and a trigger promotes the next passenger; everything runs in one transaction.

Main tables: `airlines`, `airports`, `aircraft`, `flights`, `fare_rules`, `flight_schedules`, `flight_seats`, `air_bookings`, `air_seat_allocations`, `air_standby_entries`, `air_cancellations`, `air_booking_history`, `baggage` (weak entity: key is booking plus bag number). Shared core: `railway_db.users` (passenger, loyalty points, tier) and `transport_core.loyalty_txn`.

Novelties: A1 dynamic fare function, A2 controlled overbooking with priority standby, A3 baggage fee trigger, A4 aircraft conflict trigger, S1 unified loyalty, S2 exclusive-arc ledger, S3 unified trip history view, S4 role separation. Refunds use a time-slab function.

Viva questions and answers:

1. **How is the airline module separated from the railway module?** Separate databases (`railway_db`, `airline_db`) and separate procedures, triggers and views. No railway table references an airline table or the other way round. They meet only in the shared passenger account and the loyalty ledger.
2. **What is the difference between a waitlist and standby here?** The railway waitlist is first-in first-out. Airline standby is a priority queue: loyalty tier first, then booking time, and it is limited by `overbook_limit`.
3. **Why is the standby position not stored?** A higher-tier passenger who joins later moves ahead of others, so a stored number would go stale. The view ranks the waiting entries with `ROW_NUMBER()`.
4. **Which trigger promotes a standby passenger?** `trg_air_promote_standby_after_cancellation` runs after a row is inserted into `air_cancellations`. It is attached to the cancellation table because MySQL does not let a trigger change the table that fired it.
5. **How is a double allocation of a seat prevented?** A unique key on (`flight_schedule_id`, `flight_seat_id`) in `air_seat_allocations`, the lock on the schedule row (`SELECT ... FOR UPDATE`) in the procedure, and a single transaction.
6. **What does the exclusive arc do?** `loyalty_txn` has a CHECK that exactly one of `booking_id` (rail) and `air_booking_id` (air) is set, so one ledger row never refers to both kinds of booking or to none.
7. **Why can an aircraft not be scheduled twice?** `sp_air_assert_aircraft_free`, called by the insert and update triggers on `flight_schedules`, rejects an overlapping schedule of the same aircraft (45-minute turnaround) and an aircraft of another airline.
8. **Which concepts does baggage show?** A weak entity with a composite key, and a BEFORE INSERT trigger that computes a derived value (the fee).

## Flight alternative for low waitlist probability (added)

When the railway estimate for a waitlisted ticket is below 30 %, the API (`GET /api/probability`) also returns same-day flights between the same two cities that have a confirmed seat and a fare within ±25 % of the train fare. The passenger can book one directly through the airline procedure `sp_air_create_booking`. Worked example and steps: `docs/flight_alternative_demo.md`; data: `database/18_*.sql` and `database/19_*.sql`.

1. **How is a train journey matched to a flight?** Through the city: a station and an airport with the same `city` value. This keeps the two modules separate and needs no mapping table, so normalization is unaffected.
2. **What does "around the same price" mean?** The dynamic fare from `fn_air_fare` (A1) is within ±25 % of the fare on the train ticket. The tolerance and the 30 % threshold are constants in `flightAlternativeService.js`.
3. **Why only confirmed seats?** A standby ticket would replace one uncertain queue by another.
4. **Why is the suggestion not stored?** It is derived from the estimate, the schedule and the current fares, which change with every booking, so a stored suggestion would go stale.
5. **What if the airline module is not installed?** The query fails safely, the service returns "not available" and the railway estimate is shown as before.

## Limitations
- Academic point-to-point route model only.
- Sample train and station data are fictional.
- Probability observations are simulated and suitable only for demonstrating SQL/statistical logic.
- No integration with IRCTC, payment providers, seat quotas, PNR systems, or live railway APIs.
- The airline module covers direct flights only; no payments, no codeshare, no connecting itineraries.
- Fares, baggage allowances, refund percentages and loyalty thresholds are demonstration values.
- Railway novelties R2 (refund slabs), R3 (automatic waitlist expiry job) and R4 (distance-based fare) from the project plan are not implemented yet.


## Flight loyalty discounts

Loyalty points are shared across railway and air bookings. A confirmed booking earns 1 point for each ₹100 of the final fare paid; cancellation reverses points earned for that booking. Flight-only discount policy: BASIC (<1,000 points) 0%, SILVER (1,000-4,999 points) 5%, GOLD (5,000+ points) 10%. The discount is computed by MySQL during `sp_air_create_booking`, not accepted from the frontend. `air_bookings.fare` stores the final amount paid; `base_fare`, `loyalty_discount_percent`, `loyalty_discount_amount`, and `loyalty_tier_at_booking` preserve the price breakdown. Refunds use the discounted fare actually paid.
