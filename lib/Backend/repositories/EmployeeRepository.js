const db = require('../patterns/singletons/DatabaseManager');
const ensureAuthColumns = require('../database/ensure-auth-columns');

/**
 * Repository Pattern — centralizes all data-access for employees so
 * controllers never write raw SQL directly.
 */
class EmployeeRepository {
  /** Makes sure employees.lockout_level and the password_resets table exist. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureAuthColumns().catch((err) => {
        this._schema = null;
        throw err;
      });
    }
    return this._schema;
  }

  async findByUsername(username) {
    await this._ready();
    const rows = await db.query(
      `SELECT e.*, r.role_name FROM employees e
       JOIN roles r ON e.role_id = r.role_id
       WHERE e.username = ?`,
      [username]
    );
    return rows[0] || null;
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query(
      `SELECT e.*, r.role_name FROM employees e
       JOIN roles r ON e.role_id = r.role_id
       WHERE e.employee_id = ?`,
      [id]
    );
    return rows[0] || null;
  }

  async findAll({ role, status } = {}) {
    let sql = `SELECT e.employee_id, e.name, e.username, e.email, e.profile_image, e.status, e.created_at, r.role_name
               FROM employees e JOIN roles r ON e.role_id = r.role_id WHERE 1=1`;
    const params = [];
    if (role) { sql += ' AND r.role_name = ?'; params.push(role); }
    if (status) { sql += ' AND e.status = ?'; params.push(status); }
    sql += ' ORDER BY e.created_at DESC';
    return db.query(sql, params);
  }

  async create({ name, username, email, passwordHash, roleId, profileImage }) {
    const result = await db.query(
      `INSERT INTO employees (name, username, email, password, role_id, profile_image) VALUES (?, ?, ?, ?, ?, ?)`,
      [name, username, email, passwordHash, roleId, profileImage || null]
    );
    return this.findById(result.insertId);
  }

  async update(id, fields) {
    const keys = Object.keys(fields);
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(`UPDATE employees SET ${setClause} WHERE employee_id = ?`, [...Object.values(fields), id]);
    return this.findById(id);
  }

  async setStatus(id, status) {
    await db.query('UPDATE employees SET status = ? WHERE employee_id = ?', [status, id]);
    return this.findById(id);
  }

  // --- Login lockout -------------------------------------------------------
  // failed_login_attempts / locked_until already existed in schema.sql but
  // were unused; lockout_level is new (see ensure-auth-columns.js). Together:
  //   failed_login_attempts  wrong passwords since the last lock (or since
  //                           account creation / password change)
  //   locked_until            NULL, or when the current lock expires
  //   lockout_level           how many times in a row this account has been
  //                           locked since its last real password change —
  //                           only a password change resets this, not time
  //                           or a successful login, by design (see
  //                           authController.js for the escalation math)

  /** Adds one to the wrong-password count and returns the new total. */
  async incrementFailedAttempts(id) {
    await this._ready();
    await db.query('UPDATE employees SET failed_login_attempts = failed_login_attempts + 1 WHERE employee_id = ?', [id]);
    const employee = await this.findById(id);
    return employee.failed_login_attempts;
  }

  /** Locks the account until [lockedUntil] and records the new escalation level, resetting the attempt count. */
  async lockAccount(id, { lockedUntil, lockoutLevel }) {
    await this._ready();
    await db.query(
      'UPDATE employees SET locked_until = ?, lockout_level = ?, failed_login_attempts = 0 WHERE employee_id = ?',
      [lockedUntil, lockoutLevel, id]
    );
    return this.findById(id);
  }

  /** After a successful login: clear the attempt count (locked_until is already past by then). */
  async clearFailedAttempts(id) {
    await this._ready();
    await db.query('UPDATE employees SET failed_login_attempts = 0, locked_until = NULL WHERE employee_id = ?', [id]);
  }

  /** After an actual password change: fully clears the lockout history, including the escalation level. */
  async clearLockoutEscalation(id) {
    await this._ready();
    await db.query(
      'UPDATE employees SET failed_login_attempts = 0, locked_until = NULL, lockout_level = 0 WHERE employee_id = ?',
      [id]
    );
  }

  // Kept for compatibility with any existing caller; prefer the methods
  // above for new code, since those also keep lockout_level in step.
  async recordFailedAttempt(id, attempts, lockedUntil) {
    await db.query('UPDATE employees SET failed_login_attempts = ?, locked_until = ? WHERE employee_id = ?', [attempts, lockedUntil, id]);
  }

  async resetFailedAttempts(id) {
    await db.query('UPDATE employees SET failed_login_attempts = 0, locked_until = NULL WHERE employee_id = ?', [id]);
  }

  async updatePassword(id, passwordHash) {
    await db.query('UPDATE employees SET password = ? WHERE employee_id = ?', [passwordHash, id]);
  }

  async getRoleByName(roleName) {
    const rows = await db.query('SELECT * FROM roles WHERE role_name = ?', [roleName]);
    return rows[0] || null;
  }
}

module.exports = new EmployeeRepository();