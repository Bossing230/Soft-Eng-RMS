const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/reservationController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate, authorize('administrator', 'manager', 'cashier'));

// Fixed paths first, so they are not mistaken for a reservation id.
router.get('/board', ctrl.board);
router.get('/available-tables', ctrl.availableTables);
router.get('/', ctrl.list);
router.get('/:id', ctrl.getOne);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.patch('/:id/status', ctrl.setStatus);

module.exports = router;