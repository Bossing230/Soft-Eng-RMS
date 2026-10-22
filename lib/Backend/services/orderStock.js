/**
 * Takes a dish's recipe ingredients out of inventory when an order is placed,
 * and puts them back if the order is cancelled before the kitchen starts.
 *
 *   deductForOrder(conn, ...)  runs INSIDE the order's own transaction, so an
 *                              order and its stock change succeed or fail together.
 *   returnForOrder(...)        runs in its own transaction and is safe to call
 *                              twice: it only returns what is still deducted.
 *
 * Every change is logged in inventory_transactions with the order id.
 * Dishes with no recipe are skipped, so they never block an order.
 */
const db = require('../patterns/singletons/DatabaseManager');
const ensureInventoryColumns = require('../database/ensure-inventory-columns');
const ensureRecipeTables = require('../database/ensure-recipe-tables');

const round2 = (n) => Math.round(n * 100) / 100;
const statusFor = (quantity, minimum) => (quantity <= 0 ? 'out' : quantity <= minimum ? 'low' : 'ok');
const severity = { out: 0, low: 1, ok: 2 }; // lower = worse
const httpError = (status, message) => Object.assign(new Error(message), { status });
const placeholders = (list) => list.map(() => '?').join(',');

let schemaReady = null;

/**
 * Creates the recipe table / columns if needed. Call this BEFORE starting a
 * transaction: the ALTER TABLE statements it may run would end one.
 */
function ready() {
  if (!schemaReady) {
    schemaReady = ensureInventoryColumns()
      .then(() => ensureRecipeTables())
      .catch((err) => {
        schemaReady = null; // try again on the next request
        throw err;
      });
  }
  return schemaReady;
}

/**
 * @param conn        a connection with a transaction already begun
 * @param orderId     the new order
 * @param items       [{ menuId, quantity }] as placed on the order
 * @param employeeId  who placed it
 * @returns the ingredients that just dropped into low or out of stock, so the
 *          caller can alert after the transaction commits.
 * @throws a 400 error naming every ingredient that is short, nothing is deducted.
 */
async function deductForOrder(conn, orderId, items, employeeId) {
  const orderedQty = new Map();
  for (const item of items) {
    const menuId = Number(item.menuId);
    orderedQty.set(menuId, (orderedQty.get(menuId) || 0) + Number(item.quantity));
  }
  const menuIds = [...orderedQty.keys()];

  const [recipeRows] = await conn.execute(
    `SELECT menu_id, inventory_id, quantity FROM recipe_ingredients WHERE menu_id IN (${placeholders(menuIds)})`,
    menuIds
  );
  if (!recipeRows.length) return []; // nothing on this order has a recipe

  // Total each ingredient needed across the whole order (two dishes may share one).
  const needRaw = new Map();
  for (const row of recipeRows) {
    const total = Number(row.quantity) * orderedQty.get(Number(row.menu_id));
    needRaw.set(row.inventory_id, (needRaw.get(row.inventory_id) || 0) + total);
  }
  const needs = new Map([...needRaw.entries()].map(([id, qty]) => [id, round2(qty)]));

  // Lock the rows in a fixed order so two orders at once cannot deadlock.
  const ids = [...needs.keys()].sort((a, b) => a - b);
  const [stockRows] = await conn.execute(
    `SELECT inventory_id, ingredient_name, quantity, unit, minimum_stock
       FROM inventory
      WHERE inventory_id IN (${placeholders(ids)})
      ORDER BY inventory_id
        FOR UPDATE`,
    ids
  );
  const stock = new Map(stockRows.map((r) => [r.inventory_id, r]));

  const short = [];
  for (const id of ids) {
    const row = stock.get(id);
    if (!row) throw httpError(400, 'A recipe ingredient no longer exists in inventory');
    const need = needs.get(id);
    const have = Number(row.quantity);
    if (need > have) short.push(`${row.ingredient_name} (need ${need} ${row.unit}, only ${have} left)`);
  }
  if (short.length) throw httpError(400, `Not enough stock for this order: ${short.join('; ')}`);

  const alerts = [];
  for (const id of ids) {
    const row = stock.get(id);
    const need = needs.get(id);
    const minimum = Number(row.minimum_stock);
    const before = Number(row.quantity);
    const after = round2(before - need);

    await conn.execute('UPDATE inventory SET quantity = ?, status = ? WHERE inventory_id = ?', [
      after,
      statusFor(after, minimum),
      id,
    ]);
    await conn.execute(
      `INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id, order_id)
       VALUES (?, 'usage', ?, ?, ?)`,
      [id, -need, employeeId, orderId]
    );

    const previousStatus = statusFor(before, minimum);
    const status = statusFor(after, minimum);
    if (severity[status] < severity[previousStatus]) {
      alerts.push({ inventoryId: id, name: row.ingredient_name, unit: row.unit, quantity: after, status, previousStatus });
    }
  }
  return alerts;
}

/**
 * Puts back whatever this order still has deducted. Call it only when the
 * kitchen had not started (pending or confirmed); once cooking has begun the
 * ingredients are used, so the deduction stays.
 */
async function returnForOrder(orderId, employeeId) {
  await ready();
  const conn = await db.getPool().getConnection();
  try {
    await conn.beginTransaction();

    // usage rows are negative and return rows positive, so a net below zero
    // means "still deducted". A second call finds nothing left to return.
    const [owed] = await conn.execute(
      `SELECT inventory_id, SUM(quantity) AS net
         FROM inventory_transactions
        WHERE order_id = ? AND transaction_type IN ('usage', 'return')
        GROUP BY inventory_id
       HAVING SUM(quantity) < 0
        ORDER BY inventory_id`,
      [orderId]
    );
    if (!owed.length) {
      await conn.commit();
      return;
    }

    const ids = owed.map((r) => r.inventory_id);
    const [stockRows] = await conn.execute(
      `SELECT inventory_id, quantity, minimum_stock
         FROM inventory
        WHERE inventory_id IN (${placeholders(ids)})
        ORDER BY inventory_id
          FOR UPDATE`,
      ids
    );
    const stock = new Map(stockRows.map((r) => [r.inventory_id, r]));

    for (const row of owed) {
      const item = stock.get(row.inventory_id);
      if (!item) continue;
      const give = round2(-Number(row.net));
      const after = round2(Number(item.quantity) + give);
      await conn.execute('UPDATE inventory SET quantity = ?, status = ? WHERE inventory_id = ?', [
        after,
        statusFor(after, Number(item.minimum_stock)),
        row.inventory_id,
      ]);
      await conn.execute(
        `INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id, order_id)
         VALUES (?, 'return', ?, ?, ?)`,
        [row.inventory_id, give, employeeId, orderId]
      );
    }

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { ready, deductForOrder, returnForOrder };