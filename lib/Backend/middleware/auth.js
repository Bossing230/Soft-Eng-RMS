const jwt = require('jsonwebtoken');
const SessionManager = require('../patterns/singletons/SessionManager');
const Presence = require('../services/presence');

function authenticate(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = header.split(' ')[1];

  if (SessionManager.isInvalidated(token)) {
    return res.status(401).json({ error: 'Session has been logged out' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded; // { employeeId, username, role }
    req.token = token;
    // Remember that this person's app is open right now (see services/presence.js).
    if (decoded.employeeId && !decoded.purpose) Presence.touch(decoded.employeeId);
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = authenticate;