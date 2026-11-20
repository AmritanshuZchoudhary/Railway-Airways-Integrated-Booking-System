const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const express = require('express');
const cors = require('cors');
const db = require('./config/db');
const authRoutes = require('./routes/authRoutes');
const scheduleRoutes = require('./routes/scheduleRoutes');
const stationRoutes = require('./routes/stationRoutes');
const bookingRoutes = require('./routes/bookingRoutes');
const dashboardRoutes = require('./routes/dashboardRoutes');
const probabilityRoutes = require('./routes/probabilityRoutes');
const airRoutes = require('./routes/airRoutes');
const loyaltyRoutes = require('./routes/loyaltyRoutes');
const { notFound, errorHandler } = require('./middleware/errorHandler');

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32 || process.env.JWT_SECRET.startsWith('replace_with_')) {
  console.error('Set JWT_SECRET in backend/.env to a random secret of at least 32 characters.');
  process.exit(1);
}

const app = express();
const allowedOrigin = process.env.CLIENT_ORIGIN || 'http://localhost:5173';
app.disable('x-powered-by');
app.use((req, res, next) => { res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('X-Frame-Options', 'DENY'); next(); });
app.use(cors({ origin: allowedOrigin, methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'], allowedHeaders: ['Content-Type', 'Authorization'] }));
app.use(express.json({ limit: '100kb' }));

app.get('/api/health', async (_req, res) => {
  try {
    await db.query('SELECT 1 AS database_ok');
    // The airline module is optional: report whether its database is installed.
    let airline = 'not installed';
    try { await db.query('SELECT 1 FROM airline_db.airlines LIMIT 1'); airline = 'connected'; } catch (_error) { /* airline SQL files 09-15 not run yet */ }
    return res.json({ status: 'ok', service: 'railway-reservation-api', database: 'connected', airline_module: airline });
  } catch (_error) {
    return res.status(503).json({ status: 'degraded', service: 'railway-reservation-api', database: 'disconnected' });
  }
});
app.use('/api/auth', authRoutes);
app.use('/api/stations', stationRoutes);
app.use('/api/schedules', scheduleRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/probability', probabilityRoutes);
app.use('/api/air', airRoutes);
app.use('/api/loyalty', loyaltyRoutes);
app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 5000);
const server = app.listen(port, () => console.log(`Railway API listening on http://localhost:${port}`));

async function shutdown(signal) {
  console.log(`${signal} received; shutting down...`);
  server.close(async () => {
    try { await db.end(); } catch (_error) { /* graceful exit */ }
    process.exit(0);
  });
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
