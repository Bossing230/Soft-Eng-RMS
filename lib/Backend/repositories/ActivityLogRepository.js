const db = require('../patterns/singletons/DatabaseManager');
const ensureActivityLogColumns = require('../database/ensure-activity-log-columns');

// Same setting the reports use: hours to add to stored timestamps so dates and
// times are restaurant-local (8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;

// "auth" entries are split into three kinds by what the action text says, so
// the page can show Login / Logout / Password badges and filter on them.
const AUTH_KIND_SQL = {
  login: "l.action LIKE 'Logged in%'",
  logout: "l.action LIKE 'Logged out%'",
  password: "l.action LIKE '%password%'",
};

/** The badge kind of one entry: login / logout / password, or the module name. */
function kindFor(module, action) {
  if (module === 'auth') {
    const text = String(action).toLowerCase();
    if (text.startsWith('logged in')) return 'login';
    if (text.startsWith('logged out')) return 'logout';
    if (text.includes('password')) return 'password';
  }
  return module;
}

class ActivityLogRepository {
  /** Makes sure the ip_address / device columns and indexes exist, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureActivityLogColumns().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  /** Today's date (YYYY-MM-DD) in restaurant-local time. */
  async todayLocal() {
    const rows = await db.query(
      `SELECT DATE_FORMAT(DATE(DATE_ADD(NOW(), INTERVAL ${TZ_OFFSET_HOURS} HOUR)), '%Y-%m-%d') AS today`
    );
    return rows[0].today;
  }

  /** The WHERE clause and its values for the filters. `from` and `to` are whole local days, both included. */
  _where({ from, to, type, role, search, employeeId }) {
    const clauses = [
      `l.timestamp >= DATE_SUB(CAST(? AS DATETIME), INTERVAL ${TZ_OFFSET_HOURS} HOUR)`,
      `l.timestamp < DATE_SUB(DATE_ADD(CAST(? AS DATETIME), INTERVAL 1 DAY), INTERVAL ${TZ_OFFSET_HOURS} HOUR)`,
    ];
    const params = [from, to];

    if (employeeId) {
      clauses.push('l.employee_id = ?');
      params.push(employeeId);
    }
    if (role) {
      clauses.push('r.role_name = ?');
      params.push(role);
    }
    if (type) {
      if (AUTH_KIND_SQL[type]) {
        clauses.push(`(l.module = 'auth' AND ${AUTH_KIND_SQL[type]})`);
      } else {
        clauses.push('l.module = ?');
        params.push(type);
      }
    }
    if (search) {
      const like = `%${search.replace(/[\\%_]/g, '\\$&')}%`;
      clauses.push('(l.action LIKE ? OR l.module LIKE ? OR e.name LIKE ? OR l.ip_address LIKE ?)');
      params.push(like, like, like, like);
    }

    return { where: clauses.join(' AND '), params };
  }

  /**
   * One page of entries, newest first, plus the total that match the filters.
   * `limit` and `page` must already be sanitized integers (the controller does that).
   */
  async findPage({ from, to, type, role, search, employeeId, page, limit }) {
    await this._ready();
    const { where, params } = this._where({ from, to, type, role, search, employeeId });
    const base = `FROM activity_logs l
                  JOIN employees e ON e.employee_id = l.employee_id
                  JOIN roles r ON r.role_id = e.role_id
                 WHERE ${where}`;

    const offset = (page - 1) * limit;
    const [[countRow], rows] = await Promise.all([
      db.query(`SELECT COUNT(*) AS total ${base}`, params),
      db.query(
        `SELECT l.log_id, l.action, l.module, l.ip_address, l.device,
                DATE_FORMAT(DATE_ADD(l.timestamp, INTERVAL ${TZ_OFFSET_HOURS} HOUR), '%Y-%m-%d %H:%i:%s') AS local_time,
                e.employee_id, e.name AS employee_name, r.role_name
           ${base}
          ORDER BY l.timestamp DESC, l.log_id DESC
          LIMIT ${limit} OFFSET ${offset}`,
        params
      ),
    ]);

    return {
      total: Number(countRow.total),
      logs: rows.map((r) => ({
        id: r.log_id,
        kind: kindFor(r.module, r.action),
        module: r.module,
        details: r.action,
        time: r.local_time,
        user_id: r.employee_id,
        user_name: r.employee_name,
        role: r.role_name,
        ip: r.ip_address,
        device: r.device,
      })),
    };
  }

  /** The kinds that actually exist in the log (feeds the activity dropdown). */
  async kinds({ employeeId } = {}) {
    await this._ready();
    const rows = await db.query(
      `SELECT DISTINCT module FROM activity_logs ${employeeId ? 'WHERE employee_id = ?' : ''} ORDER BY module`,
      employeeId ? [employeeId] : []
    );
    const kinds = new Set();
    for (const { module } of rows) {
      if (module === 'auth') Object.keys(AUTH_KIND_SQL).forEach((k) => kinds.add(k));
      else kinds.add(module);
    }
    return [...kinds].sort();
  }
}

module.exports = new ActivityLogRepository();