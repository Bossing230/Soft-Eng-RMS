/**
 * Who is active right now.
 *
 * Every authenticated request refreshes employees.last_seen_at (at most once a
 * minute per person, so it costs almost nothing). Open dashboards already
 * contact the server every 20 seconds for notifications, so anyone with the app
 * open counts as active. The manager dashboard treats a person as "on duty"
 * when they are clocked in OR were seen within ACTIVE_WINDOW_MINUTES.
 *
 * Logging out clears the timestamp straight away, so a person who leaves does
 * not stay "on duty" for the rest of the window.
 *
 * The last_seen_at column is added automatically the first time it is needed.
 */
const db = require('../patterns/singletons/DatabaseManager');

const ACTIVE_WINDOW_MINUTES = 5;
const TOUCH_EVERY_MS = 60 * 1000;
const DUPLICATE_COLUMN = 1060;

const lastTouch = new Map(); // employeeId -> when we last wrote to the database
const pending = new Map(); // employeeId -> the write currently in flight

let schemaReady = null;

/** Makes sure employees.last_seen_at exists, once per server run. */
function ready() {
  if (!schemaReady) {
    schemaReady = (async () => {
      const rows = await db.query(
        `SELECT column_name AS name
           FROM information_schema.columns
          WHERE table_schema = DATABASE() AND table_name = 'employees' AND column_name = 'last_seen_at'`
      );
      if (!rows.length) {
        try {
          await db.query('ALTER TABLE employees ADD COLUMN last_seen_at DATETIME NULL');
        } catch (err) {
          // Another request or server instance added it first: that is fine.
          if (err.errno !== DUPLICATE_COLUMN) throw err;
        }
      }
    })().catch((err) => {
      schemaReady = null; // try again on the next request
      throw err;
    });
  }
  return schemaReady;
}

/** Marks an employee as active now. Never throws and never makes the request wait. */
function touch(employeeId) {
  const now = Date.now();
  if (now - (lastTouch.get(employeeId) || 0) < TOUCH_EVERY_MS) return;
  lastTouch.set(employeeId, now);

  const task = ready()
    .then(() => db.query('UPDATE employees SET last_seen_at = NOW() WHERE employee_id = ?', [employeeId]))
    .catch((err) => console.error('Could not record last seen:', err.message))
    .then(() => {
      if (pending.get(employeeId) === task) pending.delete(employeeId);
    });
  pending.set(employeeId, task);
}

/** Marks an employee as no longer active (used when they log out). */
async function clear(employeeId) {
  lastTouch.delete(employeeId);
  await pending.get(employeeId); // let an in-flight write finish first so it can't undo this
  await ready();
  await db.query('UPDATE employees SET last_seen_at = NULL WHERE employee_id = ?', [employeeId]);
}

/** Express middleware for the logout route: clear presence, then carry on. */
function clearOnLogout(req, res, next) {
  clear(req.user.employeeId)
    .catch((err) => console.error('Could not clear last seen:', err.message))
    .finally(() => next());
}

module.exports = { ACTIVE_WINDOW_MINUTES, ready, touch, clear, clearOnLogout };