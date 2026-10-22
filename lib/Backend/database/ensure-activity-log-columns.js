/**
 * Adds what the Activity Log page needs to the activity_logs table:
 *   - ip_address  (where the request came from; empty for older entries)
 *   - device      (Windows, Android, iOS, ... read from the browser's user-agent)
 *   - two indexes so the log can be filtered by date and by employee quickly
 *
 * It runs by itself the first time something is logged (see activityLogger.js),
 * so a deploy needs no manual SQL. Safe to run any number of times. You can
 * also run it by hand from lib/Backend:
 *     node database/ensure-activity-log-columns.js
 *
 * Existing entries keep their action text and module; their IP and device stay
 * empty because they were never recorded and are not guessed.
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
const DUPLICATE_INDEX = 1061;

async function runIgnoring(sql, errno) {
  try {
    await db.query(sql);
  } catch (err) {
    // Another request or server instance added it first: that is fine.
    if (err.errno !== errno) throw err;
  }
}

async function ensureActivityLogColumns() {
  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'activity_logs'`
  );
  const have = new Set(rows.map((r) => String(r.name).toLowerCase()));

  if (!have.has('ip_address')) {
    await runIgnoring('ALTER TABLE activity_logs ADD COLUMN ip_address VARCHAR(45) NULL', DUPLICATE_COLUMN);
  }
  if (!have.has('device')) {
    await runIgnoring('ALTER TABLE activity_logs ADD COLUMN device VARCHAR(50) NULL', DUPLICATE_COLUMN);
  }

  await runIgnoring('ALTER TABLE activity_logs ADD INDEX idx_activity_time (`timestamp`)', DUPLICATE_INDEX);
  await runIgnoring(
    'ALTER TABLE activity_logs ADD INDEX idx_activity_employee_time (employee_id, `timestamp`)',
    DUPLICATE_INDEX
  );
}

module.exports = ensureActivityLogColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureActivityLogColumns()
    .then(() => {
      console.log('The activity_logs table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}