const jwt = require('jsonwebtoken');
const SessionManager = require('../patterns/singletons/SessionManager');
const Presence = require('../services/presence');
const AccountGuard = require('../services/accountGuard');

async function authenticate(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = header.split(' ')[1];

  if (SessionManager.isInvalidated(token)) {
    return res.status(401).json({ error: 'Session has been logged out' });
  }

  let decoded;
  try {
    decoded = jwt.verify(token, process.env.JWT_SECRET);
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  // A deleted or deactivated account is locked out everywhere, even with a
  // token that has not expired yet (see services/accountGuard.js).
  if (decoded.employeeId && !(await AccountGuard.isActive(decoded.employeeId))) {
    return res.status(401).json({ error: 'This account is no longer active' });
  }

  req.user = decoded; // { employeeId, username, role }
  req.token = token;
  // Remember that this person's app is open right now (see services/presence.js).
  if (decoded.employeeId && !decoded.purpose) Presence.touch(decoded.employeeId);
  next();
}

module.exports = authenticate;