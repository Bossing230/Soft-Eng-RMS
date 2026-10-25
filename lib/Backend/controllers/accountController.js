const db = require('../patterns/singletons/DatabaseManager');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const ensureAccountColumns = require('../database/ensure-account-columns');
const { logAction } = require('../middleware/activityLogger');

// Same setting the reports use: hours to add to stored timestamps so the last
// login shows restaurant-local time (8 on a UTC database in the Philippines).
const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;

const NAME_MIN = 2;
const NAME_MAX = 100;
const ADDRESS_MAX = 255;
const PHONE_RE = /^[0-9+\-\s()]{7,20}$/;

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

// Make sure employees.phone / employees.address exist, once per server run.
let schemaReady = null;
function ready() {
  if (!schemaReady) {
    schemaReady = ensureAccountColumns().catch((err) => {
      schemaReady = null; // try again on the next request
      throw err;
    });
  }
  return schemaReady;
}

/** The signed-in person's own profile, with only the fields the page needs (never the password). */
async function buildProfile(employeeId) {
  await ready();
  const employee = await EmployeeRepository.findById(employeeId);
  if (!employee) return null;

  const rows = await db.query(
    `SELECT DATE_FORMAT(DATE_ADD(\`timestamp\`, INTERVAL ${TZ_OFFSET_HOURS} HOUR), '%Y-%m-%d %H:%i:%s') AS last_login
       FROM activity_logs
      WHERE employee_id = ? AND module = 'auth' AND action LIKE 'Logged in%'
      ORDER BY \`timestamp\` DESC, log_id DESC
      LIMIT 1`,
    [employeeId]
  );

  return {
    employee_id: employee.employee_id,
    name: employee.name,
    username: employee.username,
    email: employee.email,
    role: employee.role_name,
    phone: employee.phone || '',
    address: employee.address || '',
    profile_image: employee.profile_image || null,
    last_login: rows[0] ? rows[0].last_login : null,
  };
}

/** GET /api/account/profile */
exports.getProfile = async (req, res) => {
  try {
    const profile = await buildProfile(req.user.employeeId);
    if (!profile) return res.status(404).json({ error: 'Account not found' });
    res.json(profile);
  } catch (err) {
    fail(res, err);
  }
};

/**
 * PUT /api/account/profile   body: { name, phone, address }
 * Only these three fields can change, and only on the signed-in person's own
 * account. Email, role and username are never taken from the request.
 */
exports.updateProfile = async (req, res) => {
  try {
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    const phone = typeof req.body.phone === 'string' ? req.body.phone.trim() : '';
    const address = typeof req.body.address === 'string' ? req.body.address.trim() : '';

    if (name.length < NAME_MIN || name.length > NAME_MAX) {
      return res.status(400).json({ error: `Name must be ${NAME_MIN} to ${NAME_MAX} characters` });
    }
    if (phone && !PHONE_RE.test(phone)) {
      return res.status(400).json({ error: 'Phone number can only contain digits, spaces, + - ( ) and be 7 to 20 characters' });
    }
    if (address.length > ADDRESS_MAX) {
      return res.status(400).json({ error: `Address must be ${ADDRESS_MAX} characters or fewer` });
    }

    await ready();
    await EmployeeRepository.update(req.user.employeeId, {
      name,
      phone: phone || null,
      address: address || null,
    });
    await logAction(req.user.employeeId, 'Updated profile details', 'account');

    res.json(await buildProfile(req.user.employeeId));
  } catch (err) {
    fail(res, err);
  }
};

/** POST /api/account/photo   multipart field "image" (see the route for the upload limits) */
exports.uploadPhoto = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No photo was uploaded' });

    // With Cloudinary storage, req.file.path is already the full, permanent https URL.
    const url = req.file.path;
    await EmployeeRepository.update(req.user.employeeId, { profile_image: url });
    await logAction(req.user.employeeId, 'Changed profile photo', 'account');

    res.status(201).json({ profile_image: url });
  } catch (err) {
    fail(res, err);
  }
};