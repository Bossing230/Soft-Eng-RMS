const db = require('../patterns/singletons/DatabaseManager');

class TableRepository {
  async findAll({ status } = {}) {
    let sql = 'SELECT * FROM tables WHERE 1=1';
    const params = [];
    if (status) {
      sql += ' AND status = ?';
      params.push(status);
    }
    sql += ' ORDER BY table_number';
    return db.query(sql, params);
  }

  async findById(id) {
    const rows = await db.query('SELECT * FROM tables WHERE table_id = ?', [id]);
    return rows[0] || null;
  }

  async create({ tableNumber, capacity }) {
    const result = await db.query('INSERT INTO tables (table_number, capacity) VALUES (?, ?)', [tableNumber, capacity]);
    return this.findById(result.insertId);
  }

  async update(id, fields) {
    const keys = Object.keys(fields);
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(`UPDATE tables SET ${setClause} WHERE table_id = ?`, [...Object.values(fields), id]);
    return this.findById(id);
  }

  async setStatus(id, status) {
    await db.query('UPDATE tables SET status = ? WHERE table_id = ?', [status, id]);
    return this.findById(id);
  }
}

module.exports = new TableRepository();