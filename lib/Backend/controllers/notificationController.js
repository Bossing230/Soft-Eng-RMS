const NotificationRepository = require('../repositories/NotificationRepository');
const EmployeeRepository = require('../repositories/EmployeeRepository');

exports.list = async (req, res) => {
  const employee = await EmployeeRepository.findById(req.user.employeeId);
  const notifications = await NotificationRepository.findForEmployee(req.user.employeeId, employee.role_id, {
    unreadOnly: req.query.unreadOnly === 'true',
  });
  res.json(notifications);
};

exports.markRead = async (req, res) => {
  await NotificationRepository.markRead(req.params.id);
  res.json({ message: 'Marked as read' });
};

exports.markAllRead = async (req, res) => {
  const employee = await EmployeeRepository.findById(req.user.employeeId);
  await NotificationRepository.markAllRead(req.user.employeeId, employee.role_id);
  res.json({ message: 'All notifications marked as read' });
};