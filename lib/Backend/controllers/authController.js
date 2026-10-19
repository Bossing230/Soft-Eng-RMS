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