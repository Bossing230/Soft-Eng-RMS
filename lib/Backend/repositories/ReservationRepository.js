const db = require('../patterns/singletons/DatabaseManager');
const ensureReservationColumns = require('../database/ensure-reservation-columns');
const ensureTableColumns = require('../database/ensure-table-columns');

// Bookings are entered as restaurant wall-clock time, so "now" and "today" are
// restaurant-local: REPORT_TZ_OFFSET_HOURS is added to the database clock (8 on
// a UTC database in the Philippines), the same setting the reports use.
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;
const LOCAL_NOW = `DATE_ADD(NOW(), INTERVAL ${TZ_OFFSET_HOURS} HOUR)`;
const LOCAL_TODAY = `DATE(${LOCAL_NOW})`;

// How long one booking holds its table. Two bookings on the same table must be
// at least this many minutes apart.
const HOLD_MINUTES = Number(process.env.RESERVATION_HOLD_MINUTES) || 90;

// A booking can be entered for a time that passed this many minutes ago (for
// example a guest who walked in a moment ago), but not further back.
const PAST_GRACE_MINUTES = 5;

// Statuses that still use up their table.
const BLOCKING = `'pending','confirmed','seated'`;

/** Which status can follow which. Anything else is refused. */
const TRANSITIONS = {
  pending: ['confirmed', 'seated', 'cancelled', 'no_show'],
  confirmed: ['seated', 'cancelled', 'no_show'],
  seated: ['completed'],
  completed: [],
  cancelled: [],
  no_show: [],
};

const SCOPES = ['today', 'upcoming', 'all', 'cancelled', 'date'];
const BOARD_LIMIT = 300;

const httpError = (status, message) => Object.assign(new Error(message), { status });

/** "19:30:00" -> "7:30 PM" */
function time12(value) {
  const [h, m] = String(value).split(':').map(Number);
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

const SELECT_ROW = `
  r.reservation_id, r.table_id, t.table_number, t.capacity AS table_capacity,
  r.customer_name, r.contact_number, r.reservation_date, r.reservation_time,
  r.guest_count, r.status, r.notes,
  TIMESTAMPDIFF(MINUTE, ${LOCAL_NOW}, TIMESTAMP(r.reservation_date, r.reservation_time)) AS minutes_until`;

class ReservationRepository {
  /** Makes sure the notes column, indexes and the 'cleaning'/'location' table columns exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureReservationColumns()
        .then(() => ensureTableColumns())
        .catch((err) => {
          this._schema = null; // try again on the next request
          throw err;
        });
    }
    return this._schema;
  }

  // ---- reading ----

  /** Plain list, kept for older callers. The Reservations page uses board(). */
  async findAll({ date, status } = {}) {
    await this._ready();
    let sql = `SELECT ${SELECT_ROW} FROM reservations r JOIN tables t ON r.table_id = t.table_id WHERE 1=1`;
    const params = [];
    if (date) { sql += ' AND r.reservation_date = ?'; params.push(date); }
    if (status) { sql += ' AND r.status = ?'; params.push(status); }
    sql += ' ORDER BY r.reservation_date, r.reservation_time';
    return db.query(sql, params);
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query(
      `SELECT ${SELECT_ROW} FROM reservations r JOIN tables t ON r.table_id = t.table_id WHERE r.reservation_id = ?`,
      [id]
    );
    return rows[0] || null;
  }

  /**
   * Everything the Reservations page needs in one go: the list for the chosen
   * scope, today's summary numbers, the counts shown on the filter chips, and
   * the restaurant's own idea of "now" and "today".
   */
  async board({ scope = 'today', date = null, search = '' } = {}) {
    await this._ready();
    const safeScope = SCOPES.includes(scope) ? scope : 'today';

    const where = [];
    const params = [];
    let order = 'r.reservation_date, r.reservation_time';
    switch (safeScope) {
      case 'today':
        where.push(`r.reservation_date = ${LOCAL_TODAY}`);
        break;
      case 'upcoming':
        where.push(`r.reservation_date > ${LOCAL_TODAY}`, `r.status IN ('pending','confirmed')`);
        break;
      case 'cancelled':
        where.push(`r.status IN ('cancelled','no_show')`);
        order = 'r.reservation_date DESC, r.reservation_time DESC';
        break;
      case 'date':
        where.push('r.reservation_date = ?');
        params.push(date);
        break;
      default: // all
        order = 'r.reservation_date DESC, r.reservation_time DESC';
    }
    if (search) {
      const like = `%${search.replace(/[\\%_]/g, '\\$&')}%`;
      where.push('(r.customer_name LIKE ? OR r.contact_number LIKE ? OR t.table_number LIKE ?)');
      params.push(like, like, like);
    }

    const [rows, statsRows, countRows, clockRows] = await Promise.all([
      db.query(
        `SELECT ${SELECT_ROW}
           FROM reservations r JOIN tables t ON r.table_id = t.table_id
          ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
          ORDER BY ${order}
          LIMIT ${BOARD_LIMIT}`,
        params
      ),
      db.query(
        `SELECT COALESCE(SUM(status NOT IN ('cancelled','no_show')), 0) AS bookings,
                COALESCE(SUM(CASE WHEN status IN ('pending','confirmed') THEN guest_count END), 0) AS guests_expected,
                COALESCE(SUM(status = 'seated'), 0) AS seated,
                COALESCE(SUM(status IN ('cancelled','no_show')), 0) AS cancelled
           FROM reservations
          WHERE reservation_date = ${LOCAL_TODAY}`
      ),
      db.query(
        `SELECT COALESCE(SUM(reservation_date = ${LOCAL_TODAY} AND status NOT IN ('cancelled','no_show')), 0) AS today,
                COALESCE(SUM(reservation_date > ${LOCAL_TODAY} AND status IN ('pending','confirmed')), 0) AS upcoming,
                COALESCE(SUM(status IN ('cancelled','no_show')), 0) AS cancelled
           FROM reservations`
      ),
      db.query(
        `SELECT DATE_FORMAT(${LOCAL_NOW}, '%Y-%m-%d %H:%i:%s') AS now_local,
                DATE_FORMAT(${LOCAL_TODAY}, '%Y-%m-%d') AS today`
      ),
    ]);

    const stats = statsRows[0];
    const counts = countRows[0];
    return {
      now: clockRows[0].now_local,
      today: clockRows[0].today,
      scope: safeScope,
      stats: {
        bookings: Number(stats.bookings),
        guests_expected: Number(stats.guests_expected),
        seated: Number(stats.seated),
        cancelled: Number(stats.cancelled),
      },
      counts: {
        today: Number(counts.today),
        upcoming: Number(counts.upcoming),
        cancelled: Number(counts.cancelled),
      },
      reservations: rows.map((r) => ({ ...r, minutes_until: Number(r.minutes_until) })),
    };
  }

  /**
   * Tables that fit the party and have no booking within HOLD_MINUTES of the
   * requested time. `excludeId` is the booking being edited, so it does not
   * block its own table.
   */
  async findAvailableTables(date, time, guestCount, excludeId = null) {
    await this._ready();
    const params = [guestCount, date, time, HOLD_MINUTES];
    let exclude = '';
    if (excludeId) {
      exclude = 'AND r.reservation_id <> ?';
      params.push(excludeId);
    }
    return db.query(
      `SELECT t.table_id, t.table_number, t.capacity, t.location, t.status
         FROM tables t
        WHERE t.capacity >= ?
          AND NOT EXISTS (
                SELECT 1 FROM reservations r
                 WHERE r.table_id = t.table_id
                   AND r.status IN (${BLOCKING})
                   AND ABS(TIMESTAMPDIFF(MINUTE, TIMESTAMP(r.reservation_date, r.reservation_time), TIMESTAMP(?, ?))) < ?
                   ${exclude})
        ORDER BY t.capacity ASC, LENGTH(t.table_number), t.table_number`,
      params
    );
  }

  // ---- writing ----

  /**
   * Inside the caller's transaction: locks the table row (so two people booking
   * the same table at once are handled one after the other), then checks the
   * table exists, fits the party, the time is not in the past, and nothing else
   * is booked within HOLD_MINUTES. Throws a clear 4xx error otherwise.
   */
  async _assertBookable(conn, { tableId, date, time, guestCount, excludeId = null, checkPast = true }) {
    const [tables] = await conn.execute(
      'SELECT table_id, table_number, capacity FROM tables WHERE table_id = ? FOR UPDATE',
      [tableId]
    );
    const table = tables[0];
    if (!table) throw httpError(404, 'That table does not exist');
    if (guestCount > Number(table.capacity)) {
      throw httpError(400, `Table ${table.table_number} seats ${table.capacity}, but the booking is for ${guestCount} guests`);
    }

    if (checkPast) {
      const [clock] = await conn.execute(
        `SELECT TIMESTAMPDIFF(MINUTE, ${LOCAL_NOW}, TIMESTAMP(?, ?)) AS minutes_until`,
        [date, time]
      );
      if (Number(clock[0].minutes_until) < -PAST_GRACE_MINUTES) {
        throw httpError(400, 'That date and time has already passed');
      }
    }

    const params = [tableId, date, time, HOLD_MINUTES];
    let exclude = '';
    if (excludeId) {
      exclude = 'AND r.reservation_id <> ?';
      params.push(excludeId);
    }
    const [clashes] = await conn.execute(
      `SELECT r.customer_name, r.reservation_time
         FROM reservations r
        WHERE r.table_id = ?
          AND r.status IN (${BLOCKING})
          AND ABS(TIMESTAMPDIFF(MINUTE, TIMESTAMP(r.reservation_date, r.reservation_time), TIMESTAMP(?, ?))) < ?
          ${exclude}
        ORDER BY r.reservation_time
        LIMIT 1`,
      params
    );
    if (clashes[0]) {
      throw httpError(
        409,
        `Table ${table.table_number} is already booked at ${time12(clashes[0].reservation_time)} (${clashes[0].customer_name}). ` +
          `A booking holds its table for ${HOLD_MINUTES} minutes, so choose another table or a time at least that far apart.`
      );
    }
    return table;
  }

  /** Staff-entered bookings start as 'confirmed' (the guest has already agreed). */
  async create({ tableId, customerName, contactNumber, date, time, guestCount, notes, createdBy }) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();
      await this._assertBookable(conn, { tableId, date, time, guestCount });
      const [result] = await conn.execute(
        `INSERT INTO reservations
           (table_id, customer_name, contact_number, reservation_date, reservation_time, guest_count, status, notes, created_by)
         VALUES (?, ?, ?, ?, ?, ?, 'confirmed', ?, ?)`,
        [tableId, customerName, contactNumber || null, date, time, guestCount, notes || null, createdBy]
      );
      await conn.commit();
      return this.findById(result.insertId);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  /** Edits a booking that has not been seated yet (new table, date, time, party, details). */
  async update(id, { tableId, customerName, contactNumber, date, time, guestCount, notes }) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();
      const [rows] = await conn.execute(
        'SELECT reservation_id, status, reservation_date, reservation_time FROM reservations WHERE reservation_id = ? FOR UPDATE',
        [id]
      );
      const current = rows[0];
      if (!current) throw httpError(404, 'Reservation not found');
      if (!['pending', 'confirmed'].includes(current.status)) {
        throw httpError(409, `A ${current.status.replace('_', ' ')} booking can no longer be edited`);
      }
      // Fixing the notes or table of a booking that is already running late must
      // work, so the "time has passed" check only applies when the time is changed.
      const timeUnchanged = current.reservation_date === date && current.reservation_time === time;
      await this._assertBookable(conn, { tableId, date, time, guestCount, excludeId: id, checkPast: !timeUnchanged });
      await conn.execute(
        `UPDATE reservations
            SET table_id = ?, customer_name = ?, contact_number = ?, reservation_date = ?,
                reservation_time = ?, guest_count = ?, notes = ?
          WHERE reservation_id = ?`,
        [tableId, customerName, contactNumber || null, date, time, guestCount, notes || null, id]
      );
      await conn.commit();
      return this.findById(id);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  /**
   * Moves a booking to its next status, only along the allowed steps, and keeps
   * the table in step:
   *   seated    -> the table becomes occupied (refused if someone else is on it)
   *   completed -> an occupied table becomes available again
   * Cancelling or marking a no-show never touches the table, because a booking
   * that was never seated is not what is occupying it.
   * Resolves to { previous, reservation }.
   */
  async setStatus(id, next) {
    await this._ready();
    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();
      const [rows] = await conn.execute('SELECT reservation_id, table_id, status FROM reservations WHERE reservation_id = ? FOR UPDATE', [id]);
      const current = rows[0];
      if (!current) throw httpError(404, 'Reservation not found');

      if (!(TRANSITIONS[current.status] || []).includes(next)) {
        throw httpError(409, `A ${current.status.replace('_', ' ')} booking can't be changed to ${next.replace('_', ' ')}`);
      }

      if (next === 'seated') {
        const [tables] = await conn.execute('SELECT table_number, status FROM tables WHERE table_id = ? FOR UPDATE', [current.table_id]);
        if (tables[0] && tables[0].status === 'occupied') {
          throw httpError(409, `Table ${tables[0].table_number} is occupied right now. Free it first, then seat this booking.`);
        }
        await conn.execute(`UPDATE tables SET status = 'occupied' WHERE table_id = ?`, [current.table_id]);
      } else if (next === 'completed') {
        await conn.execute(`UPDATE tables SET status = 'available' WHERE table_id = ? AND status = 'occupied'`, [current.table_id]);
      }

      await conn.execute('UPDATE reservations SET status = ? WHERE reservation_id = ?', [next, id]);
      await conn.commit();
      return { previous: current.status, reservation: await this.findById(id) };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = new ReservationRepository();
module.exports.HOLD_MINUTES = HOLD_MINUTES;