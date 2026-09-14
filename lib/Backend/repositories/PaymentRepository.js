const db = require('../patterns/singletons/DatabaseManager');

class PaymentRepository {
  async create({ orderId, method, amount, status, reference, processedBy, change }) {
    const result = await db.query(
      `INSERT INTO payments (order_id, payment_method, amount, payment_status, transaction_reference, processed_by)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [orderId, method, amount, status, reference, processedBy]
    );
    const rows = await db.query('SELECT * FROM payments WHERE payment_id = ?', [result.insertId]);
    return { ...rows[0], change };
  }

  async findByOrderId(orderId) {
    return db.query('SELECT * FROM payments WHERE order_id = ? ORDER BY payment_date DESC', [orderId]);
  }

  async findAll({ status, date } = {}) {
    let sql = `SELECT p.*, o.order_id, e.name AS processed_by_name FROM payments p
               JOIN orders o ON p.order_id = o.order_id
               JOIN employees e ON p.processed_by = e.employee_id WHERE 1=1`;
    const params = [];
    if (status) { sql += ' AND p.payment_status = ?'; params.push(status); }
    if (date) { sql += ' AND DATE(p.payment_date) = ?'; params.push(date); }
    sql += ' ORDER BY p.payment_date DESC';
    return db.query(sql, params);
  }

  async updateStatus(paymentId, status) {
    await db.query('UPDATE payments SET payment_status = ? WHERE payment_id = ?', [status, paymentId]);
    const rows = await db.query('SELECT * FROM payments WHERE payment_id = ?', [paymentId]);
    return rows[0];
  }
}

module.exports = new PaymentRepository();