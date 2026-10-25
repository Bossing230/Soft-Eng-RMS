const db = require('../patterns/singletons/DatabaseManager');
const ensureInventoryColumns = require('../database/ensure-inventory-columns');
const { ensureTransactionColumns } = ensureInventoryColumns;
const ensureRecipeTables = require('../database/ensure-recipe-tables');
const RecipeRepository = require('./RecipeRepository');

// By default an item is "low" when it is at or below this share of its max
// stock. An item can have its own reorder level instead (reorder_level), and
// either way the result is stored in minimum_stock, which everything else
// (alerts, dashboards, the low-stock list) already reads.
const LOW_STOCK_RATIO = 0.3;

// "Critical" is the more urgent part of low: at or below one third of the
// low-stock line (which is 10% of max stock with the default 30% line).
// Presentation-only, never stored. Kept as an export for older callers.
const CRITICAL_RATIO = 0.1;
const CRITICAL_SHARE_OF_LOW = 1 / 3;

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
  const minimum = Number(row.minimum_stock);
  let itemSeverity;
  if (quantity <= 0) itemSeverity = 'out';
  else if (quantity <= minimum * CRITICAL_SHARE_OF_LOW) itemSeverity = 'critical';
  else if (quantity <= minimum) itemSeverity = 'low';
  else itemSeverity = 'ok';
  return { ...row, severity: itemSeverity };
}

class InventoryRepository {
  /**
   * Makes sure the extra inventory columns, the recipe tables and the
   * transaction columns (reason, the 'waste' type) exist, once per server run.
   */
  _ready() {
    if (!this._schema) {
      this._schema = ensureInventoryColumns()
        .then(() => ensureRecipeTables())
        .then(() => ensureTransactionColumns())
        .catch((err) => {
          this._schema = null; // try again on the next request
          throw err;
        });
    }
    return this._schema;
  }

  /** Active items by default; pass { archived: true } for the archived ones. */
  async findAll({ status, archived = false } = {}) {
    await this._ready();
    let sql = 'SELECT * FROM inventory WHERE is_archived = ?';
    const params = [archived ? 1 : 0];
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

  /** Case-insensitive name lookup (archived items included), used to stop duplicates. */
  async findByName(name, excludeId = null) {
    await this._ready();
    const rows = await db.query(
      'SELECT inventory_id, is_archived FROM inventory WHERE LOWER(ingredient_name) = LOWER(?) AND inventory_id <> ? LIMIT 1',
      [name, excludeId === null ? 0 : excludeId]
    );
    return rows[0] || null;
  }

  async findLowStock() {
    await this._ready();
    const rows = await db.query(
      'SELECT * FROM inventory WHERE is_archived = 0 AND quantity <= minimum_stock ORDER BY quantity ASC'
    );
    return rows.map(withSeverity);
  }

  /**
   * Everything the Inventory overview needs: counts by severity, how many
   * are expiring soon, total stock value, category breakdown (for the filter
   * pills), the single most urgent item to flag, and recent stock activity
   * across every item. Archived items are left out of all of it, and only
   * counted separately (archivedCount).
   */
  async getOverview() {
    await this._ready();
    const [categories, [totals], worstRows, recentActivity, [archivedRow]] = await Promise.all([
      db.query(
        `SELECT COALESCE(category, 'Uncategorized') AS category, COUNT(*) AS count
           FROM inventory WHERE is_archived = 0 GROUP BY category ORDER BY category`
      ),
      db.query(
        `SELECT COUNT(*) AS total_items,
                SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS out_count,
                SUM(CASE WHEN quantity > 0 AND quantity <= minimum_stock * ${CRITICAL_SHARE_OF_LOW} THEN 1 ELSE 0 END) AS critical_count,
                SUM(CASE WHEN quantity > minimum_stock * ${CRITICAL_SHARE_OF_LOW} AND quantity <= minimum_stock THEN 1 ELSE 0 END) AS low_count,
                SUM(CASE WHEN quantity > minimum_stock THEN 1 ELSE 0 END) AS ok_count,
                SUM(CASE WHEN expiry_date IS NOT NULL
                          AND expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ${EXPIRING_SOON_DAYS} DAY)
                         THEN 1 ELSE 0 END) AS expiring_count,
                COALESCE(SUM(quantity * unit_cost), 0) AS total_value,
                SUM(CASE WHEN unit_cost > 0 THEN 1 ELSE 0 END) AS priced_count
           FROM inventory
          WHERE is_archived = 0`
      ),
      db.query(
        `SELECT * FROM inventory
          WHERE is_archived = 0 AND quantity <= minimum_stock
          ORDER BY (quantity / NULLIF(max_stock, 0)) ASC, quantity ASC
          LIMIT 1`
      ),
      db.query(
        `SELECT t.transaction_id, t.transaction_type, t.quantity, t.order_id, t.reason,
                DATE_FORMAT(DATE_ADD(t.transaction_date, INTERVAL ${TZ_OFFSET_HOURS} HOUR), '%Y-%m-%d %H:%i:%s') AS local_time,
                i.ingredient_name
           FROM inventory_transactions t
           JOIN inventory i ON t.inventory_id = i.inventory_id
          WHERE i.is_archived = 0
          ORDER BY t.transaction_date DESC, t.transaction_id DESC
          LIMIT 10`
      ),
      db.query('SELECT COUNT(*) AS count FROM inventory WHERE is_archived = 1'),
    ]);

    return {
      categories,
      totals,
      actionNeeded: worstRows[0] ? withSeverity(worstRows[0]) : null,
      recentActivity,
      archivedCount: Number(archivedRow.count) || 0,
    };
  }

  /**
   * [reorderLevel] is the item's own low-stock line; leave it out (null) to
   * use 30% of max stock.
   */
  async create({
    ingredientName, category = null, quantity, unit, maxStock, expiryDate = null, unitCost = 0, image = null,
    reorderLevel = null, supplierName = null, supplierPhone = null, storageLocation = null, notes = null,
  }) {
    await this._ready();
    const minimumStock = reorderLevel ?? round2(maxStock * LOW_STOCK_RATIO);
    const result = await db.query(
      `INSERT INTO inventory
         (ingredient_name, category, quantity, unit, max_stock, minimum_stock, reorder_level, expiry_date, unit_cost,
          image, supplier_name, supplier_phone, storage_location, notes, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        ingredientName, category, quantity, unit, maxStock, minimumStock, reorderLevel, expiryDate, unitCost,
        image, supplierName, supplierPhone, storageLocation, notes, statusFor(quantity, minimumStock),
      ]
    );
    return this.findById(result.insertId);
  }

  /**
   * Edits an item's details. The low-stock line follows the item's own
   * reorder level if it has one, otherwise 30% of max stock, and the status
   * is recomputed.
   * For image / supplier / location / notes: undefined = keep, null = clear.
   * For reorderLevel: undefined = keep, null = go back to the 30% default.
   */
  async update(id, {
    ingredientName, category, unit, maxStock, expiryDate, unitCost, image,
    reorderLevel, supplierName, supplierPhone, storageLocation, notes,
  }) {
    await this._ready();
    const item = await this.findById(id);
    if (!item) return null;

    // Recipes measure this item in its current unit. Changing the unit would
    // silently change what every recipe using it means (30 g becoming 30 kg).
    if (unit !== undefined && unit !== item.unit && (await RecipeRepository.countUsing(id)) > 0) {
      throw httpError(400, `${item.ingredient_name} is used in recipes, so its unit can't be changed. Remove it from those recipes first.`);
    }

    const keep = (next, current) => (next === undefined ? current ?? null : next);

    const nextMax = maxStock ?? Number(item.max_stock);
    const nextReorder = reorderLevel === undefined ? item.reorder_level ?? null : reorderLevel;
    const minimumStock = nextReorder !== null ? round2(Number(nextReorder)) : round2(nextMax * LOW_STOCK_RATIO);

    await db.query(
      `UPDATE inventory
          SET ingredient_name = ?, category = ?, unit = ?, max_stock = ?, minimum_stock = ?, reorder_level = ?,
              expiry_date = ?, unit_cost = ?, image = ?, supplier_name = ?, supplier_phone = ?,
              storage_location = ?, notes = ?, status = ?
        WHERE inventory_id = ?`,
      [
        ingredientName ?? item.ingredient_name,
        keep(category, item.category),
        unit ?? item.unit,
        nextMax,
        minimumStock,
        nextReorder,
        keep(expiryDate, item.expiry_date),
        unitCost === undefined ? item.unit_cost : unitCost,
        keep(image, item.image),
        keep(supplierName, item.supplier_name),
        keep(supplierPhone, item.supplier_phone),
        keep(storageLocation, item.storage_location),
        keep(notes, item.notes),
        statusFor(Number(item.quantity), minimumStock),
        id,
      ]
    );
    return this.findById(id);
  }

  /** Sets or clears (null) just the photo of an item. */
  async setImage(id, image) {
    await this._ready();
    await db.query('UPDATE inventory SET image = ? WHERE inventory_id = ?', [image, id]);
    return this.findById(id);
  }

  /** Hides an item everywhere (or brings it back). Its history is kept. */
  async setArchived(id, archived) {
    await this._ready();
    await db.query('UPDATE inventory SET is_archived = ? WHERE inventory_id = ?', [archived ? 1 : 0, id]);
    return this.findById(id);
  }

  /**
   * Applies a stock change (positive = in, negative = out) and logs it, all in
   * one transaction. Refuses to take more than what is in stock, and refuses
   * archived items. [reason] is only used for 'waste' records.
   * The result says whether the item just dropped into a worse status, so
   * callers only alert on the change and not on every adjustment.
   */
  async adjustStock(id, delta, type, employeeId, reason = null) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    let previousStatus;
    try {
      await conn.beginTransaction();

      const [rows] = await conn.execute('SELECT * FROM inventory WHERE inventory_id = ? FOR UPDATE', [id]);
      const item = rows[0];
      if (!item) throw httpError(404, 'Inventory item not found');
      if (Number(item.is_archived)) {
        throw httpError(400, `${item.ingredient_name} is archived. Restore it before changing its stock.`);
      }

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
        'INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id, reason) VALUES (?, ?, ?, ?, ?)',
        [id, type, delta, employeeId, reason]
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
        if (Number(item.is_archived)) {
          throw httpError(400, `${item.ingredient_name} is archived. Restore it before restocking.`);
        }

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
      `SELECT t.transaction_id, t.transaction_type, t.quantity, t.order_id, t.reason, t.transaction_date,
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