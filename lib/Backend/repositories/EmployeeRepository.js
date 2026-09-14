const db = require('../patterns/singletons/DatabaseManager');

/**
 * Repository Pattern — centralizes all data-access for employees so
 * controllers never write raw SQL directly.
 */
class EmployeeRepository {
  async findByUsername(username) {
    const rows = await db.query(
      `SELECT e.*, r.role_name FROM employees e
       JOIN roles r ON e.role_id = r.role_id
       WHERE e.username = ?`,
      [username]
    );
    return rows[0] || null;
  }

  async findById(id) {
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