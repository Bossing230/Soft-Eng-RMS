/**
 * Singleton Pattern — tracks active sessions / blacklisted (logged-out)
 * JWT tokens in-memory. In production this should be backed by Redis.
 */
class SessionManager {
  constructor() {
    if (SessionManager.instance) {
      return SessionManager.instance;
    }
    this.blacklistedTokens = new Set();
    SessionManager.instance = this;
  }

  invalidateToken(token) {
    this.blacklistedTokens.add(token);
  }

  isInvalidated(token) {
    return this.blacklistedTokens.has(token);
  }
}

module.exports = new SessionManager();