const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/inventoryController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');
const upload = require('../middleware/upload');

router.use(authenticate);

// Kitchen staff look after the ingredients: they can add and edit them and
// record deliveries, usage and waste. Archiving, deleting, reports and the
// bulk restock stay with the administrator and manager.
const stockStaff = authorize('administrator', 'manager', 'kitchen');
const management = authorize('administrator', 'manager');

router.get('/', stockStaff, ctrl.list);
router.get('/low-stock', stockStaff, ctrl.lowStock);
router.get('/overview', stockStaff, ctrl.overview);
router.get('/report', management, ctrl.report);
router.get('/:id/history', stockStaff, ctrl.history);
router.post('/', stockStaff, ctrl.create);
router.post('/restock', management, ctrl.restock);
router.post('/upload-image', stockStaff, upload.single('image'), ctrl.uploadImage);
router.put('/:id', stockStaff, ctrl.update);
router.put('/:id/image', stockStaff, ctrl.setImage);
router.put('/:id/archive', management, ctrl.setArchived);
router.post('/:id/delete', management, ctrl.remove);
router.post('/:id/adjust', stockStaff, ctrl.adjustStock);

module.exports = router;