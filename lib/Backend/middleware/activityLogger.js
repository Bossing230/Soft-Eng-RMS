const { AsyncLocalStorage } = require('async_hooks');
const db = require('../patterns/singletons/DatabaseManager');
const ensureActivityLogColumns = require('../database/ensure-activity-log-columns');

// ---------------------------------------------------------------------------
// Request context: lets logAction(...) know the IP address and device of the
// request that triggered it, WITHOUT changing any of the existing
// logAction(employeeId, action, module) calls in the controllers.
// Register `requestContext` once in server.js, AFTER the body parsers.
// ---------------------------------------------------------------------------
const requestStore = new AsyncLocalStorage();

/** "::ffff:203.0.113.5" -> "203.0.113.5", "::1" -> "127.0.0.1". */
function normalizeIp(raw) {
  if (!raw) return null;
  let ip = String(raw).split(',')[0].trim(); // a header can list several addresses; the first is the visitor
  if (ip.startsWith('::ffff:')) ip = ip.slice(7);
  if (ip === '::1') ip = '127.0.0.1';
  return ip.slice(0, 45);
}

/** A short device label from the browser's user-agent (Android and iOS are checked before Linux and macOS, which they also mention). */
function deviceFromUserAgent(userAgent) {
  if (!userAgent) return null;
  if (/Dart\//i.test(userAgent)) return 'App';
  if (/Android/i.test(userAgent)) return 'Android';
  if (/iPhone|iPad|iPod/i.test(userAgent)) return 'iOS';
  if (/Windows/i.test(userAgent)) return 'Windows';
  if (/Macintosh|Mac OS X/i.test(userAgent)) return 'macOS';
  if (/CrOS/i.test(userAgent)) return 'ChromeOS';
  if (/Linux/i.test(userAgent)) return 'Linux';
  return 'Other';
}

/**
 * The visitor's real address. Behind Render the app is reached through internal
 * proxies, so req.ip is often a private 10.x address. The public address of the
 * visitor arrives in these headers (set by the network edge in front of Render),
 * so they are tried first, then req.ip. This is for the Activity Log display
 * only, never for security decisions, because a header can be forged.
 */
function clientIp(req) {
  const h = req.headers;
  return normalizeIp(h['cf-connecting-ip'] || h['true-client-ip'] || req.ip);
}

function requestContext(req, res, next) {
  requestStore.run(
    { ip: clientIp(req), device: deviceFromUserAgent(req.headers['user-agent']) },
    next
  );
}

function getRequestContext() {
  return requestStore.getStore() || {};
}

// ---------------------------------------------------------------------------
// Schema: make sure the ip_address / device columns exist, once per server run.
// ---------------------------------------------------------------------------
let schemaReady = null;

function ready() {
  if (!schemaReady) {
    schemaReady = ensureActivityLogColumns().catch((err) => {
      schemaReady = null; // try again on the next log entry
      throw err;
    });
  }
  return schemaReady;
}

/**
 * Logs an employee action to the activity_logs table.
 * Call this from controllers after a meaningful state change
 * (e.g. logAction(req.user.employeeId, 'Created menu item', 'menu')).
 * The IP address and device of the current request are added automatically.
 * Logging never throws: a failure is printed and the request carries on.
 */
async function logAction(employeeId, action, module) {
  try {
    let withContext = true;
    try {
      await ready();
    } catch (err) {
      // Could not add the new columns: still record the action itself.
      withContext = false;
      console.error('Activity log columns check failed:', err.message);
    }

    if (withContext) {
      const { ip = null, device = null } = getRequestContext();
      await db.query(
        'INSERT INTO activity_logs (employee_id, action, module, ip_address, device) VALUES (?, ?, ?, ?, ?)',
        [employeeId, action, module, ip, device]
      );
    } else {
      await db.query('INSERT INTO activity_logs (employee_id, action, module) VALUES (?, ?, ?)', [
        employeeId,
        action,
        module,
      ]);
    }
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

module.exports = {
  logAction,
  requestContext,
  checkLoginThrottle,
  registerFailedLogin,
  clearFailedLogins,
};