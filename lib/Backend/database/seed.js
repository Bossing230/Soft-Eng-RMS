require('dotenv').config();
const bcrypt = require('bcrypt');
const db = require('../patterns/singletons/DatabaseManager');

async function seed() {
  console.log('Seeding database...');

  const username = process.env.SEED_ADMIN_USERNAME || 'admin';
  const email = process.env.SEED_ADMIN_EMAIL || 'admin@rms.local';
  const password = process.env.SEED_ADMIN_PASSWORD || 'ChangeMe123!';

  const existing = await db.query('SELECT employee_id FROM employees WHERE username = ?', [username]);
  if (existing.length) {
    console.log(`Admin user "${username}" already exists — skipping.`);
  } else {
    const [role] = await db.query("SELECT role_id FROM roles WHERE role_name = 'administrator'");
    const hash = await bcrypt.hash(password, 10);
    await db.query(
      'INSERT INTO employees (name, username, email, password, role_id) VALUES (?, ?, ?, ?, ?)',
      ['System Administrator', username, email, hash, role.role_id]
    );
    console.log(`Created administrator "${username}" with password "${password}" — change it after first login.`);
  }

  const tableCount = await db.query('SELECT COUNT(*) AS count FROM tables');
  if (tableCount[0].count === 0) {
    const sampleTables = [
      ['T1', 2], ['T2', 2], ['T3', 4], ['T4', 4], ['T5', 6], ['T6', 8],
    ];
    for (const [tableNumber, capacity] of sampleTables) {
      await db.query('INSERT INTO tables (table_number, capacity) VALUES (?, ?)', [tableNumber, capacity]);
    }
    console.log(`Created ${sampleTables.length} sample tables.`);
  }

  console.log('Seeding complete.');
  process.exit(0);
}

seed().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});