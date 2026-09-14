const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const SessionManager = require('../patterns/singletons/SessionManager');
const { logAction, registerFailedLogin, clearFailedLogins } = require('../middleware/activityLogger');

function signToken(employee) {
  return jwt.sign(
    { employeeId: employee.employee_id, username: employee.username, role: employee.role_name },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
  );
}

exports.login = async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password are required' });
    }

    const employee = await EmployeeRepository.findByUsername(username);
    if (!employee) {
      registerFailedLogin(username);
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (employee.status !== 'active') {
      return res.status(403).json({ error: 'This account has been deactivated. Contact the administrator.' });
    }

    const valid = await bcrypt.compare(password, employee.password);
    if (!valid) {
      registerFailedLogin(username);
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    clearFailedLogins(username);
    const token = signToken(employee);
    await logAction(employee.employee_id, 'Logged in', 'auth');

    res.json({
      token,
      user: {
        employeeId: employee.employee_id,
        name: employee.name,
        username: employee.username,
        email: employee.email,
        role: employee.role_name,
        profileImage: employee.profile_image,
      },
    });
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

// NOTE: "Forgot password" here issues a short-lived reset token that would
// normally be emailed to the user. Wire up an email provider (e.g. SendGrid)
// in production; for now the token is returned directly for the admin flow.
exports.forgotPassword = async (req, res) => {
  try {
    const { username } = req.body;
    const employee = await EmployeeRepository.findByUsername(username);
    if (!employee) return res.status(404).json({ error: 'No account with that username' });

    const resetToken = jwt.sign({ employeeId: employee.employee_id, purpose: 'reset' }, process.env.JWT_SECRET, { expiresIn: '15m' });
    res.json({ message: 'Password reset token generated', resetToken });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.resetPassword = async (req, res) => {
  try {
    const { resetToken, newPassword } = req.body;
    const decoded = jwt.verify(resetToken, process.env.JWT_SECRET);
    if (decoded.purpose !== 'reset') throw new Error('Invalid token');

    const hash = await bcrypt.hash(newPassword, 10);
    await EmployeeRepository.updatePassword(decoded.employeeId, hash);
    res.json({ message: 'Password has been reset. You can now log in.' });
  } catch (err) {
    res.status(400).json({ error: 'Invalid or expired reset token' });
  }
};