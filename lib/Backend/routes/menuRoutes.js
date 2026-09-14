const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/menuController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');
const upload = require('../middleware/upload');

router.use(authenticate);

// All roles can view the menu.
router.get('/', ctrl.list);
router.get('/categories', ctrl.listCategories);
router.get('/:id', ctrl.getOne);

// Only Admin/Manager can modify it.
router.post('/', authorize('administrator', 'manager'), ctrl.create);
router.put('/:id', authorize('administrator', 'manager'), ctrl.update);
router.delete('/:id', authorize('administrator', 'manager'), ctrl.remove);
router.patch('/:id/availability', authorize('administrator', 'manager'), ctrl.setAvailability);
router.post('/categories', authorize('administrator', 'manager'), ctrl.createCategory);
router.delete('/categories/:id', authorize('administrator', 'manager'), ctrl.deleteCategory);
router.post('/upload-image', authorize('administrator', 'manager'), upload.single('image'), require('../controllers/menuController').uploadImage);

module.exports = router;