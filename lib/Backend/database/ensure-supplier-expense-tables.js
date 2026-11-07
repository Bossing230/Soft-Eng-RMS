/**
 * Creates the suppliers and expenses tables if they don't exist.
 * Runs by itself the first time the supplier / expense code touches the
 * database, and is safe to run any number of times. By hand, from lib/Backend:
 *     node database/ensure-supplier-expense-tables.js
 */
if (require.main === module) {
  try {
    require('dotenv').config();
  } catch (_) {
    // dotenv not installed: rely on variables already set in the environment.
  }
}

const db = require('../patterns/singletons/DatabaseManager');

async function ensureSupplierExpenseTables() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS suppliers (
      supplier_id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100) NOT NULL UNIQUE,
      contact_person VARCHAR(100) NULL,
      phone VARCHAR(30) NULL,
      email VARCHAR(100) NULL,
      address VARCHAR(255) NULL,
      notes VARCHAR(500) NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

  await db.query(`
    CREATE TABLE IF NOT EXISTS expenses (
      expense_id INT AUTO_INCREMENT PRIMARY KEY,
      expense_date DATE NOT NULL,
      category VARCHAR(50) NOT NULL,
      description VARCHAR(255) NOT NULL,
      amount DECIMAL(10,2) NOT NULL,
      supplier_id INT NULL,
      recorded_by INT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id) ON DELETE SET NULL,
      FOREIGN KEY (recorded_by) REFERENCES employees(employee_id),
      INDEX idx_expense_date (expense_date)
    )`);
}

module.exports = ensureSupplierExpenseTables;

if (require.main === module) {
  ensureSupplierExpenseTables()
    .then(() => {
      console.log('Supplier and expense tables are up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}