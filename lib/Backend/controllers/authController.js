const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const PasswordResetRepository = require('../repositories/PasswordResetRepository');
const SessionManager = require('../patterns/singletons/SessionManager');
const mailer = require('../services/mailer');
const { logAction } = require('../middleware/activityLogger');

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

    const valid = await bcrypt.compare(password, employee.password);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

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
    await logAction(employee.employee_id, 'Changed password', 'auth');
    res.json({ message: 'Password updated successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ---------------------------------------------------------------------------
// Forgot password: a 3-step, email-verified reset.
//   1. requestPasswordReset  — emails a 6-digit code to the typed-in address,
//                              as long as it's an address on file
//   2. verifyPasswordReset   — checks the code, issues a short-lived reset ticket
//   3. resetPasswordWithCode — sets the new password using that ticket
// The code is always sent to the account's own email on file — the one the
// person typed is only ever used to look that account up, never as a
// delivery address someone else could substitute — so this can't be used to
// redirect a reset somewhere an attacker controls.
// ---------------------------------------------------------------------------

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// In lib/Backend/controllers/authController.js, REPLACE the whole existing
// `exports.requestPasswordReset = ...` function with this one. Nothing else
// in that file changes.

exports.requestPasswordReset = async (req, res) => {
  try {
    const { email } = req.body;
    if (!email || !EMAIL_RE.test(email)) return res.status(400).json({ error: 'Enter a valid email address' });

    const employee = await EmployeeRepository.findByEmail(email);
    if (!employee) return res.status(404).json({ error: 'No account with that email address' });

    const waitSeconds = await PasswordResetRepository.secondsUntilNextRequestAllowed(employee.employee_id);
    if (waitSeconds > 0) {
      // A code from the earlier request is still active and usable. This only
      // blocks sending ANOTHER one too soon; the frontend uses maskedEmail to
      // still move the person on to entering that code.
      return res.status(429).json({
        error: `Please wait ${waitSeconds}s before requesting another code.`,
        retryAfterSeconds: waitSeconds,
        maskedEmail: mailer.maskEmail(employee.email),
      });
    }

    const code = await PasswordResetRepository.createCode(employee.employee_id);

    try {
      const result = await mailer.sendResetCode({ to: employee.email, name: employee.name, code });
      // Not configured: fine for local development (code is printed to the
      // console), but in production it means nobody would ever get the email.
      if (!result.delivered && process.env.NODE_ENV === 'production') {
        throw new Error('No email provider is configured (set BREVO_API_KEY and BREVO_SENDER_EMAIL)');
      }
    } catch (mailErr) {
      console.error('[forgot-password] could not send email:', mailErr.message);
      // Remove the unsendable code so the 60s cooldown doesn't block a retry.
      await PasswordResetRepository.discardActive(employee.employee_id);
      return res.status(502).json({ error: "We couldn't send the email right now. Please try again in a moment." });
    }

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
    const { email, code } = req.body;
    if (!email || !code) return res.status(400).json({ error: 'Email and code are required' });

    const employee = await EmployeeRepository.findByEmail(email);
    if (!employee) return res.status(404).json({ error: 'No account with that email address' });

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