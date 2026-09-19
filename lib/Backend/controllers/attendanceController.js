const db = require('../patterns/singletons/DatabaseManager');
const { logAction } = require('../middleware/activityLogger');

// A shift that was never clocked out is treated as stale after this many hours,
// so a forgotten clock-out can't make someone look "on duty" forever.
const SHIFT_MAX_HOURS = 16;
exports.SHIFT_MAX_HOURS = SHIFT_MAX_HOURS;

async function openShift(employeeId) {
  const rows = await db.query(
    `SELECT attendance_id, break_started_at
       FROM attendance
      WHERE employee_id = ?
        AND clock_out IS NULL
        AND clock_in >= DATE_SUB(NOW(), INTERVAL ${SHIFT_MAX_HOURS} HOUR)
      ORDER BY attendance_id DESC
      LIMIT 1`,
    [employeeId]
  );
  return rows[0] || null;
}

function statusOf(shift) {
  if (!shift) return 'off';
  return shift.break_started_at ? 'on_break' : 'on_duty';
}

exports.me = async (req, res) => {
  try {
    const shift = await openShift(req.user.employeeId);
    res.json({ status: statusOf(shift) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.clockIn = async (req, res) => {
  try {
    const { employeeId } = req.user;
    if (await openShift(employeeId)) {
      return res.status(409).json({ error: 'You are already clocked in' });
    }
    // Close any stale, never-clocked-out shifts before starting a new one.
    await db.query(
      `UPDATE attendance
          SET clock_out = DATE_ADD(clock_in, INTERVAL ${SHIFT_MAX_HOURS} HOUR), break_started_at = NULL
        WHERE employee_id = ? AND clock_out IS NULL`,
      [employeeId]
    );
    await db.query('INSERT INTO attendance (employee_id) VALUES (?)', [employeeId]);
    await logAction(employeeId, 'Clocked in', 'attendance');
    res.json({ status: 'on_duty' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.clockOut = async (req, res) => {
  try {
    const { employeeId } = req.user;
    const shift = await openShift(employeeId);
    if (!shift) return res.status(409).json({ error: 'You are not clocked in' });
    await db.query(
      'UPDATE attendance SET clock_out = NOW(), break_started_at = NULL WHERE attendance_id = ?',
      [shift.attendance_id]
    );
    await logAction(employeeId, 'Clocked out', 'attendance');
    res.json({ status: 'off' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.startBreak = async (req, res) => {
  try {
    const { employeeId } = req.user;
    const shift = await openShift(employeeId);
    if (!shift) return res.status(409).json({ error: 'Clock in before starting a break' });
    if (shift.break_started_at) return res.status(409).json({ error: 'You are already on break' });
    await db.query('UPDATE attendance SET break_started_at = NOW() WHERE attendance_id = ?', [shift.attendance_id]);
    await logAction(employeeId, 'Started break', 'attendance');
    res.json({ status: 'on_break' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.endBreak = async (req, res) => {
  try {
    const { employeeId } = req.user;
    const shift = await openShift(employeeId);
    if (!shift || !shift.break_started_at) return res.status(409).json({ error: 'You are not on break' });
    await db.query('UPDATE attendance SET break_started_at = NULL WHERE attendance_id = ?', [shift.attendance_id]);
    await logAction(employeeId, 'Ended break', 'attendance');
    res.json({ status: 'on_duty' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};