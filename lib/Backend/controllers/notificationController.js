const NotificationRepository = require('../repositories/NotificationRepository');
const EmployeeRepository = require('../repositories/EmployeeRepository');

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

exports.list = async (req, res) => {
  try {
    const employee = await EmployeeRepository.findById(req.user.employeeId);
    if (!employee) return res.status(404).json({ error: 'Employee not found' });
    const notifications = await NotificationRepository.findForEmployee(req.user.employeeId, employee.role_id, {
      unreadOnly: req.query.unreadOnly === 'true',
    });
    res.json(notifications);
  } catch (err) {
    fail(res, err);
  }
};

exports.markRead = async (req, res) => {
  try {
    await NotificationRepository.markRead(req.params.id);
    res.json({ message: 'Marked as read' });
  } catch (err) {
    fail(res, err);
  }
};

exports.markAllRead = async (req, res) => {
  try {
    const employee = await EmployeeRepository.findById(req.user.employeeId);
    if (!employee) return res.status(404).json({ error: 'Employee not found' });
    await NotificationRepository.markAllRead(req.user.employeeId, employee.role_id);
    res.json({ message: 'All notifications marked as read' });
  } catch (err) {
    fail(res, err);
  }
};