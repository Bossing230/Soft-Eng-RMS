const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/notificationController');
const authenticate = require('../middleware/auth');

router.use(authenticate);

router.get('/', ctrl.list);                // the bell's list: GET /api/notifications?unreadOnly=false
router.patch('/read-all', ctrl.markAllRead); // "Mark all read"
router.patch('/:id/read', ctrl.markRead);    // tapping one notification

module.exports = router;