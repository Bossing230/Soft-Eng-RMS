    const express = require('express');
    const router = express.Router();
    const ctrl = require('../controllers/authController');
    const authenticate = require('../middleware/auth');

    // The old checkLoginThrottle middleware is gone from this route: the new
    // per-account escalating lockout in authController.login (backed by
    // employees.failed_login_attempts / locked_until / lockout_level) now does
    // this job. If checkLoginThrottle also did something broader than per-account
    // throttling (e.g. IP-based rate limiting), that protection is no longer
    // applied here — let me know and I'll add it back alongside this.
    router.post('/login', ctrl.login);
    router.post('/logout', authenticate, ctrl.logout);
    router.get('/me', authenticate, ctrl.me);
    router.post('/change-password', authenticate, ctrl.changePassword);

    // Forgot password: 1) request a code  2) verify it  3) set the new password.
    router.post('/forgot-password/request', ctrl.requestPasswordReset);
    router.post('/forgot-password/verify', ctrl.verifyPasswordReset);
    router.post('/forgot-password/reset', ctrl.resetPasswordWithCode);

    module.exports = router;