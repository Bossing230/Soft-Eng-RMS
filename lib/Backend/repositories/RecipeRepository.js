const db = require('../patterns/singletons/DatabaseManager');
const ensureInventoryColumns = require('../database/ensure-inventory-columns');
const ensureRecipeTables = require('../database/ensure-recipe-tables');

const MIN_QTY = 0.01; // inventory quantities hold 2 decimals
const MAX_QTY = 100000;

const round2 = (n) => Math.round(n * 100) / 100;
const httpError = (status, message) => Object.assign(new Error(message), { status });

class RecipeRepository {
  /** Makes sure the recipe table and the inventory cost column exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureInventoryColumns()
        .then(() => ensureRecipeTables())
        .catch((err) => {
          this._schema = null; // try again on the next request
          throw err;
        });
    }
    return this._schema;
  }

  /**
   * Every active inventory item a recipe can use (feeds the ingredient
   * dropdown). Archived items are left out.
   */
  async listIngredientOptions() {
    await this._ready();
    const rows = await db.query(
      `SELECT inventory_id, ingredient_name, unit, unit_cost, quantity
         FROM inventory
        WHERE is_archived = 0
        ORDER BY ingredient_name`
    );
    return rows.map((r) => ({
      inventory_id: r.inventory_id,
      ingredient_name: r.ingredient_name,
      unit: r.unit,
      unit_cost: Number(r.unit_cost),
      quantity: Number(r.quantity),
    }));
  }

  /**
   * Cleans and checks a list from the client: [{ inventoryId, quantity }].
   * Merges repeated ingredients, rounds to 2 decimals and confirms every item
   * exists in inventory and is not archived. Throws a 400 error with a
   * readable message otherwise.
   * An empty or missing list is fine: the dish simply has no recipe.
   */
  async normalize(ingredients) {
    await this._ready();
    if (ingredients === undefined || ingredients === null) return [];
    if (!Array.isArray(ingredients)) throw httpError(400, 'ingredients must be a list');

    const merged = new Map();
    for (const raw of ingredients) {
      const entry = raw || {};
      const inventoryId = Number(entry.inventoryId);
      const quantity = round2(Number(entry.quantity));
      if (!Number.isInteger(inventoryId) || inventoryId < 1) {
        throw httpError(400, 'Each ingredient needs an inventory item');
      }
      if (!Number.isFinite(quantity) || quantity < MIN_QTY || quantity > MAX_QTY) {
        throw httpError(400, `Each ingredient quantity must be between ${MIN_QTY} and ${MAX_QTY}`);
      }
      merged.set(inventoryId, round2((merged.get(inventoryId) || 0) + quantity));
    }

    const ids = [...merged.keys()];
    if (!ids.length) return [];
    const rows = await db.query(
      `SELECT inventory_id FROM inventory
        WHERE is_archived = 0 AND inventory_id IN (${ids.map(() => '?').join(',')})`,
      ids
    );
    if (rows.length !== ids.length) {
      throw httpError(400, 'One of the ingredients no longer exists in inventory or has been archived');
    }
    return ids.map((inventoryId) => ({ inventoryId, quantity: merged.get(inventoryId) }));
  }

  /** How many recipes use this inventory item (so its unit can be protected, and it can't be archived while in use). */
  async countUsing(inventoryId) {
    await this._ready();
    const rows = await db.query('SELECT COUNT(*) AS count FROM recipe_ingredients WHERE inventory_id = ?', [inventoryId]);
    return Number(rows[0].count);
  }

  /** Replaces a dish's whole recipe in one transaction. Pass the result of normalize(). */
  async replaceForMenu(menuId, ingredients) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();
      await conn.execute('DELETE FROM recipe_ingredients WHERE menu_id = ?', [menuId]);
      for (const { inventoryId, quantity } of ingredients) {
        await conn.execute(
          'INSERT INTO recipe_ingredients (menu_id, inventory_id, quantity) VALUES (?, ?, ?)',
          [menuId, inventoryId, quantity]
        );
      }
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
    return this.getRecipe(menuId);
  }

  /**
   * A dish's recipe with its cost per serving and how many servings the current
   * stock could still make (null when the dish has no recipe).
   */
  async getRecipe(menuId) {
    await this._ready();
    const rows = await db.query(
      `SELECT r.inventory_id, r.quantity, i.ingredient_name, i.unit, i.unit_cost, i.quantity AS in_stock
         FROM recipe_ingredients r
         JOIN inventory i ON i.inventory_id = r.inventory_id
        WHERE r.menu_id = ?
        ORDER BY i.ingredient_name`,
      [menuId]
    );

    const ingredients = rows.map((r) => {
      const quantity = Number(r.quantity);
      const unitCost = Number(r.unit_cost);
      const inStock = Number(r.in_stock);
      return {
        inventory_id: r.inventory_id,
        ingredient_name: r.ingredient_name,
        unit: r.unit,
        quantity,
        unit_cost: unitCost,
        line_cost: round2(quantity * unitCost),
        in_stock: inStock,
        servings_possible: Math.floor(inStock / quantity),
      };
    });

    return {
      menu_id: Number(menuId),
      ingredients,
      cost_per_serving: round2(ingredients.reduce((sum, i) => sum + i.line_cost, 0)),
      missing_costs: ingredients.some((i) => i.unit_cost <= 0),
      servings_available: ingredients.length ? Math.min(...ingredients.map((i) => i.servings_possible)) : null,
    };
  }
}

module.exports = new RecipeRepository();