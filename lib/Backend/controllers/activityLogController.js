const ActivityLogRepository = require('../repositories/ActivityLogRepository');

// Administrators and managers see everyone's activity. Everyone else sees only
// their own. This is decided here on the server, never by the app.
const SEE_ALL_ROLES = ['administrator', 'manager'];
const ROLES = ['administrator', 'manager', 'cashier', 'kitchen'];

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_RANGE_DAYS = 366;
const DEFAULT_RANGE_DAYS = 7;
const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 50;

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

/** True for a real calendar date written as YYYY-MM-DD. */
function isValidDate(value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

function shiftDays(date, days) {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * GET /api/activity-logs
 *   ?from=YYYY-MM-DD&to=YYYY-MM-DD   (default: the last 7 days, today included)
 *   &type=login|logout|password|orders|...   &role=manager|...   &search=text
 *   &page=1&limit=10
 * `role` is ignored for people who can only see their own activity.
 */
exports.list = async (req, res) => {
  try {
    const seesAll = SEE_ALL_ROLES.includes(req.user.role);

    const today = await ActivityLogRepository.todayLocal();
    const to = isValidDate(req.query.to) ? req.query.to : today;
    const from = isValidDate(req.query.from) ? req.query.from : shiftDays(to, -(DEFAULT_RANGE_DAYS - 1));
    if (from > to) return res.status(400).json({ error: 'The start date must not be after the end date' });
    if (shiftDays(from, MAX_RANGE_DAYS) < to) {
      return res.status(400).json({ error: 'Choose a range of one year or less' });
    }

    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(MAX_LIMIT, Math.max(1, parseInt(req.query.limit, 10) || DEFAULT_LIMIT));
    const type = typeof req.query.type === 'string' && /^[a-z_]{1,50}$/.test(req.query.type) ? req.query.type : null;
    const role = seesAll && ROLES.includes(req.query.role) ? req.query.role : null;
    const search = typeof req.query.search === 'string' ? req.query.search.trim().slice(0, 100) : '';

    const { logs, total } = await ActivityLogRepository.findPage({
      from,
      to,
      type,
      role,
      search,
      employeeId: seesAll ? null : req.user.employeeId,
      page,
      limit,
    });

    res.json({ logs, total, page, limit, from, to, canSeeAll: seesAll });
  } catch (err) {
    fail(res, err);
  }
};

/** The activity kinds that exist, for the dropdown. */
exports.kinds = async (req, res) => {
  try {
    const seesAll = SEE_ALL_ROLES.includes(req.user.role);
    res.json(await ActivityLogRepository.kinds({ employeeId: seesAll ? null : req.user.employeeId }));
  } catch (err) {
    fail(res, err);
  }
};