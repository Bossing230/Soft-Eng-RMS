const EmployeeRepository = require('../../repositories/EmployeeRepository');
const { notificationSubject } = require('./NotificationSubject');

/**
 * Sends one notification to each of the given roles, e.g.
 *   notifyRoles(['kitchen'], { title, message, type })
 *
 * A notification is only shown to an employee or a role, so it has to name one.
 * A failed alert never throws: the action that triggered it has already
 * happened and must not be undone because a notification could not be saved.
 */
async function notifyRoles(roleNames, { title, message, type }) {
  for (const roleName of roleNames) {
    try {
      const role = await EmployeeRepository.getRoleByName(roleName);
      if (!role) continue;
      await notificationSubject.notify({ roleId: role.role_id, title, message, type });
    } catch (err) {
      console.warn(`[notifications] could not notify ${roleName}:`, err.message);
    }
  }
}

module.exports = notifyRoles;