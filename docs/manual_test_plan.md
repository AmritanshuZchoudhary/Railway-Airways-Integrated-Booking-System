# Manual database and website test plan

Run these tests on a dedicated project database populated with the supplied demo data. Use at least four registered passenger accounts for the queue walkthrough.

| Test | Steps | Expected result |
|---|---|---|
| Register | Create account from the website | A `users` row is created with a bcrypt hash and PASSENGER role |
| Search | Select New Delhi Demo Terminal → Mumbai Demo Central, date 3 days ahead, SLEEPER | Demo schedule 1001 appears with 3 seats initially available |
| Seat reservation | Book the first three tickets from three accounts | Each booking is CONFIRMED with a different seat allocation |
| Waitlist | Book a fourth SLEEPER ticket for schedule 1001 | Booking is WAITLISTED, with queue position 1 |
| Probability | Check probability for the active waitlisted booking | Route/class/position/time history is queried; demo group has enough records for a percentage |
| Automatic promotion | Cancel one of the first three confirmed bookings from its owner's account | Cancellation record stores released seat; database trigger confirms first waiter and allocates the released seat |
| FIFO | Have a fifth account join the waitlist before canceling another confirmed booking | The earliest still-WAITING queue position is promoted first |
| Cancel waiter | Cancel a WAITLISTED booking | Its queue entry becomes CANCELLED and no other booking is promoted because no seat was released |
| Double cancel | Cancel the same booking again | API returns a validation error; no extra cancellation record is created |
| Owner check | Try to cancel another account's booking | API returns a permission error; no data changes |
| No eligible waiter | Cancel a confirmed booking when no one is waiting | The released seat remains available |
| Estimate data threshold | Temporarily test a route/class/position without enough known history | API returns insufficient-data message; no made-up percentage appears |
| Admin role | Promote own account with local make-admin script, sign in again | Admin console shows live MySQL counts |
| Historical finalization | Ensure a demo schedule date is before today and it has waitlist entries, then click **Finalize past outcomes** as admin | Known outcomes are inserted once with `RECORDED_OUTCOME`; remaining waiting entries expire; re-running does not duplicate history |

## Airline module tests (SQL files 09 to 15 installed)

Use five or more registered passenger accounts and one administrator. Schedule 2001 (flight DS101, New Delhi Demo Airport to Mumbai Demo Airport, three days ahead) has 4 economy seats and a standby limit of 2.

| Test | Steps | Expected result |
|---|---|---|
| Search | Open **Air booking**, search NDA to MBA three days ahead, ECONOMY | Flight DS101 appears with 4 seats left and a fare computed by the database |
| Dynamic fare (A1) | Book four tickets one after another and compare fares | Each fare is higher than the previous one (occupancy factor); with a flight under 7 days away the 1.3 time factor is included |
| Seat reservation | Book with four accounts | Four CONFIRMED bookings with seats E01 to E04 |
| Standby (A2) | Book with a fifth and sixth account | Both bookings are STANDBY with positions 1 and 2 |
| Standby limit | Book with a seventh account | Rejected: the flight and its standby list are full; no booking row is created |
| Priority | Before the standby step, give the sixth account 5000 points (`UPDATE railway_db.users SET loyalty_points = 5200 WHERE email = '...'`), then join standby with the fifth account first and the sixth second | The sixth account (GOLD) is standby position 1, the fifth is position 2 |
| Automatic promotion | Cancel one confirmed booking from its owner's account | The cancellation row stores the released seat; the trigger promotes the top standby booking, which receives the seat and shows CONFIRMED |
| Refund slab | Look at the refund shown after cancelling a flight more than 48 hours away | 90 % of the fare; a standby booking is refunded in full |
| Baggage (A3) | Add a 10 kg bag and then a 10 kg bag to a confirmed economy booking | First bag free, second bag has 5 kg excess, fee 2000 rupees |
| Baggage rules | Add a bag to a standby booking, and a 60 kg bag | Both rejected with a validation message |
| Aircraft conflict (A4) | As admin, create a schedule for DS150 with aircraft VT-DS01 on the same date as DS101 | Rejected: overlapping flight on the same aircraft |
| Airline mismatch | Create DS150 with aircraft VT-CA01 | Rejected: aircraft belongs to a different airline |
| Seat map | Create DS150 with aircraft VT-DS02 | Created with 6 generated seats |
| Loyalty (S1) | Confirm a railway booking and an air booking, open **Loyalty and trips** | One balance with 1 point per 100 rupees of fare; ledger rows show RAIL and AIR |
| Loyalty reversal | Cancel the confirmed booking | A negative ledger row of the same size; balance goes back down |
| Trip history (S3) | Open **Loyalty and trips** | Railway and airline bookings of the account in one list |
| Owner check | Cancel or add baggage to another account's booking | Permission error; no data changes |
| Two-tab upgrade (railway) | Run `16_demo_railway_one_seat.sql`. Register two passengers, one per tab. Both search New Delhi to Jaipur two days from today, class AC, and book train 90004; then cancel the first passenger's ticket | First booking CONFIRMED, second WAITLISTED position 1; after the cancellation the second tab shows a notice within about 4 seconds, highlights the ticket and shows CONFIRMED |
| Two-tab upgrade (airline) | Run `17_demo_airline_one_seat.sql`. With the same two accounts open **Air booking**, search New Delhi to Jaipur two days from today, economy, and book flight DS777 in both tabs; then cancel the first passenger's booking | First booking CONFIRMED (seat E01), second STANDBY position 1; after the cancellation the second booking becomes CONFIRMED with seat E01 and the first passenger's refund follows the time slab |
| Flight alternative (low probability) | Run `18` and `19`. Register two passengers in two tabs. Both book train 90005 (New Delhi to Lucknow, two days from today, class AC); passenger B is WAITLISTED | B's probability card shows 12.5 %, and the card **Fly instead, at about the same price** lists DS410 (about 2145) and DS412 (about 1950); CA411 (about 6240) is not listed |
| Flight alternative booking | Press **Book this flight** on DS410 as passenger B | Flight booking is CONFIRMED and appears under **Air booking**; the train waitlist ticket stays WAITLISTED until cancelled |
| No suggestion when probability is high | Run `16`, book train 90004 AC with two accounts and check the probability of the waitlisted one | No flight card is shown |
| Flights outside the price band | Change the base fare of train schedule 1102 to 800 (`UPDATE train_schedules SET base_fare = 800 WHERE schedule_id = 1102`) and re-check B's probability | The card says that no same-day flight costs within ±25 % of the train fare |
| Airline module absent | Skip files 09 to 15 and check a low-probability waitlist | Estimate still shown; no flight card and no error |
| Separate logins per tab | Log in as different users in two tabs of one browser and refresh both | Each tab keeps its own user; closing a tab signs that tab out |
| Railway unaffected | Run the railway walkthrough above again | Same results as before; the railway pages still work |

## Useful SQL for the teacher demonstration

```sql
USE railway_db;
SELECT * FROM bookings ORDER BY booking_id DESC;
SELECT * FROM seat_allocations ORDER BY schedule_id, seat_id;
SELECT * FROM waitlist_entries ORDER BY schedule_id, class_type, queue_position;
SELECT * FROM cancellations ORDER BY cancellation_id DESC;
SELECT * FROM vw_schedule_occupancy ORDER BY journey_date, train_number;
SELECT * FROM vw_probability_outcome_summary ORDER BY route_id, class_type, position_band;
SHOW TRIGGERS;
SHOW PROCEDURE STATUS WHERE Db = 'railway_db';
```

A cancellation test must be performed by the account that owns the confirmed booking; the procedure intentionally enforces ownership.

Airline module queries:

```sql
USE airline_db;
SELECT * FROM vw_air_booking_overview ORDER BY air_booking_id DESC;   -- includes derived standby_position
SELECT * FROM vw_flight_occupancy ORDER BY flight_date, flight_number;
SELECT * FROM air_standby_entries ORDER BY flight_schedule_id, status, priority_score DESC, queued_at;
SELECT * FROM air_booking_history ORDER BY history_id DESC;
SELECT * FROM baggage;
SELECT fn_air_fare(2001, 'ECONOMY') AS current_fare;
SELECT * FROM transport_core.loyalty_txn ORDER BY loyalty_txn_id DESC;
SELECT * FROM transport_core.v_trip_history WHERE passenger_id = 1;
SHOW TRIGGERS FROM airline_db;
```
