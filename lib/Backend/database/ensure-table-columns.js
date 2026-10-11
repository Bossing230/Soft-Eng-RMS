/**
 * Adds what the redesigned Tables page needs:
 *   - tables.location   free text, e.g. 'indoor' / 'outdoor' (defaults to 'indoor')
 *   - the 'cleaning' value in tables.status, alongside available/occupied/reserved
 *
 * It runs by itself the first time the table code touches the database (see
 * TableRepository), so a deploy needs no manual SQL, and it is safe to run any
 * number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-table-columns.js
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
    if (err.errno !== DUPLICATE_COLUMN) throw err; // already added by another server instance
  }
}

async function ensureTableColumns() {
  const rows = await db.query(
    `SELECT column_name AS name, column_type AS type
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'tables'`
  );
  const columns = new Map(rows.map((r) => [String(r.name).toLowerCase(), String(r.type).toLowerCase()]));

  if (!columns.has('location')) {
    await addColumn("ALTER TABLE tables ADD COLUMN location VARCHAR(20) NOT NULL DEFAULT 'indoor' AFTER capacity");
  }

  const statusType = columns.get('status') || '';
  if (statusType && !statusType.includes("'cleaning'")) {
    await db.query(
      `ALTER TABLE tables
         MODIFY COLUMN status ENUM('available','occupied','reserved','cleaning') NOT NULL DEFAULT 'available'`
    );
  }
}

module.exports = ensureTableColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureTableColumns()
    .then(() => {
      console.log('The tables table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}