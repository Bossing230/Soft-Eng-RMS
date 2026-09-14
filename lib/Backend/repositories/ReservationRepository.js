const db = require('../patterns/singletons/DatabaseManager');

class ReservationRepository {
  async findAll({ date, status } = {}) {
    let sql = `SELECT r.*, t.table_number FROM reservations r
               JOIN tables t ON r.table_id = t.table_id WHERE 1=1`;
    const params = [];
    if (date) { sql += ' AND r.reservation_date = ?'; params.push(date); }
    if (status) { sql += ' AND r.status = ?'; params.push(status); }
    sql += ' ORDER BY r.reservation_date, r.reservation_time';
    return db.query(sql, params);
  }

  async findById(id) {
    const rows = await db.query(
      `SELECT r.*, t.table_number FROM reservations r
       JOIN tables t ON r.table_id = t.table_id WHERE r.reservation_id = ?`,
      [id]
    );
    return rows[0] || null;
  }

  /** Returns true if the table is already booked (non-cancelled) at that date/time. */
  async isTableTaken(tableId, date, time, excludeReservationId = null) {
    let sql = `SELECT reservation_id FROM reservations
               WHERE table_id = ? AND reservation_date = ? AND reservation_time = ?
               AND status NOT IN ('cancelled', 'no_show')`;
    const params = [tableId, date, time];
    if (excludeReservationId) { sql += ' AND reservation_id != ?'; params.push(excludeReservationId); }
    const rows = await db.query(sql, params);
    return rows.length > 0;
  }

  async create({ tableId, customerName, contactNumber, date, time, guestCount, createdBy }) {
    const result = await db.query(
      `INSERT INTO reservations (table_id, customer_name, contact_number, reservation_date, reservation_time, guest_count, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [tableId, customerName, contactNumber, date, time, guestCount, createdBy]
    );
    await db.query('UPDATE tables SET status = ? WHERE table_id = ?', ['reserved', tableId]);
    return this.findById(result.insertId);
  }

  async update(id, fields) {
    const keys = Object.keys(fields);
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(`UPDATE reservations SET ${setClause} WHERE reservation_id = ?`, [...Object.values(fields), id]);
    return this.findById(id);
  }

  async setStatus(id, status) {
    const reservation = await this.findById(id);
    await db.query('UPDATE reservations SET status = ? WHERE reservation_id = ?', [status, id]);
    if (['cancelled', 'completed', 'no_show'].includes(status) && reservation) {
      await db.query('UPDATE tables SET status = ? WHERE table_id = ?', ['available', reservation.table_id]);
    }
    return this.findById(id);
  }

  async findAvailableTables(date, time, guestCount) {
    return db.query(
      `SELECT * FROM tables t WHERE t.capacity >= ? AND t.table_id NOT IN (
         SELECT table_id FROM reservations
         WHERE reservation_date = ? AND reservation_time = ? AND status NOT IN ('cancelled','no_show')
       ) ORDER BY t.capacity ASC`,
      [guestCount, date, time]
    );
  }
}

module.exports = new ReservationRepository();