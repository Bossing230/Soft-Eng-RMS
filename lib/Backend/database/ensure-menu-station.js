/**
 * Adds what the Kitchen board needs: menu_items.station, one of the fixed
 * values in ../constants/stations.js (Grill / Pasta / Salad / Desserts /
 * Drinks). It runs by itself the first time kitchen-board code touches the
 * database, so a deploy needs no manual SQL, and it is safe to run any
 * number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-menu-station.js
 *
 * Existing items get a one-time best guess from their category name (see the
 * CASE below). A manager can correct any item afterwards with
 * POST /menu/:id/station.
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

async function ensureMenuStation() {
  const rows = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'menu_items'`
  );
  const has = new Set(rows.map((r) => String(r.name).toLowerCase()));
  if (has.has('station')) return;

  let added = true;
  try {
    await db.query('ALTER TABLE menu_items ADD COLUMN station VARCHAR(30) NULL AFTER category_id');
  } catch (err) {
    if (err.errno !== DUPLICATE_COLUMN) throw err;
    added = false; // another server instance already added it
  }
  if (!added) return; // don't also backfill — avoids a race double-run overwriting manual fixes

  await db.query(
    `UPDATE menu_items m
       JOIN menu_categories c ON m.category_id = c.category_id
        SET m.station = CASE
              WHEN c.category_name IN ('Salad', 'Salads') THEN 'Salad'
              WHEN c.category_name IN ('Desserts', 'Dessert') THEN 'Desserts'
              WHEN c.category_name IN ('Drinks', 'Drink', 'Beverages') THEN 'Drinks'
              WHEN c.category_name IN ('Noodles', 'Pasta') THEN 'Pasta'
              ELSE 'Grill'
            END
      WHERE m.station IS NULL`
  );
}

module.exports = ensureMenuStation;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureMenuStation()
    .then(() => {
      console.log('The menu_items table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}