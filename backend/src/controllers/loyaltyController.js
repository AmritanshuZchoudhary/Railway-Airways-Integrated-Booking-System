const db = require('../config/db');
const SILVER_AT = 1000;
const GOLD_AT = 5000;

// Shared core: one loyalty balance across the railway and airline modules (novelties S1-S3).
exports.getLoyalty = async (req, res, next) => {
  try {
    const [users] = await db.query(`
      SELECT loyalty_points, tier,
        airline_db.fn_air_loyalty_discount_percent(loyalty_points) AS flight_discount_percent
      FROM railway_db.users WHERE user_id = ? LIMIT 1`, [req.user_id]);
    if (!users.length) return res.status(404).json({ error: 'Account not found.' });
    const points = Number(users[0].loyalty_points);
    const nextTier = points >= GOLD_AT ? null : points >= SILVER_AT ? 'GOLD' : 'SILVER';
    const nextAt = nextTier === 'GOLD' ? GOLD_AT : nextTier === 'SILVER' ? SILVER_AT : null;
    const flightDiscountPercent = Number(users[0].flight_discount_percent || 0);

    const [ledger] = await db.query(`
      SELECT loyalty_txn_id, points, created_at,
        CASE WHEN air_booking_id IS NULL THEN 'RAIL' ELSE 'AIR' END AS travel_mode,
        COALESCE(booking_id, air_booking_id) AS booking_ref
      FROM transport_core.loyalty_txn WHERE passenger_id = ?
      ORDER BY loyalty_txn_id DESC LIMIT 15`, [req.user_id]);

    return res.json({
      loyalty: {
        points,
        tier: users[0].tier,
        next_tier: nextTier,
        points_to_next_tier: nextAt ? Math.max(nextAt - points, 0) : 0,
        silver_at: SILVER_AT,
        gold_at: GOLD_AT,
        flight_discount_percent: flightDiscountPercent,
        flight_discount_tiers: [
          { tier: 'BASIC', minimum_points: 0, maximum_points: 999, discount_percent: 0 },
          { tier: 'SILVER', minimum_points: 1000, maximum_points: 4999, discount_percent: 5 },
          { tier: 'GOLD', minimum_points: 5000, maximum_points: null, discount_percent: 10 }
        ]
      },
      ledger
    });
  } catch (error) { return next(error); }
};

exports.getTrips = async (req, res, next) => {
  try {
    const [trips] = await db.query(`
      SELECT travel_mode, booking_ref, carrier, service_number, origin, destination, travel_date,
        departure_time, travel_class, status, fare, base_fare,
        loyalty_discount_percent, loyalty_discount_amount, booking_time
      FROM transport_core.v_trip_history WHERE passenger_id = ?
      ORDER BY booking_time DESC LIMIT 100`, [req.user_id]);
    return res.json({ trips });
  } catch (error) { return next(error); }
};
