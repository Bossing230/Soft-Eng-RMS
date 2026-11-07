const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/supplierController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

// Kitchen staff can read the list (for the supplier picker on an ingredient);
// only the manager and administrator can change it.
router.get('/', authorize('administrator', 'manager', 'kitchen'), ctrl.list);
router.post('/', authorize('administrator', 'manager'), ctrl.create);
router.put('/:id', authorize('administrator', 'manager'), ctrl.update);
router.post('/:id/delete', authorize('administrator', 'manager'), ctrl.remove);

module.exports = router;