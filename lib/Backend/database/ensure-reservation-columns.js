/**
 * Prepares the reservations table for the new Reservations feature:
 *   - notes      (optional special request, e.g. "Birthday celebration")
 *   - two ordinary indexes so booking lookups stay fast
 *   - removes the old UNIQUE (table, date, time) rule. That rule also counted
 *     CANCELLED bookings, so a table could never be booked again at the same
 *     time after a cancellation, and it only caught identical times, never
 *     overlaps (7:00 and 7:30 on one table). The code now checks overlaps
 *     itself, inside a transaction that locks the table.
 *   - one time only, together with that removal: tables left stuck as
 *     'reserved' by the old behaviour (every booking used to flag its table as
 *     reserved immediately, even for next week) go back to 'available'. A table
 *     now shows as reserved automatically shortly before a booking.
 *
 * It runs by itself the first time the reservation code touches the database
 * (see ReservationRepository), so a deploy needs no manual SQL. It is safe to
 * run any number of times. You can also run it by hand from lib/Backend:
 *     node database/ensure-reservation-columns.js
 */
if (require.main === module) {
  try {
    require('dotenv').config();
  } catch (_) {
    // dotenv not installed: rely on variables already set in the environment.
  }
}

const db = require('../patterns/singletons/DatabaseManager');

const DUPLICATE_COLUMN = 1060;
const DUPLICATE_INDEX = 1061;
const CANT_DROP_INDEX = 1091;

async function runIgnoring(sql, errno) {
  try {
    await db.query(sql);
  } catch (err) {
    // Another request or server instance did it first: that is fine.
    if (err.errno !== errno) throw err;
  }
}

async function ensureReservationColumns() {
  const columns = await db.query(
    `SELECT column_name AS name
       FROM information_schema.columns
      WHERE table_schema = DATABASE() AND table_name = 'reservations'`
  );
  const have = new Set(columns.map((r) => String(r.name).toLowerCase()));

  if (!have.has('notes')) {
    await runIgnoring('ALTER TABLE reservations ADD COLUMN notes VARCHAR(255) NULL', DUPLICATE_COLUMN);
  }

  // Plain indexes first: the foreign key on table_id needs an index to lean on
  // once the old unique one is gone.
  await runIgnoring(
    'ALTER TABLE reservations ADD INDEX idx_res_table_slot (table_id, reservation_date, reservation_time)',
    DUPLICATE_INDEX
  );
  await runIgnoring('ALTER TABLE reservations ADD INDEX idx_res_date_status (reservation_date, status)', DUPLICATE_INDEX);

  const unique = await db.query(
    `SELECT index_name AS name
       FROM information_schema.statistics
      WHERE table_schema = DATABASE() AND table_name = 'reservations' AND index_name = 'uniq_table_slot'
      LIMIT 1`
  );
  if (unique.length) {
    try {
      await db.query(`UPDATE tables SET status = 'available' WHERE status = 'reserved'`);
      await runIgnoring('ALTER TABLE reservations DROP INDEX uniq_table_slot', CANT_DROP_INDEX);
    } catch (err) {
      // Not fatal: bookings still work, only re-booking a cancelled slot stays blocked.
      console.warn('[reservations] could not remove the old unique rule:', err.message);
    }
  }
}

module.exports = ensureReservationColumns;

if (require.main === module) {
  console.log(`Connecting to ${process.env.DB_HOST || 'localhost'} / ${process.env.DB_NAME || 'rms_db'} ...`);
  ensureReservationColumns()
    .then(() => {
      console.log('The reservations table is up to date.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Failed:', err.message);
      process.exit(1);
    });
}