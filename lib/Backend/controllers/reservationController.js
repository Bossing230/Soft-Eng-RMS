const ReservationRepository = require('../repositories/ReservationRepository');
const notifyRoles = require('../patterns/observers/notifyRoles');
const { logAction } = require('../middleware/activityLogger');

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });
const httpError = (status, message) => Object.assign(new Error(message), { status });

const SCOPES = ['today', 'upcoming', 'all', 'cancelled', 'date'];
const STATUSES = ['pending', 'confirmed', 'seated', 'completed', 'cancelled', 'no_show'];

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/;
const PHONE_RE = /^[0-9+\-\s()]{7,20}$/;

const NAME_MIN = 2;
const NAME_MAX = 100;
const GUESTS_MAX = 50;
const NOTES_MAX = 255;

/** True for a real calendar date written as YYYY-MM-DD. */
function isValidDate(value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

/** "19:30" or "19:30:00" -> "19:30:00" */
function normalizeTime(value) {
  if (typeof value !== 'string' || !TIME_RE.test(value.trim())) return null;
  const [h, m] = value.trim().split(':');
  return `${h}:${m}:00`;
}

/** "19:30:00" -> "7:30 PM" */
function time12(value) {
  const [h, m] = String(value).split(':').map(Number);
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/** Checks and cleans a booking from the app. Throws a 400 with a readable message. */
function normalizeBooking(body) {
  const tableId = Number(body.tableId);
  const customerName = typeof body.customerName === 'string' ? body.customerName.trim() : '';
  const contactNumber = typeof body.contactNumber === 'string' ? body.contactNumber.trim() : '';
  const notes = typeof body.notes === 'string' ? body.notes.trim() : '';
  const guestCount = Number(body.guestCount);
  const time = normalizeTime(body.time);

  if (!Number.isInteger(tableId) || tableId < 1) throw httpError(400, 'Choose a table');
  if (customerName.length < NAME_MIN || customerName.length > NAME_MAX) {
    throw httpError(400, `Customer name must be ${NAME_MIN} to ${NAME_MAX} characters`);
  }
  if (contactNumber && !PHONE_RE.test(contactNumber)) {
    throw httpError(400, 'Phone number can only contain digits, spaces, + - ( ) and be 7 to 20 characters');
  }
  if (!Number.isInteger(guestCount) || guestCount < 1 || guestCount > GUESTS_MAX) {
    throw httpError(400, `Guests must be a whole number from 1 to ${GUESTS_MAX}`);
  }
  if (!isValidDate(body.date)) throw httpError(400, 'Choose a valid date');
  if (!time) throw httpError(400, 'Choose a valid time');
  if (notes.length > NOTES_MAX) throw httpError(400, `Notes must be ${NOTES_MAX} characters or fewer`);

  return { tableId, customerName, contactNumber, date: body.date, time, guestCount, notes };
}

/** Tells the front desk and the manager. A failed notification never fails the booking. */
async function tellStaff(title, message, type) {
  try {
    await notifyRoles(['manager', 'cashier'], { title, message, type });
  } catch (err) {
    console.error('Reservation notification failed:', err.message);
  }
}

/** Older plain list (kept so nothing that still calls it breaks). */
exports.list = async (req, res) => {
  try {
    const { date, status } = req.query;
    res.json(await ReservationRepository.findAll({ date, status }));
  } catch (err) {
    fail(res, err);
  }
};

/**
 * GET /api/reservations/board?scope=today|upcoming|all|cancelled|date&date=YYYY-MM-DD&search=text
 * The list for the page plus today's summary numbers and the chip counts.
 */
exports.board = async (req, res) => {
  try {
    const scope = SCOPES.includes(req.query.scope) ? req.query.scope : 'today';
    let date = null;
    if (scope === 'date') {
      if (!isValidDate(req.query.date)) return res.status(400).json({ error: 'Choose a valid date' });
      date = req.query.date;
    }
    const search = typeof req.query.search === 'string' ? req.query.search.trim().slice(0, 60) : '';
    res.json(await ReservationRepository.board({ scope, date, search }));
  } catch (err) {
    fail(res, err);
  }
};

exports.getOne = async (req, res) => {
  try {
    const reservation = await ReservationRepository.findById(req.params.id);
    if (!reservation) return res.status(404).json({ error: 'Reservation not found' });
    res.json(reservation);
  } catch (err) {
    fail(res, err);
  }
};

/** GET /api/reservations/available-tables?date&time&guestCount[&excludeId] */
exports.availableTables = async (req, res) => {
  try {
    const time = normalizeTime(req.query.time);
    if (!isValidDate(req.query.date) || !time) return res.status(400).json({ error: 'Choose a valid date and time' });
    const guestCount = Math.min(GUESTS_MAX, Math.max(1, parseInt(req.query.guestCount, 10) || 1));
    const excludeId = parseInt(req.query.excludeId, 10) || null;
    res.json(await ReservationRepository.findAvailableTables(req.query.date, time, guestCount, excludeId));
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const booking = normalizeBooking(req.body);
    const reservation = await ReservationRepository.create({ ...booking, createdBy: req.user.employeeId });

    await logAction(
      req.user.employeeId,
      `Created reservation for ${booking.customerName} (table ${reservation.table_number}, ${booking.guestCount} guests, ${booking.date} ${time12(booking.time)})`,
      'reservations'
    );
    await tellStaff(
      'New reservation',
      `${booking.customerName}, ${booking.guestCount} guests, table ${reservation.table_number}, ${booking.date} at ${time12(booking.time)}.`,
      'new_reservation'
    );

    res.status(201).json(reservation);
  } catch (err) {
    fail(res, err);
  }
};

exports.update = async (req, res) => {
  try {
    const booking = normalizeBooking(req.body);
    const reservation = await ReservationRepository.update(req.params.id, booking);

    await logAction(
      req.user.employeeId,
      `Updated reservation #${req.params.id} for ${booking.customerName} (table ${reservation.table_number}, ${booking.date} ${time12(booking.time)})`,
      'reservations'
    );
    res.json(reservation);
  } catch (err) {
    fail(res, err);
  }
};

exports.setStatus = async (req, res) => {
  try {
    const { status } = req.body;
    if (!STATUSES.includes(status)) {
      return res.status(400).json({ error: `status must be one of: ${STATUSES.join(', ')}` });
    }

    const { previous, reservation } = await ReservationRepository.setStatus(req.params.id, status);
    const label = (s) => s.replace('_', ' ');

    await logAction(
      req.user.employeeId,
      `Reservation #${req.params.id} (${reservation.customer_name}): ${label(previous)} to ${label(status)}`,
      'reservations'
    );
    if (status === 'cancelled' || status === 'no_show') {
      await tellStaff(
        status === 'cancelled' ? 'Reservation cancelled' : 'Reservation marked no-show',
        `${reservation.customer_name}, table ${reservation.table_number}, ${reservation.reservation_date} at ${time12(reservation.reservation_time)}.`,
        'reservation_status'
      );
    }

    res.json(reservation);
  } catch (err) {
    fail(res, err);
  }
};