const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/orderController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

router.get('/', authorize('administrator', 'manager', 'cashier'), ctrl.list);
router.get('/board', authorize('administrator', 'manager', 'cashier'), ctrl.board); // before '/:id'
router.get('/kitchen-queue', authorize('administrator', 'manager', 'kitchen'), ctrl.kitchenQueue);
router.get('/:id', authorize('administrator', 'manager', 'cashier', 'kitchen'), ctrl.getOne);
router.post('/', authorize('administrator', 'manager', 'cashier'), ctrl.create);
// Which status each role may set is decided in the controller (see TRANSITIONS).
router.patch('/:id/status', authorize('administrator', 'manager', 'cashier', 'kitchen'), ctrl.updateStatus);
router.post('/:id/cancel', authorize('administrator', 'manager'), ctrl.cancel);

module.exports = router;