const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const PasswordResetRepository = require('../repositories/PasswordResetRepository');
const SessionManager = require('../patterns/singletons/SessionManager');
const mailer = require('../services/mailer');
const { logAction } = require('../middleware/activityLogger');

const MAX_ATTEMPTS_BEFORE_LOCK = 3;
// 1st lockout: 5 min. 2nd: 10 min (double). 3rd and every one after: 12 hours.
// Only a real password change brings this back down to 5 min — see
// EmployeeRepository.clearLockoutEscalation and its callers below.
const LOCKOUT_MINUTES_BY_LEVEL = { 1: 5, 2: 10 };
const LOCKOUT_MINUTES_CAP = 12 * 60;
function lockoutMinutesForLevel(level) {
  return LOCKOUT_MINUTES_BY_LEVEL[level] ?? LOCKOUT_MINUTES_CAP;
}

const MIN_PASSWORD_LENGTH = 6;

function signToken(employee) {
  return jwt.sign(
    { employeeId: employee.employee_id, username: employee.username, role: employee.role_name },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
  );
}

function loginResponse(employee, token) {
  return {
    token,
    user: {
      employeeId: employee.employee_id,
      name: employee.name,
      username: employee.username,
      email: employee.email,
      role: employee.role_name,
      profileImage: employee.profile_image,
    },
  };
}

/** The DB client returns DATETIME columns as 'YYYY-MM-DD HH:MM:SS' strings (dateStrings: true). */
function parseDbDate(value) {
  return value ? new Date(String(value).replace(' ', 'T')) : null;
}

function isLocked(employee) {
  const until = parseDbDate(employee.locked_until);
  return !!until && until > new Date();
}

function confirmationNumber() {
  const stamp = Date.now().toString(36).toUpperCase();
  const tail = Math.floor(1000 + Math.random() * 9000);
  return `RST-${stamp}-${tail}`;
}

exports.login = async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password are required' });
    }

    const employee = await EmployeeRepository.findByUsername(username);
    if (!employee) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (employee.status !== 'active') {
      return res.status(403).json({ error: 'This account has been deactivated. Contact the administrator.' });
    }

    if (isLocked(employee)) {
      return res.status(423).json({
        error: 'This account is temporarily locked after too many failed attempts.',
        lockedUntil: parseDbDate(employee.locked_until).toISOString(),
        lockoutMinutes: lockoutMinutesForLevel(employee.lockout_level),
        justLocked: false,
      });
    }

    const valid = await bcrypt.compare(password, employee.password);
    if (!valid) {
      const attempts = await EmployeeRepository.incrementFailedAttempts(employee.employee_id);

      if (attempts >= MAX_ATTEMPTS_BEFORE_LOCK) {
        const nextLevel = (employee.lockout_level || 0) + 1;
        const minutes = lockoutMinutesForLevel(nextLevel);
        const lockedUntil = new Date(Date.now() + minutes * 60000);
        await EmployeeRepository.lockAccount(employee.employee_id, { lockedUntil, lockoutLevel: nextLevel });
        await logAction(employee.employee_id, `Account locked for ${minutes} minute(s) after ${attempts} failed attempts`, 'auth');

        return res.status(423).json({
          error: 'Too many failed attempts. This account is now temporarily locked.',
          lockedUntil: lockedUntil.toISOString(),
          lockoutMinutes: minutes,
          justLocked: true,
        });
      }

      return res.status(401).json({
        error: 'Invalid credentials',
        attemptsRemaining: MAX_ATTEMPTS_BEFORE_LOCK - attempts,
      });
    }

    await EmployeeRepository.clearFailedAttempts(employee.employee_id);
    const token = signToken(employee);
    await logAction(employee.employee_id, 'Logged in', 'auth');

    res.json(loginResponse(employee, token));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.logout = async (req, res) => {
  SessionManager.invalidateToken(req.token);
  await logAction(req.user.employeeId, 'Logged out', 'auth');
  res.json({ message: 'Logged out successfully' });
};

exports.me = async (req, res) => {
  const employee = await EmployeeRepository.findById(req.user.employeeId);
  if (!employee) return res.status(404).json({ error: 'Employee not found' });
  const { password, ...safe } = employee;
  res.json(safe);
};

exports.changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!newPassword || newPassword.length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `New password must be at least ${MIN_PASSWORD_LENGTH} characters` });
    }
    const employee = await EmployeeRepository.findById(req.user.employeeId);
    const valid = await bcrypt.compare(currentPassword, employee.password);
    if (!valid) return res.status(401).json({ error: 'Current password is incorrect' });

    const hash = await bcrypt.hash(newPassword, 10);
    await EmployeeRepository.updatePassword(employee.employee_id, hash);
    // A real password change is what's allowed to bring the lockout escalation back down.
    await EmployeeRepository.clearLockoutEscalation(employee.employee_id);
    await logAction(employee.employee_id, 'Changed password', 'auth');
    res.json({ message: 'Password updated successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ---------------------------------------------------------------------------
// Forgot password: a 3-step, email-verified reset.
//   1. requestPasswordReset  — emails a 6-digit code to the address on file
//   2. verifyPasswordReset   — checks the code, issues a short-lived reset ticket
//   3. resetPasswordWithCode — sets the new password using that ticket
// The email address is never taken from the request — only ever the one
// already on the account — so this can't be used to redirect a reset
// somewhere an attacker controls.
// ---------------------------------------------------------------------------

exports.requestPasswordReset = async (req, res) => {
  try {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'Username is required' });

    const employee = await EmployeeRepository.findByUsername(username);
    if (!employee) return res.status(404).json({ error: 'No account with that username' });
    if (!employee.email) {
      return res.status(400).json({ error: 'This account has no email on file. Contact your administrator.' });
    }

    const waitSeconds = await PasswordResetRepository.secondsUntilNextRequestAllowed(employee.employee_id);
    if (waitSeconds > 0) {
      return res.status(429).json({
        error: `Please wait ${waitSeconds}s before requesting another code.`,
        retryAfterSeconds: waitSeconds,
      });
    }

    const code = await PasswordResetRepository.createCode(employee.employee_id);
    await mailer.sendResetCode({ to: employee.email, name: employee.name, code });
    await logAction(employee.employee_id, 'Requested a password reset code', 'auth');

    res.json({
      message: 'A verification code was sent to your email.',
      maskedEmail: mailer.maskEmail(employee.email),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.verifyPasswordReset = async (req, res) => {
  try {
    const { username, code } = req.body;
    if (!username || !code) return res.status(400).json({ error: 'Username and code are required' });

    const employee = await EmployeeRepository.findByUsername(username);
    if (!employee) return res.status(404).json({ error: 'No account with that username' });

    const result = await PasswordResetRepository.verifyCode(employee.employee_id, code);
    switch (result) {
      case 'ok': {
        const resetToken = jwt.sign({ employeeId: employee.employee_id, purpose: 'reset' }, process.env.JWT_SECRET, {
          expiresIn: '15m',
        });
        return res.json({ resetToken });
      }
      case 'wrong':
        return res.status(401).json({ error: 'That code is incorrect. Please try again.' });
      case 'too_many_attempts':
        return res.status(429).json({ error: 'Too many incorrect tries. Request a new code.' });
      case 'expired':
      default:
        return res.status(410).json({ error: 'This code has expired. Request a new one.' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.resetPasswordWithCode = async (req, res) => {
  try {
    const { resetToken, newPassword } = req.body;
    if (!newPassword || newPassword.length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `New password must be at least ${MIN_PASSWORD_LENGTH} characters` });
    }

    let decoded;
    try {
      decoded = jwt.verify(resetToken, process.env.JWT_SECRET);
    } catch (_) {
      return res.status(400).json({ error: 'Invalid or expired reset session. Please request a new code.' });
    }
    if (decoded.purpose !== 'reset') {
      return res.status(400).json({ error: 'Invalid or expired reset session. Please request a new code.' });
    }

    const hash = await bcrypt.hash(newPassword, 10);
    await EmployeeRepository.updatePassword(decoded.employeeId, hash);
    await EmployeeRepository.clearLockoutEscalation(decoded.employeeId);
    await logAction(decoded.employeeId, 'Reset password via emailed code', 'auth');

    const employee = await EmployeeRepository.findById(decoded.employeeId);
    const token = signToken(employee);

    res.json({
      message: 'Password has been reset.',
      confirmationNumber: confirmationNumber(),
      ...loginResponse(employee, token),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};