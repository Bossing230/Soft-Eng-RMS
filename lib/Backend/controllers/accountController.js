const db = require('../patterns/singletons/DatabaseManager');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const ensureAccountColumns = require('../database/ensure-account-columns');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const cloudinary = require('cloudinary').v2;
const SessionManager = require('../patterns/singletons/SessionManager');
const notifyRoles = require('../patterns/observers/notifyRoles');
const Presence = require('../services/presence');
const AccountGuard = require('../services/accountGuard');
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

// ---------------------------------------------------------------------------
// Delete my account
//
// The employee row is kept (orders, payments, reservations and the activity log
// all point at it, and deleting it would either fail or erase the restaurant's
// records). Instead the account is closed for good:
//   - name, email, phone, address and photo are removed
//   - the username is freed and the password is replaced by an unusable one
//   - the account is marked inactive and deleted, so nobody can sign in with it
//     and every token already issued stops working
// Past orders and logs then show "Deleted account #id" instead of the name.
// ---------------------------------------------------------------------------

const MAX_WRONG_PASSWORDS = 5;
const BLOCK_MS = 5 * 60 * 1000;
const wrongPasswords = new Map(); // employeeId -> { count, blockedUntil }

/** The Cloudinary id of an uploaded photo, from its URL, or null for anything else. */
function cloudinaryPublicId(url) {
  if (typeof url !== 'string' || !url.includes('res.cloudinary.com')) return null;
  const match = /\/upload\/(?:v\d+\/)?(.+)\.[a-z0-9]+$/i.exec(url);
  return match ? match[1] : null;
}

/**
 * POST /api/account/delete   body: { password, confirm: "DELETE" }
 * Only ever closes the signed-in person's own account.
 */
exports.deleteAccount = async (req, res) => {
  try {
    const employeeId = req.user.employeeId;

    const record = wrongPasswords.get(employeeId);
    if (record && record.blockedUntil > Date.now()) {
      const minutes = Math.ceil((record.blockedUntil - Date.now()) / 60000);
      return res.status(429).json({ error: `Too many wrong passwords. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.` });
    }

    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (req.body.confirm !== 'DELETE') return res.status(400).json({ error: 'Type DELETE to confirm' });
    if (!password) return res.status(400).json({ error: 'Enter your password' });

    await ready();
    const employee = await EmployeeRepository.findById(employeeId);
    if (!employee || employee.deleted_at) return res.status(404).json({ error: 'Account not found' });

    if (!(await bcrypt.compare(password, employee.password))) {
      const next = { count: (record ? record.count : 0) + 1, blockedUntil: 0 };
      if (next.count >= MAX_WRONG_PASSWORDS) {
        next.blockedUntil = Date.now() + BLOCK_MS;
        next.count = 0;
      }
      wrongPasswords.set(employeeId, next);
      return res.status(401).json({ error: 'Your password is incorrect' });
    }
    wrongPasswords.delete(employeeId);

    const unusablePassword = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 10);

    const conn = await db.getPool().getConnection();
    try {
      await conn.beginTransaction();

      // Lock every active administrator, so two administrators deleting at the
      // same moment cannot both pass the "someone else is left" check.
      const [admins] = await conn.execute(
        `SELECT e.employee_id
           FROM employees e JOIN roles r ON r.role_id = e.role_id
          WHERE r.role_name = 'administrator' AND e.status = 'active' AND e.deleted_at IS NULL
          FOR UPDATE`
      );
      if (employee.role_name === 'administrator' && admins.length <= 1) {
        const err = new Error('You are the only administrator. Make another account an administrator before deleting this one.');
        err.status = 409;
        throw err;
      }

      await conn.execute(
        `UPDATE employees
            SET name = CONCAT('Deleted account #', employee_id),
                username = CONCAT('deleted_', employee_id),
                email = CONCAT('deleted_', employee_id, '@deleted.invalid'),
                password = ?,
                phone = NULL, address = NULL, profile_image = NULL,
                status = 'inactive', deleted_at = NOW(),
                failed_login_attempts = 0, locked_until = NULL
          WHERE employee_id = ?`,
        [unusablePassword, employeeId]
      );

      // Close a shift that was left open (the attendance table may not exist yet).
      try {
        await conn.execute(
          'UPDATE attendance SET clock_out = NOW(), break_started_at = NULL WHERE employee_id = ? AND clock_out IS NULL',
          [employeeId]
        );
      } catch (err) {
        if (err.errno !== 1146) throw err;
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    // Lock the account out right away, on every device.
    AccountGuard.markInactive(employeeId);
    SessionManager.invalidateToken(req.token);
    try {
      await Presence.clear(employeeId);
    } catch (err) {
      console.error('Could not clear last seen:', err.message);
    }

    await logAction(employeeId, `Deleted own account (${employee.role_name})`, 'account');
    try {
      await notifyRoles(['administrator'], {
        title: 'An account was deleted',
        message: `${employee.name} (${employee.role_name}) deleted their account.`,
        type: 'account_deleted',
      });
    } catch (err) {
      console.error('Account-deleted notification failed:', err.message);
    }

    // Best effort: remove the photo from Cloudinary as well.
    const publicId = cloudinaryPublicId(employee.profile_image);
    if (publicId) {
      cloudinary.uploader.destroy(publicId).catch((err) => console.error('Could not delete the photo:', err.message));
    }

    res.json({ message: 'Your account has been deleted.' });
  } catch (err) {
    fail(res, err);
  }
};