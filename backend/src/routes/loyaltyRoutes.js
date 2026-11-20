const router = require('express').Router();
const controller = require('../controllers/loyaltyController');
const { verifyToken } = require('../middleware/authMiddleware');
router.get('/me', verifyToken, controller.getLoyalty);
router.get('/trips', verifyToken, controller.getTrips);
module.exports = router;
