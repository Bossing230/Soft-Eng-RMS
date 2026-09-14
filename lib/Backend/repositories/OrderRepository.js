const db = require('../patterns/singletons/DatabaseManager');
const ConfigManager = require('../patterns/singletons/ConfigManager');

class OrderRepository {
  async findAll({ status, date } = {}) {
    let sql = `SELECT o.*, t.table_number, e.name AS employee_name FROM orders o
               LEFT JOIN tables t ON o.table_id = t.table_id
               JOIN employees e ON o.employee_id = e.employee_id WHERE 1=1`;
    const params = [];
    if (status) { sql += ' AND o.order_status = ?'; params.push(status); }
    if (date) { sql += ' AND DATE(o.order_date) = ?'; params.push(date); }
    sql += ' ORDER BY o.order_date DESC';
    return db.query(sql, params);
  }

  async findById(id) {
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

  /** Creates an order together with its line items inside a transaction. */
  async create({ tableId, employeeId, items, discount = 0 }) {
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
        `INSERT INTO orders (table_id, employee_id, subtotal, discount, tax, total_amount)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [tableId || null, employeeId, subtotal, discount, tax + serviceCharge, total]
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

  async findKitchenQueue() {
    return db.query(
      `SELECT o.*, t.table_number FROM orders o
       LEFT JOIN tables t ON o.table_id = t.table_id
       WHERE o.order_status IN ('confirmed', 'preparing')
       ORDER BY o.order_date ASC`
    );
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
    return db.query(
      `SELECT m.menu_id, m.food_name, SUM(oi.quantity) AS total_sold, SUM(oi.subtotal) AS total_revenue
       FROM order_items oi
       JOIN orders o ON oi.order_id = o.order_id
       JOIN menu_items m ON oi.menu_id = m.menu_id
       WHERE o.order_status = 'completed' AND DATE(o.order_date) BETWEEN ? AND ?
       GROUP BY m.menu_id ORDER BY total_sold DESC LIMIT ?`,
      [startDate, endDate, limit]
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