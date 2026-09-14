const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/employeeController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');


router.use(authenticate, authorize('administrator'));

router.get('/', ctrl.list);
router.get('/:id', ctrl.getOne);
router.post('/', ctrl.create);
router.put('/:id', ctrl.update);
router.patch('/:id/status', ctrl.setStatus);
router.patch('/:id/role', ctrl.assignRole);
router.post('/:id/reset-password', ctrl.resetPassword);

module.exports = router;