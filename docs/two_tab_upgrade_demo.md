# Waiting list to confirmed: two-tab demonstration

This shows the central idea of the project live. One passenger holds the last seat, a second passenger is on the waiting list, the first passenger cancels, and the second passenger is upgraded to CONFIRMED automatically, without refreshing the page.

You create everything by hand: **two accounts, two tabs, book, cancel.** No demo accounts or example tickets are installed.

## One-time setup

1. Install the database as described in `README.md` (files `01` to `07`; files `09` to `15` for the airline module).
2. Run the one-seat inventory files in MySQL Workbench or the `mysql` client:
   * `database/16_demo_railway_one_seat.sql`: train 90004 "Demo One-Seat Express", New Delhi to Jaipur, **one AC seat**
   * `database/17_demo_airline_one_seat.sql`: flight DS777, New Delhi to Jaipur, **one economy seat** and room for one standby passenger (needs files `09` to `15`)
3. Start the backend (`npm run dev` in `backend`) and the frontend (`npm run dev` in `frontend`).

Both journeys are scheduled **two days from today**. Running `16` and `17` again moves them to two days from today and clears the bookings made on them, so you can repeat the demonstration.

## Steps: railway

Each browser tab keeps its own login, so two different passengers can be signed in on two tabs of the same browser. Open two **new** tabs (not "Duplicate tab", which copies the login) at `http://localhost:5173`. For the best effect put them in two windows side by side.

1. **Tab 1:** register passenger A (any name, email and password), then log in.
2. **Tab 2:** register passenger B in the same way.
3. **Tab 1:** search *New Delhi Demo Terminal* to *Jaipur Demo Junction*, date two days from today, class **AC**. Book the "Demo One-Seat Express". The ticket is **CONFIRMED**.
4. **Tab 2:** run the same search and book the same train. Because the only seat is taken, the ticket is **WAITLISTED** at position 1. (Optional: use *Check estimate*.)
5. **Tab 1:** open **My tickets** and cancel passenger A's ticket.
6. **Tab 2:** within about 4 seconds (immediately when you switch to the tab) a green notice appears, the ticket is highlighted "Upgraded from the waiting list to CONFIRMED just now", and the status is **CONFIRMED**.

## Steps: airline

Use the same two accounts. In each tab choose **Air booking** in the sidebar.

1. **Tab 1:** search *New Delhi* to *Jaipur*, date two days from today, **Economy**. Two flights appear; choose **DS777** (one seat). Book it: **CONFIRMED**, seat E01.
2. **Tab 2:** the same search shows DS777 with no seats and "STANDBY OPEN". Choose *Join standby*: **STANDBY**, position 1.
3. **Tab 1:** open **My flights** and cancel the booking. The refund depends on how close the flight is.
4. **Tab 2:** the booking changes from STANDBY to **CONFIRMED** with seat E01, with the same notice and highlight.

## What to explain while it happens

* The cancel button calls a stored procedure that runs in one transaction: it marks the ticket CANCELLED, releases the seat and writes a row in the cancellation table.
* A database trigger on that cancellation row picks the first waiting passenger of the same schedule and class (railway: first come, first served; airline: loyalty tier first, then booking time), gives them the released seat and writes the history.
* The website does not decide anything. Tab 2 only asks the server for its tickets every few seconds and shows what the database now says.
* Loyalty points follow the status: points for the cancelled confirmed ticket are taken back, and the promoted passenger earns points when their ticket becomes CONFIRMED.

## Proof in SQL (optional)

```sql
USE railway_db;
SELECT booking_id, passenger_id, status FROM bookings WHERE schedule_id = 1101;
SELECT * FROM cancellations ORDER BY cancellation_id DESC LIMIT 1;
SELECT * FROM seat_allocations WHERE schedule_id = 1101;

USE airline_db;
SELECT passenger_name, booking_status, seat_no, standby_position FROM vw_air_booking_overview WHERE flight_schedule_id = 2101;
SELECT air_booking_id, old_status, new_status, event_type FROM air_booking_history ORDER BY history_id DESC LIMIT 6;
```

## Troubleshooting

* **Both tabs show the same person:** the tab was duplicated. Log out in that tab and log in as the other passenger.
* **The second booking is CONFIRMED instead of waitlisted:** the one-seat journey already had a cancelled booking, or you booked a different train or flight. Re-run `16` / `17` and use the one-seat train 90004 or flight DS777.
* **A tab never updates:** background tabs pause timers in some browsers; the tab refreshes as soon as you switch to it.
* **Login screen after closing a tab:** by design. The login lives in `sessionStorage`, so closing a tab signs it out.
