/**
 * Adds what the recipe-based stock deduction needs:
 *   - recipe_ingredients   (which inventory items, and how much of each,
 *                           one serving of a menu item uses)
 *   - inventory_transactions.order_id  (which order caused a stock change)
 *   - inventory_transactions.transaction_type gets one new value:
 *       'return' (stock put back when an order is cancelled before cooking starts)
 *
 * Quantities in recipe_ingredients are always in the inventory item's own
 * unit (inventory.unit), so deducting never needs a unit conversion.
 *
 * Safe to run any number of times. Run by hand from lib/Backend with:
 *     node database/ensure-recipe-tables.js
 * Place this file in lib/Backend/database/.
 */
if (require.main === module) {
  try {
    require('dotenv').config();
  } catch (_) {
    // dotenv not installed: rely on variables already set in the environment.
  }
}

const db = require('../patterns/singletons/DatabaseManager');

const DUPLICATE_COLUMN = 1060;

async function addColumn(sql) {
  try {
    await db.query(sql);
  } catch (err) {
    // Another request or server instance added it first: that is fine.
    if (err.errno !== DUPLICATE_COLUMN) throw err;
  }
}

async function ensureRecipeTables() {
  await db.query(
    `CREATE TABLE IF NOT EXISTS recipe_ingredients (
       recipe_id INT AUTO_INCREMENT PRIMARY KEY,
       menu_id INT NOT NULL,
       inventory_id INT NOT NULL,
       quantity DECIMAL(10,2) NOT NULL,
       FOREIGN KEY (menu_id) REFERENCES menu_items(menu_id) ON DELETE CASCADE,
       FOREIGN KEY (inventory_id) REFERENCES inventory(inventory_id),
       UNIQUE KEY uniq_menu_inventory (menu_id, inventory_id)
     )`
  );

  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'inventory_transactions'`
  );
  const have = new Set(rows.map((r) => String(r.name).toLowerCase()));

  if (!have.has('order_id')) {
    await addColumn('ALTER TABLE inventory_transactions ADD COLUMN order_id INT NULL AFTER employee_id');
    await db.query('ALTER TABLE inventory_transactions ADD INDEX idx_inv_tx_order (order_id)').catch((err) => {
      // 1061 = index already exists
      if (err.errno !== 1061) throw err;
    });
  }

  // MODIFY with the full list is idempotent: re-running changes nothing.
  await db.query(
    `ALTER TABLE inventory_transactions
       MODIFY COLUMN transaction_type
       ENUM('delivery','usage','adjustment','return') NOT NULL`
  );
}

module.exports = ensureRecipeTables;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureRecipeTables()
    .then(() => {
      console.log('Recipe tables are up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}