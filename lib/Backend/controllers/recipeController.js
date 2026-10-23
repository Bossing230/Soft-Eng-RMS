const RecipeRepository = require('../repositories/RecipeRepository');
const MenuRepository = require('../repositories/MenuRepository');
const { logAction } = require('../middleware/activityLogger');

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

function parseMenuId(req, res) {
  const menuId = Number(req.params.menuId);
  if (!Number.isInteger(menuId) || menuId < 1) {
    res.status(400).json({ error: 'Invalid menu item id' });
    return null;
  }
  return menuId;
}

/** Inventory items a recipe can use: name, unit, cost per unit and current stock. */
exports.ingredientOptions = async (req, res) => {
  try {
    res.json(await RecipeRepository.listIngredientOptions());
  } catch (err) {
    fail(res, err);
  }
};

/** A dish's recipe, its cost per serving, and how many servings stock can still make. */
exports.getRecipe = async (req, res) => {
  try {
    const menuId = parseMenuId(req, res);
    if (menuId === null) return;
    const item = await MenuRepository.findById(menuId);
    if (!item) return res.status(404).json({ error: 'Menu item not found' });
    res.json(await RecipeRepository.getRecipe(menuId));
  } catch (err) {
    fail(res, err);
  }
};

/** Replaces a dish's whole recipe. Send an empty list to remove it. Body: { ingredients: [{ inventoryId, quantity }] } */
exports.saveRecipe = async (req, res) => {
  try {
    const menuId = parseMenuId(req, res);
    if (menuId === null) return;
    const item = await MenuRepository.findById(menuId);
    if (!item) return res.status(404).json({ error: 'Menu item not found' });

    const ingredients = await RecipeRepository.normalize(req.body.ingredients);
    const recipe = await RecipeRepository.replaceForMenu(menuId, ingredients);
    await logAction(req.user.employeeId, `Updated recipe for menu item #${menuId}`, 'menu');
    res.json(recipe);
  } catch (err) {
    fail(res, err);
  }
};