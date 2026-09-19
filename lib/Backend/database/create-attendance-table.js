/**
 * Creates the `attendance` table if it doesn't exist yet. Safe to run any
 * number of times: it never touches existing tables or data.
 *
 * Two ways to use it:
 *   1. From the command line, inside lib/Backend:
 *        node database/create-attendance-table.js
 *   2. At server start, so a deploy creates the table by itself:
 *        // in server.js, after your environment variables are loaded
 *        require('./database/create-attendance-table')()
 *          .catch((err) => console.error('attendance table check failed:', err.message));
 */

// When run directly, load .env first because DatabaseManager reads the
// connection settings as soon as it is required.
if (require.main === module) {
  try {
    require('dotenv').config();
  } catch (_) {
    // dotenv not installed: rely on variables already set in the environment.
  }
}

const db = require('../patterns/singletons/DatabaseManager');

const CREATE_ATTENDANCE_TABLE = `
  CREATE TABLE IF NOT EXISTS attendance (
    attendance_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    clock_in DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    clock_out DATETIME NULL,
    break_started_at DATETIME NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
    INDEX idx_attendance_open (employee_id, clock_out)
  )`;

async function ensureAttendanceTable() {
  await db.query(CREATE_ATTENDANCE_TABLE);
}

module.exports = ensureAttendanceTable;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureAttendanceTable()
    .then(() =>
      db.query(
        `SELECT COUNT(*) AS n FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name = 'attendance'`
      )
    )
    .then(([row]) => {
      console.log(Number(row.n) === 1 ? 'The attendance table is ready.' : 'Finished, but the attendance table was not found.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}