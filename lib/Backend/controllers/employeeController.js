const bcrypt = require('bcrypt');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const RoleFactory = require('../patterns/factories/RoleFactory');
const { logAction } = require('../middleware/activityLogger');

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

// REPLACE the existing `exports.create` in controllers/employeeController.js
// with this version (adds optional profileImage support).

exports.create = async (req, res) => {
  try {
    const { name, username, email, password, role, profileImage } = req.body;
    if (!RoleFactory.validRoles().includes(role)) {
      return res.status(400).json({ error: `Role must be one of: ${RoleFactory.validRoles().join(', ')}` });
    }

    const existing = await EmployeeRepository.findByUsername(username);
    if (existing) return res.status(409).json({ error: 'Username already taken' });

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
    const bcrypt = require('bcrypt');
    const hash = await bcrypt.hash(newPassword, 10);
    await EmployeeRepository.updatePassword(req.params.id, hash);
    await logAction(req.user.employeeId, `Reset password for employee #${req.params.id}`, 'employees');
    res.json({ message: 'Password reset successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};