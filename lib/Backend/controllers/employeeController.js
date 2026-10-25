const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const EmailVerificationRepository = require('../repositories/EmailVerificationRepository');
const RoleFactory = require('../patterns/factories/RoleFactory');
const mailer = require('../services/mailer');
const { logAction } = require('../middleware/activityLogger');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD_LENGTH = 6;
const normalizeEmail = (email) => String(email || '').trim().toLowerCase();

exports.list = async (req, res) => {
  try {
    const { role, status } = req.query;
    const employees = await EmployeeRepository.findAll({ role, status });
    res.json(employees);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getOne = async (req, res) => {
  const employee = await EmployeeRepository.findById(req.params.id);
  if (!employee) return res.status(404).json({ error: 'Employee not found' });
  const { password, ...safe } = employee;
  res.json(safe);
};

// ---------------------------------------------------------------------------
// Email verification for a NEW employee account.
//   1. requestEmailCode — emails a 6-digit code to the address being added
//   2. verifyEmailCode  — checks the code, returns a short-lived token that
//                         is tied to that exact email
//   3. create           — refuses to make the account without that token
// Checking only in the app would be skippable by calling the API directly,
// so the server enforces it in `create`.
// ---------------------------------------------------------------------------

exports.requestEmailCode = async (req, res) => {
  try {
    const email = String(req.body.email || '').trim();
    if (!EMAIL_RE.test(email)) return res.status(400).json({ error: 'Enter a valid email address' });

    const existing = await EmployeeRepository.findByEmail(email);
    if (existing) return res.status(409).json({ error: 'An account with that email address already exists' });

    const waitSeconds = await EmailVerificationRepository.secondsUntilNextRequestAllowed(email);
    if (waitSeconds > 0) {
      // The earlier code is still usable; this only blocks sending ANOTHER too soon.
      return res.status(429).json({
        error: `Please wait ${waitSeconds}s before requesting another code.`,
        retryAfterSeconds: waitSeconds,
        maskedEmail: mailer.maskEmail(email),
      });
    }

    const code = await EmailVerificationRepository.createCode(email);

    try {
      const result = await mailer.sendVerificationCode({ to: email, code });
      if (!result.delivered && process.env.NODE_ENV === 'production') {
        throw new Error('No email provider is configured (set BREVO_API_KEY and BREVO_SENDER_EMAIL)');
      }
    } catch (mailErr) {
      console.error('[employee-email-code] could not send email:', mailErr.message);
      await EmailVerificationRepository.discardActive(email);
      return res.status(502).json({ error: "We couldn't send the email right now. Please try again in a moment." });
    }

    await logAction(req.user.employeeId, `Sent an email verification code to ${mailer.maskEmail(email)}`, 'employees');
    res.json({ message: 'A verification code was sent.', maskedEmail: mailer.maskEmail(email) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.verifyEmailCode = async (req, res) => {
  try {
    const { email, code } = req.body;
    if (!email || !code) return res.status(400).json({ error: 'Email and code are required' });

    const result = await EmailVerificationRepository.verifyCode(email, code);
    switch (result) {
      case 'ok': {
        const emailToken = jwt.sign({ email: normalizeEmail(email), purpose: 'employee-email' }, process.env.JWT_SECRET, {
          expiresIn: '30m',
        });
        return res.json({ emailToken });
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

exports.create = async (req, res) => {
  try {
    const { name, username, email, emailToken, password, role, profileImage } = req.body;
    if (!name || !username || !password) {
      return res.status(400).json({ error: 'Name, username, and password are required' });
    }
    if (password.length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters` });
    }
    if (!RoleFactory.validRoles().includes(role)) {
      return res.status(400).json({ error: `Role must be one of: ${RoleFactory.validRoles().join(', ')}` });
    }

    // The email must have been verified, and the token must be for THIS email.
    let decoded;
    try {
      decoded = jwt.verify(String(emailToken || ''), process.env.JWT_SECRET);
    } catch (_) {
      return res.status(403).json({ error: 'Email verification is missing or expired. Verify the email again.' });
    }
    if (decoded.purpose !== 'employee-email' || decoded.email !== normalizeEmail(email)) {
      return res.status(403).json({ error: 'The verified email does not match. Verify the email again.' });
    }

    const existing = await EmployeeRepository.findByUsername(username);
    if (existing) return res.status(409).json({ error: 'Username already taken' });
    const emailTaken = await EmployeeRepository.findByEmail(email);
    if (emailTaken) return res.status(409).json({ error: 'An account with that email address already exists' });

    const passwordHash = await bcrypt.hash(password, 10);
    const roleObject = RoleFactory.create(role, { name, username, email, passwordHash });

    const roleRecord = await EmployeeRepository.getRoleByName(role);
    const created = await EmployeeRepository.create({
      name: roleObject.name,
      username: roleObject.username,
      email: roleObject.email,
      passwordHash: roleObject.password,
      roleId: roleRecord.role_id,
      profileImage: profileImage || null,
    });

    await logAction(req.user.employeeId, `Created employee ${username} (${role})`, 'employees');
    const { password: _pw, ...safe } = created;
    res.status(201).json(safe);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  try {
    const { name, email } = req.body;
    const updated = await EmployeeRepository.update(req.params.id, { name, email });
    await logAction(req.user.employeeId, `Updated employee #${req.params.id}`, 'employees');
    const { password, ...safe } = updated;
    res.json(safe);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.setStatus = async (req, res) => {
  try {
    const { status } = req.body; // 'active' | 'inactive'
    if (!['active', 'inactive'].includes(status)) {
      return res.status(400).json({ error: "status must be 'active' or 'inactive'" });
    }
    const updated = await EmployeeRepository.setStatus(req.params.id, status);
    await logAction(req.user.employeeId, `Set employee #${req.params.id} to ${status}`, 'employees');
    const { password, ...safe } = updated;
    res.json(safe);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.assignRole = async (req, res) => {
  try {
    const { role } = req.body;
    const roleRecord = await EmployeeRepository.getRoleByName(role);
    if (!roleRecord) return res.status(400).json({ error: 'Invalid role' });
    const updated = await EmployeeRepository.update(req.params.id, { role_id: roleRecord.role_id });
    await logAction(req.user.employeeId, `Reassigned employee #${req.params.id} to ${role}`, 'employees');
    const { password, ...safe } = updated;
    res.json(safe);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.resetPassword = async (req, res) => {
  try {
    const { newPassword } = req.body;
    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }
    const hash = await bcrypt.hash(newPassword, 10);
    await EmployeeRepository.updatePassword(req.params.id, hash);
    await logAction(req.user.employeeId, `Reset password for employee #${req.params.id}`, 'employees');
    res.json({ message: 'Password reset successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};