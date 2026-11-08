/**
 * Creates the expenses table if it doesn't exist. Runs by itself the first
 * time the expense code touches the database, and is safe to run any number
 * of times. By hand, from lib/Backend:
 *     node database/ensure-expense-table.js
 *
 * If an older expenses table from the earlier version already exists (with a
 * supplier_id column), it keeps working: that column is optional and unused.
 */
if (require.main === module) {
  try {
    require('dotenv').config();
  } catch (_) {
    // dotenv not installed: rely on variables already set in the environment.
  }
}

const db = require('../patterns/singletons/DatabaseManager');

async function ensureExpenseTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS expenses (
      expense_id INT AUTO_INCREMENT PRIMARY KEY,
      expense_date DATE NOT NULL,
      category VARCHAR(50) NOT NULL,
      description VARCHAR(255) NOT NULL,
      amount DECIMAL(10,2) NOT NULL,
      recorded_by INT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (recorded_by) REFERENCES employees(employee_id),
      INDEX idx_expense_date (expense_date)
    )`);
}

module.exports = ensureExpenseTable;

if (require.main === module) {
  ensureExpenseTable()
    .then(() => {
      console.log('The expenses table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}