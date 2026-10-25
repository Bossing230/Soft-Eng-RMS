/**
 * Is this employee's account still active?
 *
 * Login tokens last hours and say nothing about the account after they are
 * issued, so without a check a deleted or deactivated person could keep using
 * the app on another device until the token expired. The authenticate
 * middleware asks this guard on every request. The answer is remembered for 30
 * seconds per person, so it costs about one tiny query per person per 30 seconds.
 *
 * If the database cannot be read, the guard lets the request through (and logs
 * the problem) rather than signing everybody out because of a brief hiccup.
 */
const db = require('../patterns/singletons/DatabaseManager');

const TTL_MS = 30 * 1000;
const cache = new Map(); // employeeId -> { active, at }

async function isActive(employeeId) {
  const now = Date.now();
  const hit = cache.get(employeeId);
  if (hit && now - hit.at < TTL_MS) return hit.active;

  try {
    const rows = await db.query('SELECT status FROM employees WHERE employee_id = ?', [employeeId]);
    const active = Boolean(rows[0]) && rows[0].status === 'active';
    cache.set(employeeId, { active, at: now });
    return active;
  } catch (err) {
    console.error('Could not check the account status:', err.message);
    return true;
  }
}

/** Takes effect immediately on this server, instead of waiting for the cache to expire. */
function markInactive(employeeId) {
  cache.set(employeeId, { active: false, at: Date.now() });
}

module.exports = { isActive, markInactive };