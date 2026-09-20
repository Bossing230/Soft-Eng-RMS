const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/inventoryController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate, authorize('administrator', 'manager'));

router.get('/', ctrl.list);
router.get('/low-stock', ctrl.lowStock);
router.get('/report', ctrl.report);
router.get('/:id/history', ctrl.history);
router.post('/', ctrl.create);
router.post('/restock', ctrl.restock);
router.put('/:id', ctrl.update);
router.post('/:id/adjust', ctrl.adjustStock);

module.exports = router;