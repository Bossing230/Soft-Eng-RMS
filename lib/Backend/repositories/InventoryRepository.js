const db = require('../patterns/singletons/DatabaseManager');
const ensureInventoryColumns = require('../database/ensure-inventory-columns');

// An item is "low" when it is at or below this share of its max stock, and
// "critical" (a more urgent sub-bucket of low, shown separately in the
// overview) at or below this smaller share. Both are presentation-only
// splits of the stored 3-state `status` (ok/low/out) — status itself, and
// the low-stock alerting it drives, is unchanged.
const LOW_STOCK_RATIO = 0.3;
const CRITICAL_RATIO = 0.1;

// An item with an expiry_date within this many days (today included) counts
// as "Expiring Soon".
const EXPIRING_SOON_DAYS = 7;

// Same setting the reports use: hours to add to stored timestamps so the
// history shows restaurant-local times (8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;

const round2 = (n) => Math.round(n * 100) / 100;
const statusFor = (quantity, minimum) => (quantity <= 0 ? 'out' : quantity <= minimum ? 'low' : 'ok');
const severity = { out: 0, low: 1, ok: 2 }; // lower = worse
const httpError = (status, message) => Object.assign(new Error(message), { status });

/**
 * A finer-grained status for display only: splits the stored "low" into
 * "low" and "critical" by how close to empty the item is. Never stored.
 */
function withSeverity(row) {
  const quantity = Number(row.quantity);
  const max = Number(row.max_stock) || 0;
  const minimum = Number(row.minimum_stock);
  let itemSeverity;
  if (quantity <= 0) itemSeverity = 'out';
  else if (max > 0 && quantity <= max * CRITICAL_RATIO) itemSeverity = 'critical';
  else if (quantity <= minimum) itemSeverity = 'low';
  else itemSeverity = 'ok';
  return { ...row, severity: itemSeverity };
}

class InventoryRepository {
  /** Makes sure the category / max_stock / expiry_date / unit_cost columns exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureInventoryColumns().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  async findAll({ status } = {}) {
    await this._ready();
    let sql = 'SELECT * FROM inventory WHERE 1=1';
    const params = [];
    if (status) { sql += ' AND status = ?'; params.push(status); }
    sql += ' ORDER BY ingredient_name';
    const rows = await db.query(sql, params);
    return rows.map(withSeverity);
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query('SELECT * FROM inventory WHERE inventory_id = ?', [id]);
    return rows[0] ? withSeverity(rows[0]) : null;
  }

  /** Case-insensitive name lookup, used to stop duplicates. */
  async findByName(name, excludeId = null) {
    await this._ready();
    const rows = await db.query(
      'SELECT inventory_id FROM inventory WHERE LOWER(ingredient_name) = LOWER(?) AND inventory_id <> ? LIMIT 1',
      [name, excludeId === null ? 0 : excludeId]
    );
    return rows[0] || null;
  }

  async findLowStock() {
    await this._ready();
    const rows = await db.query('SELECT * FROM inventory WHERE quantity <= minimum_stock ORDER BY quantity ASC');
    return rows.map(withSeverity);
  }

  /**
   * Everything the Inventory overview needs: counts by severity, how many
   * are expiring soon, total stock value, category breakdown (for the filter
   * pills), the single most urgent item to flag, and recent stock activity
   * across every item. All computed only from data that's actually there —
   * expiry and cost are 0/empty for any item nobody has set them on yet.
   */
  async getOverview() {
    await this._ready();
    const [categories, [totals], worstRows, recentActivity] = await Promise.all([
      db.query(
        `SELECT COALESCE(category, 'Uncategorized') AS category, COUNT(*) AS count
           FROM inventory GROUP BY category ORDER BY category`
      ),
      db.query(
        `SELECT COUNT(*) AS total_items,
                SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS out_count,
                SUM(CASE WHEN quantity > 0 AND max_stock > 0 AND quantity <= max_stock * ${CRITICAL_RATIO} THEN 1 ELSE 0 END) AS critical_count,
                SUM(CASE WHEN quantity > 0 AND quantity <= minimum_stock
                          AND NOT (max_stock > 0 AND quantity <= max_stock * ${CRITICAL_RATIO}) THEN 1 ELSE 0 END) AS low_count,
                SUM(CASE WHEN quantity > minimum_stock THEN 1 ELSE 0 END) AS ok_count,
                SUM(CASE WHEN expiry_date IS NOT NULL
                          AND expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ${EXPIRING_SOON_DAYS} DAY)
                         THEN 1 ELSE 0 END) AS expiring_count,
                COALESCE(SUM(quantity * unit_cost), 0) AS total_value,
                SUM(CASE WHEN unit_cost > 0 THEN 1 ELSE 0 END) AS priced_count
           FROM inventory`
      ),
      db.query(
        `SELECT * FROM inventory
          WHERE quantity <= minimum_stock
          ORDER BY (quantity / NULLIF(max_stock, 0)) ASC, quantity ASC
          LIMIT 1`
      ),
      db.query(
        `SELECT t.transaction_id, t.transaction_type, t.quantity,
                DATE_FORMAT(DATE_ADD(t.transaction_date, INTERVAL ${TZ_OFFSET_HOURS} HOUR), '%Y-%m-%d %H:%i:%s') AS local_time,
                i.ingredient_name
           FROM inventory_transactions t
           JOIN inventory i ON t.inventory_id = i.inventory_id
          ORDER BY t.transaction_date DESC, t.transaction_id DESC
          LIMIT 10`
      ),
    ]);

    return {
      categories,
      totals,
      actionNeeded: worstRows[0] ? withSeverity(worstRows[0]) : null,
      recentActivity,
    };
  }

  async create({ ingredientName, category = null, quantity, unit, maxStock, expiryDate = null, unitCost = 0 }) {
    await this._ready();
    const minimumStock = round2(maxStock * LOW_STOCK_RATIO);
    const result = await db.query(
      `INSERT INTO inventory (ingredient_name, category, quantity, unit, max_stock, minimum_stock, expiry_date, unit_cost, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [ingredientName, category, quantity, unit, maxStock, minimumStock, expiryDate, unitCost, statusFor(quantity, minimumStock)]
    );
    return this.findById(result.insertId);
  }

  /**
   * Edits an item's details. Only these fields can change; the low-stock line
   * always follows max stock, and the status is recomputed.
   */
  async update(id, { ingredientName, category, unit, maxStock, expiryDate, unitCost }) {
    await this._ready();
    const item = await this.findById(id);
    if (!item) return null;

    const nextMax = maxStock ?? Number(item.max_stock);
    const minimumStock = round2(nextMax * LOW_STOCK_RATIO);
    await db.query(
      `UPDATE inventory
          SET ingredient_name = ?, category = ?, unit = ?, max_stock = ?, minimum_stock = ?,
              expiry_date = ?, unit_cost = ?, status = ?
        WHERE inventory_id = ?`,
      [
        ingredientName ?? item.ingredient_name,
        category === undefined ? item.category ?? null : category,
        unit ?? item.unit,
        nextMax,
        minimumStock,
        expiryDate === undefined ? item.expiry_date ?? null : expiryDate,
        unitCost === undefined ? item.unit_cost : unitCost,
        statusFor(Number(item.quantity), minimumStock),
        id,
      ]
    );
    return this.findById(id);
  }

  /**
   * Applies a stock change (positive = in, negative = out) and logs it, all in
   * one transaction. Refuses to take more than what is in stock.
   * The result says whether the item just dropped into a worse status, so
   * callers only alert on the change and not on every adjustment.
   */
  async adjustStock(id, delta, type, employeeId) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    let previousStatus;
    try {
      await conn.beginTransaction();

      const [rows] = await conn.execute('SELECT * FROM inventory WHERE inventory_id = ? FOR UPDATE', [id]);
      const item = rows[0];
      if (!item) throw httpError(404, 'Inventory item not found');

      const current = Number(item.quantity);
      const minimum = Number(item.minimum_stock);
      const next = round2(current + delta);
      if (next < 0) throw httpError(400, `Only ${current} ${item.unit} in stock`);

      previousStatus = statusFor(current, minimum);
      await conn.execute('UPDATE inventory SET quantity = ?, status = ? WHERE inventory_id = ?', [
        next,
        statusFor(next, minimum),
        id,
      ]);
      await conn.execute(
        'INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id) VALUES (?, ?, ?, ?)',
        [id, type, delta, employeeId]
      );

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    const updated = await this.findById(id);
    return {
      ...updated,
      previousStatus,
      wasLowStock: updated.status !== 'ok',
      crossedIntoLow: severity[updated.status] < severity[previousStatus],
    };
  }

  /** Records one delivery per item in a single transaction: all or nothing. */
  async restockMany(items, employeeId) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();
      for (const { inventoryId, quantity } of items) {
        const [rows] = await conn.execute('SELECT * FROM inventory WHERE inventory_id = ? FOR UPDATE', [inventoryId]);
        const item = rows[0];
        if (!item) throw httpError(404, `Inventory item #${inventoryId} not found`);

        const next = round2(Number(item.quantity) + quantity);
        await conn.execute('UPDATE inventory SET quantity = ?, status = ? WHERE inventory_id = ?', [
          next,
          statusFor(next, Number(item.minimum_stock)),
          inventoryId,
        ]);
        await conn.execute(
          'INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id) VALUES (?, ?, ?, ?)',
          [inventoryId, 'delivery', quantity, employeeId]
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

  async history(inventoryId) {
    await this._ready();
    return db.query(
      `SELECT t.transaction_id, t.transaction_type, t.quantity, t.transaction_date,
              DATE_FORMAT(DATE_ADD(t.transaction_date, INTERVAL ${TZ_OFFSET_HOURS} HOUR), '%Y-%m-%d %H:%i:%s') AS local_time,
              e.name AS employee_name
         FROM inventory_transactions t
         JOIN employees e ON t.employee_id = e.employee_id
        WHERE t.inventory_id = ?
        ORDER BY t.transaction_date DESC, t.transaction_id DESC
        LIMIT 50`,
      [inventoryId]
    );
  }
}

module.exports = new InventoryRepository();
module.exports.LOW_STOCK_RATIO = LOW_STOCK_RATIO;
module.exports.CRITICAL_RATIO = CRITICAL_RATIO;