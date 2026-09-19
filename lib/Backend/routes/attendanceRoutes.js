const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/attendanceController');
const authenticate = require('../middleware/auth');

// Every signed-in employee manages their own attendance, so no role check here.
router.use(authenticate);

router.get('/me', ctrl.me);
router.post('/clock-in', ctrl.clockIn);
router.post('/clock-out', ctrl.clockOut);
router.post('/break/start', ctrl.startBreak);
router.post('/break/end', ctrl.endBreak);

module.exports = router;