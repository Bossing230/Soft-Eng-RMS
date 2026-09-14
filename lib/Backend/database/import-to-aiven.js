// One-time use: imports schema.sql into your Aiven MySQL database.
// Uses mysql2 (already installed) instead of the old XAMPP mysql.exe
// client, which doesn't support Aiven's authentication method.
//
// Run with: node database/import-to-aiven.js

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

async function main() {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const sql = fs.readFileSync(schemaPath, 'utf8');

  const connection = await mysql.createConnection({
    host: process.env.AIVEN_DB_HOST,
    port: process.env.AIVEN_DB_PORT,
    user: process.env.AIVEN_DB_USER,
    password: process.env.AIVEN_DB_PASSWORD,
    ssl: { rejectUnauthorized: false }, // Aiven requires SSL
    multipleStatements: true, // lets us run the whole schema.sql in one go
  });

  console.log('Connected to Aiven. Running schema.sql...');
  await connection.query(sql);
  console.log('Schema imported successfully.');

  await connection.end();
  process.exit(0);
}

main().catch((err) => {
  console.error('Import failed:', err.message);
  process.exit(1);
});