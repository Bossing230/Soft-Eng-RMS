const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/tableController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

router.get('/', authorize('administrator', 'manager', 'cashier'), ctrl.list);
router.get('/board', authorize('administrator', 'manager', 'cashier'), ctrl.board); // before '/:id' if one is ever added
router.post('/', authorize('administrator', 'manager'), ctrl.create);
router.put('/:id', authorize('administrator', 'manager'), ctrl.update);
// Cashiers change status day to day (seat a walk-in, mark a table cleaning); only
// adding/renaming/resizing tables is limited to managers and administrators.
router.patch('/:id/status', authorize('administrator', 'manager', 'cashier'), ctrl.setStatus);

module.exports = router;