const db = require('../patterns/singletons/DatabaseManager');
const ensureTableColumns = require('../database/ensure-table-columns');

// Restaurant-local "now", the same setting the reports and reservations use
// (REPORT_TZ_OFFSET_HOURS is 8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;
const LOCAL_NOW = `DATE_ADD(NOW(), INTERVAL ${TZ_OFFSET_HOURS} HOUR)`;
const LOCAL_TODAY = `DATE(${LOCAL_NOW})`;

// A free table shows as "reserved" from this many minutes before a booking
// until this many minutes after it (while the party has not arrived yet), so a
// booking for next week no longer blocks the table today.
const RESERVED_LEAD_MINUTES = 60;
const RESERVED_GRACE_MINUTES = 30;

const BOOKING_SOON = `
  r.table_id = t.table_id
  AND r.status IN ('pending','confirmed')
  AND TIMESTAMP(r.reservation_date, r.reservation_time)
      BETWEEN DATE_SUB(${LOCAL_NOW}, INTERVAL ${RESERVED_GRACE_MINUTES} MINUTE)
          AND DATE_ADD(${LOCAL_NOW}, INTERVAL ${RESERVED_LEAD_MINUTES} MINUTE)`;

// What staff should see: the stored status, except that an 'available' table
// with a booking about to start counts as 'reserved'.
const EFFECTIVE_STATUS = `
  CASE WHEN t.status = 'available'
        AND EXISTS (SELECT 1 FROM reservations r WHERE ${BOOKING_SOON})
       THEN 'reserved' ELSE t.status END`;

/** Swaps in the status staff should see, keeping the stored one as stored_status. */
function withEffectiveStatus(row) {
  const { effective_status: effective, ...table } = row;
  return { ...table, stored_status: table.status, status: effective };
}

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

  /** Tables with the status staff should see (an imminent booking makes a free table "reserved"). */
  async findAll({ status } = {}) {
    await this._ready();
    let sql = `SELECT x.* FROM (
                 SELECT t.*, ${EFFECTIVE_STATUS} AS effective_status FROM tables t
               ) x WHERE 1=1`;
    const params = [];
    if (status) {
      sql += ' AND x.effective_status = ?';
      params.push(status);
    }
    sql += ' ORDER BY LENGTH(x.table_number), x.table_number'; // so T2 sorts before T10
    const rows = await db.query(sql, params);
    return rows.map(withEffectiveStatus);
  }

  /**
   * Every table for the board, each with a guest name when there is one:
   * the party seated there today for an occupied table, or the party it is
   * being held for when it shows as reserved.
   */
  async findBoard() {
    await this._ready();
    const rows = await db.query(
      `SELECT t.*,
              ${EFFECTIVE_STATUS} AS effective_status,
              (SELECT r.customer_name FROM reservations r
                 WHERE r.table_id = t.table_id AND r.status = 'seated' AND r.reservation_date = ${LOCAL_TODAY}
                 ORDER BY r.reservation_id DESC LIMIT 1) AS seated_name,
              (SELECT r.customer_name FROM reservations r
                 WHERE ${BOOKING_SOON}
                 ORDER BY TIMESTAMP(r.reservation_date, r.reservation_time) LIMIT 1) AS reserved_name
         FROM tables t
        ORDER BY LENGTH(t.table_number), t.table_number`
    );
    return rows.map((row) => {
      const { seated_name: seated, reserved_name: reserved, ...rest } = row;
      const table = withEffectiveStatus(rest);
      const name = table.status === 'occupied' ? seated : table.status === 'reserved' ? reserved : null;
      return { ...table, customer_name: name || null };
    });
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