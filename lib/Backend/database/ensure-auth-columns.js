/**
 * Adds what the escalating-lockout, forgot-password and new-employee email
 * verification flows need:
 *   - employees.lockout_level   how many times in a row this account has
 *                                hit 3 wrong passwords since its last real
 *                                password change (0 = never, or just reset)
 *   - password_resets table     one row per 6-digit code that was emailed
 *                                out, so a code can be checked and expired
 *                                without ever storing it in plain text
 *   - email_verifications table the same, for an address that does not have
 *                                an account yet (new employee being created)
 *
 * employees.failed_login_attempts and employees.locked_until already exist
 * in schema.sql — they were provisioned but unused until now.
 *
 * It runs by itself the first time the auth code touches the database (see
 * EmployeeRepository), so a deploy needs no manual SQL, and it is safe to
 * run any number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-auth-columns.js
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

async function ensureAuthColumns() {
  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'employees'`
  );
  const has = new Set(rows.map((r) => String(r.name).toLowerCase()));

  if (!has.has('lockout_level')) {
    await addColumn('ALTER TABLE employees ADD COLUMN lockout_level INT NOT NULL DEFAULT 0 AFTER locked_until');
  }

  await db.query(
    `CREATE TABLE IF NOT EXISTS password_resets (
       reset_id INT AUTO_INCREMENT PRIMARY KEY,
       employee_id INT NOT NULL,
       code_hash VARCHAR(255) NOT NULL,
       expires_at DATETIME NOT NULL,
       attempts INT NOT NULL DEFAULT 0,
       used TINYINT(1) NOT NULL DEFAULT 0,
       created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
       FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
       INDEX idx_password_resets_employee (employee_id, used, expires_at)
     )`
  );

  await db.query(
    `CREATE TABLE IF NOT EXISTS email_verifications (
       verification_id INT AUTO_INCREMENT PRIMARY KEY,
       email VARCHAR(255) NOT NULL,
       code_hash VARCHAR(255) NOT NULL,
       expires_at DATETIME NOT NULL,
       attempts INT NOT NULL DEFAULT 0,
       used TINYINT(1) NOT NULL DEFAULT 0,
       created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
       INDEX idx_email_verifications_email (email, used, expires_at)
     )`
  );
}

module.exports = ensureAuthColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureAuthColumns()
    .then(() => {
      console.log('employees.lockout_level, password_resets and email_verifications are up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}