const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/expenseController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate, authorize('administrator', 'manager'));

router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.post('/:id/delete', ctrl.remove);

module.exports = router;