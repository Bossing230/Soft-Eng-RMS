const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/tableController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

router.get('/', authorize('administrator', 'manager', 'cashier'), ctrl.list);
router.post('/', authorize('administrator', 'manager'), ctrl.create);
router.put('/:id', authorize('administrator', 'manager'), ctrl.update);
router.patch('/:id/status', authorize('administrator', 'manager'), ctrl.setStatus);

module.exports = router;