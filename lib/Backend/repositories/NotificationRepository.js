const db = require('../patterns/singletons/DatabaseManager');

class NotificationRepository {
  async findForEmployee(employeeId, roleId, { unreadOnly } = {}) {
    let sql = `SELECT * FROM notifications WHERE (employee_id = ? OR role_id = ?)`;
    const params = [employeeId, roleId];
    if (unreadOnly) sql += ' AND is_read = FALSE';
    sql += ' ORDER BY created_at DESC LIMIT 50';
    return db.query(sql, params);
  }

  async markRead(id) {
    await db.query('UPDATE notifications SET is_read = TRUE WHERE notification_id = ?', [id]);
  }

  async markAllRead(employeeId, roleId) {
    await db.query('UPDATE notifications SET is_read = TRUE WHERE employee_id = ? OR role_id = ?', [employeeId, roleId]);
  }
}

module.exports = new NotificationRepository();