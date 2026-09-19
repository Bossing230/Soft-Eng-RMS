const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/reportController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

router.get('/dashboard', ctrl.dashboardSummary); // every role gets its own tailored summary
router.get('/manager-overview', authorize('administrator', 'manager'), ctrl.managerOverview);
router.get('/sales', authorize('administrator', 'manager'), ctrl.salesReport);
router.get('/best-sellers', authorize('administrator', 'manager'), ctrl.bestSellers);
router.get('/inventory', authorize('administrator', 'manager'), ctrl.inventoryReport);
router.get('/staff-performance', authorize('administrator', 'manager'), ctrl.staffPerformance);

module.exports = router;