const db = require('../patterns/singletons/DatabaseManager');

class InventoryRepository {
  async findAll({ status } = {}) {
    let sql = 'SELECT * FROM inventory WHERE 1=1';
    const params = [];
    if (status) { sql += ' AND status = ?'; params.push(status); }
    sql += ' ORDER BY ingredient_name';
    return db.query(sql, params);
  }

  async findById(id) {
    const rows = await db.query('SELECT * FROM inventory WHERE inventory_id = ?', [id]);
    return rows[0] || null;
  }

  async findLowStock() {
    return db.query('SELECT * FROM inventory WHERE quantity <= minimum_stock ORDER BY quantity ASC');
  }

  async create({ ingredientName, quantity, unit, minimumStock }) {
    const status = quantity <= 0 ? 'out' : quantity <= minimumStock ? 'low' : 'ok';
    const result = await db.query(
      `INSERT INTO inventory (ingredient_name, quantity, unit, minimum_stock, status) VALUES (?, ?, ?, ?, ?)`,
      [ingredientName, quantity, unit, minimumStock, status]
    );
    return this.findById(result.insertId);
  }

  async update(id, fields) {
    const keys = Object.keys(fields);
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(`UPDATE inventory SET ${setClause} WHERE inventory_id = ?`, [...Object.values(fields), id]);
    return this.findById(id);
  }

  /** Applies a stock delta (positive for delivery, negative for usage) and recomputes status. */
  async adjustStock(id, delta, type, employeeId) {
    const item = await this.findById(id);
    if (!item) throw new Error('Inventory item not found');

    const newQuantity = Math.max(0, parseFloat(item.quantity) + delta);
    const status = newQuantity <= 0 ? 'out' : newQuantity <= item.minimum_stock ? 'low' : 'ok';

    await db.query('UPDATE inventory SET quantity = ?, status = ? WHERE inventory_id = ?', [newQuantity, status, id]);
    await db.query(
      `INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, employee_id) VALUES (?, ?, ?, ?)`,
      [id, type, delta, employeeId]
    );

    return { ...(await this.findById(id)), wasLowStock: status === 'low' || status === 'out' };
  }

  async history(inventoryId) {
    return db.query(
      `SELECT t.*, e.name AS employee_name FROM inventory_transactions t
       JOIN employees e ON t.employee_id = e.employee_id
       WHERE t.inventory_id = ? ORDER BY t.transaction_date DESC`,
      [inventoryId]
    );
  }
}

module.exports = new InventoryRepository();