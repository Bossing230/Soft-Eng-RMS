const db = require('../patterns/singletons/DatabaseManager');
const ConfigManager = require('../patterns/singletons/ConfigManager');
const ensureOrderColumns = require('../database/ensure-order-columns');

// "Today" for the Orders board is the restaurant-local day. REPORT_TZ_OFFSET_HOURS
// is the same setting the reports use (8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;
const LOCAL_ORDER_DAY = `DATE(DATE_ADD(o.order_date, INTERVAL ${TZ_OFFSET_HOURS} HOUR))`;
const LOCAL_TODAY = `DATE(DATE_ADD(NOW(), INTERVAL ${TZ_OFFSET_HOURS} HOUR))`;

const OPEN_STATUSES = `'pending','confirmed','preparing','ready','served'`;
const BOARD_LIMIT = 300;

class OrderRepository {
  /** Makes sure order_type and the 'served' status exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureOrderColumns().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  /** Adds each order's items with one query, instead of one query per order. */
  async _attachItems(orders) {
    if (!orders.length) return orders;
    const ids = orders.map((o) => o.order_id);
    const rows = await db.query(
      `SELECT oi.*, m.food_name
         FROM order_items oi
         JOIN menu_items m ON oi.menu_id = m.menu_id
        WHERE oi.order_id IN (${ids.map(() => '?').join(',')})
        ORDER BY oi.order_item_id`,
      ids
    );
    const byOrder = new Map();
    for (const row of rows) {
      if (!byOrder.has(row.order_id)) byOrder.set(row.order_id, []);
      byOrder.get(row.order_id).push(row);
    }
    return orders.map((o) => ({ ...o, items: byOrder.get(o.order_id) || [] }));
  }

  async findAll({ status, date, limit = 200 } = {}) {
    await this._ready();
    const safeLimit = Math.max(1, Math.min(500, parseInt(limit, 10) || 200));
    let sql = `SELECT o.*, t.table_number, e.name AS employee_name FROM orders o
               LEFT JOIN tables t ON o.table_id = t.table_id
               JOIN employees e ON o.employee_id = e.employee_id WHERE 1=1`;
    const params = [];
    if (status) { sql += ' AND o.order_status = ?'; params.push(status); }
    if (date) { sql += ' AND DATE(o.order_date) = ?'; params.push(date); }
    sql += ` ORDER BY o.order_date DESC LIMIT ${safeLimit}`;
    return this._attachItems(await db.query(sql, params));
  }

  /**
   * The Orders page: every order from today plus any order still open (from any
   * day), newest first, with items, payment method and how many minutes old.
   * The age is worked out in the database so it is right whatever the time zone.
   */
  async findBoard() {
    await this._ready();
    const rows = await db.query(
      `SELECT o.*, t.table_number, e.name AS employee_name,
              GREATEST(0, TIMESTAMPDIFF(MINUTE, o.order_date, NOW())) AS minutes_ago,
              (SELECT p.payment_method FROM payments p
                WHERE p.order_id = o.order_id AND p.payment_status IN ('paid','pending')
                ORDER BY p.payment_id DESC LIMIT 1) AS payment_method
         FROM orders o
         LEFT JOIN tables t ON o.table_id = t.table_id
         JOIN employees e ON o.employee_id = e.employee_id
        WHERE ${LOCAL_ORDER_DAY} = ${LOCAL_TODAY}
           OR o.order_status IN (${OPEN_STATUSES})
        ORDER BY o.order_date DESC, o.order_id DESC
        LIMIT ${BOARD_LIMIT}`
    );
    return this._attachItems(rows);
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query(
      `SELECT o.*, t.table_number, e.name AS employee_name FROM orders o
       LEFT JOIN tables t ON o.table_id = t.table_id
       JOIN employees e ON o.employee_id = e.employee_id
       WHERE o.order_id = ?`,
      [id]
    );
    if (!rows[0]) return null;
    const items = await db.query(
      `SELECT oi.*, m.food_name FROM order_items oi
       JOIN menu_items m ON oi.menu_id = m.menu_id WHERE oi.order_id = ?`,
      [id]
    );
    return { ...rows[0], items };
  }

  /** "3" also finds table "T3", and matching ignores upper/lower case. */
  async findTableByNumber(number) {
    const wanted = String(number).trim();
    const candidates = /^\d+$/.test(wanted) ? [wanted, `T${wanted}`] : [wanted];
    for (const candidate of candidates) {
      const rows = await db.query(
        'SELECT table_id, table_number FROM tables WHERE LOWER(table_number) = LOWER(?) LIMIT 1',
        [candidate]
      );
      if (rows[0]) return rows[0];
    }
    return null;
  }

  /** Creates an order together with its line items inside a transaction. */
  async create({ tableId, employeeId, items, discount = 0, orderType = 'dine_in' }) {
    await this._ready();
    const pool = db.getPool();
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const subtotal = items.reduce((sum, i) => sum + i.unitPrice * i.quantity, 0);
      const taxRate = ConfigManager.get('taxRate');
      const serviceRate = ConfigManager.get('serviceChargeRate');
      const tax = +(subtotal * taxRate).toFixed(2);
      const serviceCharge = +(subtotal * serviceRate).toFixed(2);
      const total = +(subtotal - discount + tax + serviceCharge).toFixed(2);

      const [orderResult] = await conn.execute(
        `INSERT INTO orders (table_id, order_type, employee_id, subtotal, discount, tax, total_amount)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [tableId || null, orderType, employeeId, subtotal, discount, tax + serviceCharge, total]
      );
      const orderId = orderResult.insertId;

      for (const item of items) {
        await conn.execute(
          `INSERT INTO order_items (order_id, menu_id, quantity, unit_price, subtotal) VALUES (?, ?, ?, ?, ?)`,
          [orderId, item.menuId, item.quantity, item.unitPrice, item.unitPrice * item.quantity]
        );
      }

      if (tableId) {
        await conn.execute('UPDATE tables SET status = ? WHERE table_id = ?', ['occupied', tableId]);
      }

      await conn.commit();
      return this.findById(orderId);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async updateStatus(id, status) {
    await this._ready();
    await db.query('UPDATE orders SET order_status = ? WHERE order_id = ?', [status, id]);
    if (status === 'completed' || status === 'cancelled') {
      const order = await this.findById(id);
      if (order?.table_id) {
        await db.query('UPDATE tables SET status = ? WHERE table_id = ?', ['available', order.table_id]);
      }
    }
    return this.findById(id);
  }

  async updatePaymentStatus(id, paymentStatus) {
    await db.query('UPDATE orders SET payment_status = ? WHERE order_id = ?', [paymentStatus, id]);
    return this.findById(id);
  }

  /** Confirmed and preparing orders, oldest first, with the items to cook. */
  async findKitchenQueue() {
    await this._ready();
    const rows = await db.query(
      `SELECT o.*, t.table_number FROM orders o
       LEFT JOIN tables t ON o.table_id = t.table_id
       WHERE o.order_status IN ('confirmed', 'preparing')
       ORDER BY o.order_date ASC`
    );
    return this._attachItems(rows);
  }

  async salesSummary(startDate, endDate) {
    const rows = await db.query(
      `SELECT DATE(order_date) AS day, COUNT(*) AS order_count, SUM(total_amount) AS total_sales
       FROM orders WHERE order_status = 'completed' AND DATE(order_date) BETWEEN ? AND ?
       GROUP BY DATE(order_date) ORDER BY day`,
      [startDate, endDate]
    );
    return rows;
  }

  async bestSellers(startDate, endDate, limit = 10) {
    const safeLimit = Math.max(1, Math.min(100, parseInt(limit, 10) || 10));
    return db.query(
      `SELECT m.menu_id, m.food_name, SUM(oi.quantity) AS total_sold, SUM(oi.subtotal) AS total_revenue
       FROM order_items oi
       JOIN orders o ON oi.order_id = o.order_id
       JOIN menu_items m ON oi.menu_id = m.menu_id
       WHERE o.order_status = 'completed' AND DATE(o.order_date) BETWEEN ? AND ?
       GROUP BY m.menu_id ORDER BY total_sold DESC LIMIT ${safeLimit}`,
      [startDate, endDate]
    );
  }

  async staffPerformance(date) {
    return db.query(
      `SELECT e.employee_id, e.name, r.role_name,
              COUNT(o.order_id) AS order_count,
              COALESCE(SUM(o.total_amount), 0) AS total_sales
       FROM employees e
       JOIN roles r ON e.role_id = r.role_id
       LEFT JOIN orders o ON o.employee_id = e.employee_id
         AND o.order_status = 'completed' AND DATE(o.order_date) = ?
       WHERE e.status = 'active'
       GROUP BY e.employee_id
       ORDER BY total_sales DESC`,
      [date]
    );
  }
}

module.exports = new OrderRepository();