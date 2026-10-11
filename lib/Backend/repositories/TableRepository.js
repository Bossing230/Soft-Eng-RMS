const db = require('../patterns/singletons/DatabaseManager');
const ensureTableColumns = require('../database/ensure-table-columns');

class TableRepository {
  /** Makes sure the location column and the 'cleaning' status exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureTableColumns().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  async findAll({ status } = {}) {
    await this._ready();
    let sql = 'SELECT * FROM tables WHERE 1=1';
    const params = [];
    if (status) {
      sql += ' AND status = ?';
      params.push(status);
    }
    sql += ' ORDER BY LENGTH(table_number), table_number'; // so T2 sorts before T10
    return db.query(sql, params);
  }

  /**
   * Every table for the board, each with the name of whoever is currently
   * seated there, if any (today's reservation at that table marked 'seated').
   * A table occupied by a walk-in with no reservation simply has no name.
   */
  async findBoard() {
    await this._ready();
    return db.query(
      `SELECT t.*,
              (SELECT r.customer_name FROM reservations r
                 WHERE r.table_id = t.table_id AND r.status = 'seated' AND r.reservation_date = CURDATE()
                 ORDER BY r.reservation_id DESC LIMIT 1) AS customer_name
         FROM tables t
        ORDER BY LENGTH(t.table_number), t.table_number`
    );
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query('SELECT * FROM tables WHERE table_id = ?', [id]);
    return rows[0] || null;
  }

  async create({ tableNumber, capacity, location = 'indoor' }) {
    await this._ready();
    const result = await db.query('INSERT INTO tables (table_number, capacity, location) VALUES (?, ?, ?)', [
      tableNumber,
      capacity,
      location,
    ]);
    return this.findById(result.insertId);
  }

  /** Only these fields may be edited this way; use setStatus to change status. */
  async update(id, { tableNumber, capacity, location }) {
    await this._ready();
    const item = await this.findById(id);
    if (!item) return null;
    await db.query('UPDATE tables SET table_number = ?, capacity = ?, location = ? WHERE table_id = ?', [
      tableNumber ?? item.table_number,
      capacity ?? item.capacity,
      location ?? item.location,
      id,
    ]);
    return this.findById(id);
  }

  async setStatus(id, status) {
    await this._ready();
    const item = await this.findById(id);
    if (!item) return null;
    await db.query('UPDATE tables SET status = ? WHERE table_id = ?', [status, id]);
    return this.findById(id);
  }
}

module.exports = new TableRepository();