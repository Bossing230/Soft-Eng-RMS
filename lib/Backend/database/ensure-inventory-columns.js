/**
 * Adds the columns the inventory page needs:
 *   - category     (text label such as "Meat")
 *   - max_stock    (the level that counts as 100% full)
 *   - expiry_date  (nullable — only perishables need it, for "Expiring Soon")
 *   - unit_cost    (nullable, defaults to 0 — for the Total Value stat)
 *   - image        (nullable — link to the item's photo, see POST /inventory/upload-image)
 *
 * It runs by itself the first time the inventory code touches the database
 * (see InventoryRepository), so a deploy needs no manual SQL. It is safe to
 * run any number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-inventory-columns.js
 *
 * The first time max_stock is added, existing items get:
 *   max_stock     = their current quantity, or higher if their old minimum
 *                   implies a bigger capacity
 *   minimum_stock = 30% of max_stock (the "low stock" line on the page)
 *   status        = recomputed from those two numbers
 *
 * expiry_date and unit_cost start empty/zero for every existing item — there
 * is no way to know a real expiry date or cost for stock already on hand, so
 * nothing is guessed. "Expiring Soon" and "Total Value" only reflect items a
 * manager has since set a date or cost for (see POST/PUT on an item).
 * image also starts empty: existing items simply have no photo yet.
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

async function ensureInventoryColumns() {
  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'inventory'`
  );
  const have = new Set(rows.map((r) => String(r.name).toLowerCase()));

  if (!have.has('category')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN category VARCHAR(50) NULL AFTER ingredient_name');
  }

  const addingMax = !have.has('max_stock');
  if (addingMax) {
    await addColumn('ALTER TABLE inventory ADD COLUMN max_stock DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER unit');
  }

  // Any item without a max gets one that is at least its current quantity.
  await db.query(
    `UPDATE inventory
        SET max_stock = GREATEST(quantity, minimum_stock / 0.3)
      WHERE max_stock = 0 AND (quantity > 0 OR minimum_stock > 0)`
  );

  if (addingMax) {
    // One-time: make the low-stock line 30% of max for the existing items.
    await db.query('UPDATE inventory SET minimum_stock = ROUND(max_stock * 0.3, 2)');
    await db.query(
      `UPDATE inventory
          SET status = CASE
                WHEN quantity <= 0 THEN 'out'
                WHEN quantity <= minimum_stock THEN 'low'
                ELSE 'ok'
              END`
    );
  }

  if (!have.has('expiry_date')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN expiry_date DATE NULL AFTER unit');
  }
  if (!have.has('unit_cost')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN unit_cost DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER max_stock');
  }
  if (!have.has('image')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN image VARCHAR(500) NULL');
  }

  // Own low-stock line for one item. NULL = use the default (30% of max stock).
  if (!have.has('reorder_level')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN reorder_level DECIMAL(10,2) NULL');
  }
  if (!have.has('supplier_name')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN supplier_name VARCHAR(100) NULL');
  }
  if (!have.has('supplier_phone')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN supplier_phone VARCHAR(30) NULL');
  }
  if (!have.has('storage_location')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN storage_location VARCHAR(50) NULL');
  }
  if (!have.has('notes')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN notes VARCHAR(500) NULL');
  }
  // Archived items are hidden everywhere (list, stats, alerts, reports) but
  // keep their history, so past orders and recipes still make sense.
  if (!have.has('is_archived')) {
    await addColumn('ALTER TABLE inventory ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0');
  }
}

/**
 * Prepares inventory_transactions for waste records:
 *   - reason            (why stock was written off, e.g. "Expired")
 *   - transaction_type  gets the new value 'waste' if it is an ENUM
 * Run it AFTER the recipe tables are ensured, since those also touch this table.
 */
async function ensureTransactionColumns() {
  const rows = await db.query(
    `SELECT column_name AS name, column_type AS col_type, is_nullable AS nullable
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'inventory_transactions'`
  );
  if (!rows.length) return; // the table does not exist yet

  const have = new Map(rows.map((r) => [String(r.name).toLowerCase(), r]));

  if (!have.has('reason')) {
    await addColumn('ALTER TABLE inventory_transactions ADD COLUMN reason VARCHAR(100) NULL');
  }

  const type = have.get('transaction_type');
  if (type && /^enum\(/i.test(type.col_type) && !/'waste'/i.test(type.col_type)) {
    const values = [...String(type.col_type).matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1]);
    const list = [...values, 'waste'].map((v) => `'${v}'`).join(',');
    const nullability = String(type.nullable).toUpperCase() === 'YES' ? 'NULL' : 'NOT NULL';
    await db.query(`ALTER TABLE inventory_transactions MODIFY COLUMN transaction_type ENUM(${list}) ${nullability}`);
  }
}

module.exports = ensureInventoryColumns;
module.exports.ensureTransactionColumns = ensureTransactionColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureInventoryColumns()
    .then(() => ensureTransactionColumns())
    .then(() => {
      console.log('The inventory table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}