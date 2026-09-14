const db = require('../patterns/singletons/DatabaseManager');

/**
 * Logs an employee action to the activity_logs table.
 * Call this from controllers after a meaningful state change
 * (e.g. logAction(req.user.employeeId, 'Created menu item', 'menu')).
 */
async function logAction(employeeId, action, module) {
  try {
    await db.query(
      'INSERT INTO activity_logs (employee_id, action, module) VALUES (?, ?, ?)',
      [employeeId, action, module]
    );
  } catch (err) {
    console.error('Failed to write activity log:', err.message);
  }
}

/** Basic login-attempt rate limiting, applied only to the /login route. */
const loginAttempts = new Map(); // key: username -> { count, lockUntil }

function checkLoginThrottle(req, res, next) {
  const { username } = req.body;
  const record = loginAttempts.get(username);
  if (record && record.lockUntil && record.lockUntil > Date.now()) {
    const secondsLeft = Math.ceil((record.lockUntil - Date.now()) / 1000);
    return res.status(429).json({ error: `Too many failed attempts. Try again in ${secondsLeft}s.` });
  }
  next();
}

function registerFailedLogin(username) {
  const record = loginAttempts.get(username) || { count: 0 };
  record.count += 1;
  if (record.count >= 5) {
    record.lockUntil = Date.now() + 5 * 60 * 1000; // lock 5 minutes
    record.count = 0;
  }
  loginAttempts.set(username, record);
}

function clearFailedLogins(username) {
  loginAttempts.delete(username);
}

module.exports = { logAction, checkLoginThrottle, registerFailedLogin, clearFailedLogins };