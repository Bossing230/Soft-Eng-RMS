const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/authController');
const authenticate = require('../middleware/auth');
const { checkLoginThrottle } = require('../middleware/activityLogger');

router.post('/login', checkLoginThrottle, ctrl.login);
router.post('/logout', authenticate, ctrl.logout);
router.get('/me', authenticate, ctrl.me);
router.post('/change-password', authenticate, ctrl.changePassword);
router.post('/forgot-password', ctrl.forgotPassword);
router.post('/reset-password', ctrl.resetPassword);

module.exports = router;