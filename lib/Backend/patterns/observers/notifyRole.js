/**
 * Adds what the redesigned Orders page needs:
 *   - orders.order_type   'dine_in' | 'takeout' | 'delivery'
 *   - the 'served' value in orders.order_status (Ready -> Served -> Completed)
 *
 * It runs by itself the first time the order code touches the database (see
 * OrderRepository), so a deploy needs no manual SQL, and it is safe to run any
 * number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-order-columns.js
 *
 * Existing orders: those with a table become 'dine_in', the rest 'takeout'.
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

/** Returns true if this call added the column, false if it already existed. */
async function addColumn(sql) {
  try {
    await db.query(sql);
    return true;
  } catch (err) {
    if (err.errno !== DUPLICATE_COLUMN) throw err;
    return false;
  }
}

async function ensureOrderColumns() {
  const rows = await db.query(
    `SELECT column_name AS name, column_type AS type
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'orders'`
  );
  const columns = new Map(rows.map((r) => [String(r.name).toLowerCase(), String(r.type).toLowerCase()]));

  if (!columns.has('order_type')) {
    const added = await addColumn(
      `ALTER TABLE orders
         ADD COLUMN order_type ENUM('dine_in','takeout','delivery') NOT NULL DEFAULT 'dine_in' AFTER table_id`
    );
    // Only the process that added the column labels the old orders, so a second
    // server instance can never overwrite types chosen since.
    if (added) {
      await db.query(`UPDATE orders SET order_type = CASE WHEN table_id IS NULL THEN 'takeout' ELSE 'dine_in' END`);
    }
  }

  const statusType = columns.get('order_status') || '';
  if (statusType && !statusType.includes("'served'")) {
    await db.query(
      `ALTER TABLE orders
         MODIFY COLUMN order_status
           ENUM('pending','confirmed','preparing','ready','served','completed','cancelled')
           NOT NULL DEFAULT 'pending'`
    );
  }
}

module.exports = ensureOrderColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureOrderColumns()
    .then(() => {
      console.log('The orders table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}