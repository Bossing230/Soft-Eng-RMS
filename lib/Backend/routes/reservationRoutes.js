const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/reservationController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate, authorize('administrator', 'manager', 'cashier'));

router.get('/', ctrl.list);
router.get('/available-tables', ctrl.availableTables);
router.get('/:id', ctrl.getOne);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.patch('/:id/status', ctrl.setStatus);

module.exports = router;