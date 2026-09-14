const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/paymentController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.post('/webhook/paymongo', express.json(), ctrl.paymongoWebhook); // no auth: called by PayMongo

router.use(authenticate);
router.get('/', authorize('administrator', 'manager'), ctrl.list);
router.post('/', authorize('administrator', 'manager', 'cashier'), ctrl.process);
router.get('/receipt/:orderId', authorize('administrator', 'manager', 'cashier'), ctrl.receipt);

module.exports = router;