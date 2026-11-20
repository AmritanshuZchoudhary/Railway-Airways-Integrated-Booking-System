# Flight Loyalty Discount Demonstration

## Policy

Loyalty points are shared by the Railway and Airways modules. Confirmed bookings earn 1 point per ₹100 of the final fare paid; cancelling a confirmed booking reverses the points previously awarded for that booking.

The Airways module applies the passenger's current tier discount to the dynamic flight fare:

| Tier | Shared loyalty points | Flight discount |
|---|---:|---:|
| BASIC | 0–999 | 0% |
| SILVER | 1,000–4,999 | 5% |
| GOLD | 5,000+ | 10% |

The discount applies only to airline bookings, not railway bookings. The tier and discount are captured when the flight booking is created. If a passenger is placed on standby, the fare benefit is retained if the passenger is later promoted.

## Stored fare breakdown

`airline_db.air_bookings` stores:

- `base_fare`: dynamic fare before the loyalty benefit.
- `loyalty_discount_percent`: percentage applied at booking time.
- `loyalty_discount_amount`: rupee amount saved.
- `loyalty_tier_at_booking`: tier used for the booking.
- `fare`: final amount payable after the discount.

Refund calculations use `fare`, so the refund is based on the discounted fare payable in the demo booking flow. Loyalty points are awarded on that net fare by the existing air-booking triggers.

## Installation / upgrade

For an existing installation, back up the `airline_db`, `railway_db`, and `transport_core` databases, then execute `database/24_air_loyalty_flight_discounts.sql` in MySQL Workbench. It is safe to rerun: it adds only missing columns, preserves all existing booking records, and recreates the flight-booking procedure and views.

After the migration, restart the backend so the updated API controller is loaded.

## Verification

Check the loyalty policy and current passenger points:

```sql
SELECT user_id, email, loyalty_points, tier
FROM railway_db.users
ORDER BY loyalty_points DESC;
```

Check saved air booking discounts:

```sql
SELECT
  air_booking_id,
  passenger_id,
  loyalty_tier_at_booking,
  base_fare,
  loyalty_discount_percent,
  loyalty_discount_amount,
  fare AS final_amount_paid,
  status
FROM airline_db.air_bookings
ORDER BY air_booking_id DESC;
```

Check total discounts granted on airline bookings:

```sql
SELECT
  COALESCE(SUM(loyalty_discount_amount), 0) AS total_flight_discounts,
  COUNT(*) AS bookings_with_discount
FROM airline_db.air_bookings
WHERE loyalty_discount_amount > 0;
```

## UI demonstration

1. Register or select a passenger account.
2. For a controlled demonstration only, an administrator may set the passenger's shared points to a test value (for example, 1,200 for SILVER or 5,200 for GOLD) in `railway_db.users`.
3. Refresh the Airways page and open **Loyalty and trips**. The active tier and flight discount table should be visible.
4. Search for a flight. Each result displays base fare, tier discount, discount amount, and final payable fare.
5. Book the flight. The booking card and unified trip history show the stored discount and final amount paid.
6. Run the SQL verification query to confirm the same breakdown is stored in MySQL.

Example only: with a dynamic base fare of ₹5,000, BASIC pays ₹5,000, SILVER saves ₹250 and pays ₹4,750, and GOLD saves ₹500 and pays ₹4,500.

The tier benefits and fares are demonstration rules for this academic project, not real airline offers.
