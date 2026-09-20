const db = require('../patterns/singletons/DatabaseManager');
const ensureInventoryColumns = require('../database/ensure-inventory-columns');

// An item is "low" when it is at or below this share of its max stock.
const LOW_STOCK_RATIO = 0.3;

// Same setting the reports use: hours to add to stored timestamps so the
// history shows restaurant-local times (8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;

const round2 = (n) => Math.round(n * 100) / 100;
const statusFor = (quantity, minimum) => (quantity <= 0 ? 'out' : quantity <= minimum ? 'low' : 'ok');
const severity = { out: 0, low: 1, ok: 2 }; // lower = worse
const httpError = (status, message) => Object.assign(new Error(message), { status });

class InventoryRepository {
  /** Makes sure the category / max_stock columns exist, once per server run. */
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
    return db.query(sql, params);
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query('SELECT * FROM inventory WHERE inventory_id = ?', [id]);
    return rows[0] || null;
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
    return db.query('SELECT * FROM inventory WHERE quantity <= minimum_stock ORDER BY quantity ASC');
  }

  async create({ ingredientName, category = null, quantity, unit, maxStock }) {
    await this._ready();
    const minimumStock = round2(maxStock * LOW_STOCK_RATIO);
    const result = await db.query(
      `INSERT INTO inventory (ingredient_name, category, quantity, unit, max_stock, minimum_stock, status)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [ingredientName, category, quantity, unit, maxStock, minimumStock, statusFor(quantity, minimumStock)]
    );
    return this.findById(result.insertId);
  }

  /**
   * Edits an item's details. Only these fields can change; the low-stock line
   * always follows max stock, and the status is recomputed.
   */
  async update(id, { ingredientName, category, unit, maxStock }) {
    await this._ready();
    const item = await this.findById(id);
    if (!item) return null;

    const nextMax = maxStock ?? Number(item.max_stock);
    const minimumStock = round2(nextMax * LOW_STOCK_RATIO);
    await db.query(
      `UPDATE inventory
          SET ingredient_name = ?, category = ?, unit = ?, max_stock = ?, minimum_stock = ?, status = ?
        WHERE inventory_id = ?`,
      [
        ingredientName ?? item.ingredient_name,
        category === undefined ? item.category ?? null : category,
        unit ?? item.unit,
        nextMax,
        minimumStock,
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