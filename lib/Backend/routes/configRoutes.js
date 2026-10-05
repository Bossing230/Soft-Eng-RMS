const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/configController');
const authenticate = require('../middleware/auth');

router.use(authenticate);

router.get('/order-rates', ctrl.orderRates);

module.exports = router;