# Low waitlist probability: suggest a flight at about the same price

When a passenger is on a train waiting list and the historical chance of a confirmed seat is **very low**, the website now suggests **same-day flights between the same two cities, with a confirmed seat, at about the same price as the train ticket**, and lets the passenger book one with a single click.

## The rule

| Item | Value | Where |
|---|---|---|
| Trigger | Estimated probability is **below 30 %** (only when the estimator has enough data, i.e. at least 20 comparable cases) | `LOW_PROBABILITY_THRESHOLD_PERCENT` in `backend/src/services/flightAlternativeService.js` |
| Same journey | Flight departs from the airport in the train's origin **city** and lands in the destination **city**, on the **same date** | station and airport are matched by `stations.city = airports.city` (no new table) |
| Around the same price | Flight fare within **±25 %** of the fare of the train ticket | `PRICE_TOLERANCE` |
| Fare used | The airline module's dynamic fare `fn_air_fare` (occupancy and days-to-departure included), so it is the price the passenger would really pay | `airline_db.fn_air_fare` |
| Confirmed only | Flights with at least one free seat in that cabin; standby is not offered because it has the same uncertainty as a waiting list | seats minus allocations |
| How many | The 3 closest in price | `MAX_SUGGESTIONS` |

If the airline module (SQL files 09 to 15) is not installed, nothing is shown and the railway estimate behaves exactly as before. Because flights are matched by city, no schema change or new table was needed, so the 3NF design is unchanged.

## API

`GET /api/probability?booking_id=<id>` now also returns an `alternatives` object:

```json
{
  "canEstimate": true,
  "probabilityPercent": 12.5,
  "alternatives": {
    "triggered": true,
    "available": true,
    "thresholdPercent": 30,
    "priceTolerancePercent": 25,
    "referenceFare": 2200,
    "flights": [
      { "flight_schedule_id": 2102, "flight_number": "DS410", "cabin_class": "ECONOMY",
        "fare": 2145, "price_difference_percent": -2.5, "seats_left": 6 }
    ]
  }
}
```

The suggested flight is booked with the existing `POST /api/air/bookings/create`, so the airline rules (fare, standby, loyalty points) apply unchanged.

## Worked example: New Delhi to Lucknow

Three fictional services on the **same day**, two days from today:

| Service | Time | Class | Price | Suggested? |
|---|---|---|---|---|
| Train 90005 *Demo Festival Express* (1 AC seat) | 09:00 | AC | 2,200 | the train being waited for |
| Flight DS410 (6 economy seats) | 11:00 | Economy | 2,145 (2.5 % less) | **yes, closest price** |
| Flight DS412 (6 economy seats) | 06:15 | Economy | 1,950 (11.4 % less) | **yes** |
| Flight CA411 (3 economy seats) | 17:30 | Economy | 6,240 (184 % more) | no, outside ±25 % |

The history for this route has 24 simulated waiting-list cases (positions 1 to 2, two to three days before departure) of which only 3 were confirmed, so the estimate is **12.5 %**, well below 30 %.

### Setup

1. Install `01` to `07` and, for the flights, `09` to `15` as described in the README.
2. Run `database/18_demo_low_probability_railway.sql` (train, route, one AC seat, fare 2,200 and the 24 history rows).
3. Run `database/19_demo_low_probability_airline.sql` (the three flights).
4. Start the backend and frontend.

### Steps (two tabs, as in `two_tab_upgrade_demo.md`)

1. **Tab 1:** register passenger A. Search *New Delhi Demo Terminal* to *Lucknow Demo Station*, two days from today, class **AC**. Book train 90005: **CONFIRMED** (it has one seat).
2. **Tab 2:** register passenger B and book the same train: **WAITLISTED** at position 1.
3. **Tab 2:** the confirmation outlook appears automatically: **12.5 %**, and below it the green card **"Fly instead, at about the same price"** lists DS410 (₹2,145) and DS412 (₹1,950). CA411 is not listed.
4. **Tab 2:** press **Book this flight** on DS410. The ticket is **CONFIRMED** (open **Air booking** → *My flights*). The train waiting-list ticket stays active until passenger B cancels it.
5. Optional: have passenger A cancel the train ticket. Passenger B is promoted on the train as usual, so B can then choose which ticket to keep.

Check for a high probability: the existing one-seat train 90004 (file 16) has a high estimate for the same position, so no flight card appears there, which shows the card is shown only when the chance is low.

### Proof in SQL

```sql
USE railway_db;
-- 3 of 24 -> 12.5 %
SELECT COUNT(*) AS cases, SUM(final_outcome = 'CONFIRMED') AS confirmed,
       ROUND(100 * SUM(final_outcome = 'CONFIRMED') / COUNT(*), 1) AS probability_percent
FROM waitlist_probability_history WHERE route_id = 7 AND class_type = 'AC';

-- Flights between the same two cities on the train's date, priced within 25 % of the train fare
SELECT f.flight_number, fs.flight_schedule_id,
       airline_db.fn_air_fare(fs.flight_schedule_id, 'ECONOMY') AS flight_fare, s.base_fare AS train_fare
FROM train_schedules s
JOIN train_routes r ON r.route_id = s.route_id
JOIN stations so ON so.station_id = r.origin_station_id
JOIN stations sd ON sd.station_id = r.destination_station_id
JOIN airline_db.airports ao ON ao.city = so.city
JOIN airline_db.airports ad ON ad.city = sd.city
JOIN airline_db.flights f ON f.origin_airport_id = ao.airport_id AND f.destination_airport_id = ad.airport_id
JOIN airline_db.flight_schedules fs ON fs.flight_id = f.flight_id AND fs.flight_date = s.journey_date
WHERE s.schedule_id = 1102
  AND ABS(airline_db.fn_air_fare(fs.flight_schedule_id, 'ECONOMY') - s.base_fare) <= 0.25 * s.base_fare;
```

## What to explain

* The estimate is the same historical calculation as before; the new part only reacts to a **low** result.
* "About the same price" is a fixed band (±25 %), so a much cheaper or much dearer flight is not offered as an equivalent.
* The flight price is computed by the database function, not by the website, and is recalculated when the ticket is booked, so it can differ slightly from the price shown.
* Only confirmed seats are offered, because a standby ticket would just replace one uncertain queue by another.

## Troubleshooting

* **No flight card:** the estimate is 30 % or more, there was not enough history (under 20 cases, so no percentage is shown), the airline files `09` to `15` or `19` are missing, or the journey date has no flight within ±25 %.
* **Estimate is not 12.5 %:** file `07` was re-run after `18` (it deletes all simulated history); run `18` again. Position 1 or 2 and a journey two days ahead are needed to hit the demo group.
* **Second booking is CONFIRMED:** the one AC seat of train 90005 was free; re-run `18` to clear the bookings.
