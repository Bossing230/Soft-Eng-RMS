/**
 * Adds the two profile fields the Account Settings page needs to employees:
 *   - phone    (optional)
 *   - address  (optional)
 *
 * It runs by itself the first time the account code touches the database
 * (see accountController.js), so a deploy needs no manual SQL. It is safe to
 * run any number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-account-columns.js
 *
 * Existing employees simply start with both fields empty.
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

async function ensureAccountColumns() {
  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'employees'`
  );
  const have = new Set(rows.map((r) => String(r.name).toLowerCase()));

  if (!have.has('phone')) {
    await addColumn('ALTER TABLE employees ADD COLUMN phone VARCHAR(30) NULL');
  }
  if (!have.has('address')) {
    await addColumn('ALTER TABLE employees ADD COLUMN address VARCHAR(255) NULL');
  }
}

module.exports = ensureAccountColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureAccountColumns()
    .then(() => {
      console.log('The employees table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}