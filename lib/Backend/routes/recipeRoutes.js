const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/recipeController');
const authenticate = require('../middleware/auth');
const authorize = require('../middleware/rbac');

router.use(authenticate);

// Recipes are managed by Admin/Manager only.
router.get('/ingredients', authorize('administrator', 'manager'), ctrl.ingredientOptions); // before '/:menuId'
router.get('/:menuId', authorize('administrator', 'manager'), ctrl.getRecipe);
router.put('/:menuId', authorize('administrator', 'manager'), ctrl.saveRecipe);

module.exports = router;