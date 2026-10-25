const bcrypt = require('bcrypt');
const db = require('../patterns/singletons/DatabaseManager');
const ensureAuthColumns = require('../database/ensure-auth-columns');

const CODE_TTL_MINUTES = 10;
const MAX_CODE_ATTEMPTS = 5;
const MIN_SECONDS_BETWEEN_REQUESTS = 60;

const normalize = (email) => String(email).trim().toLowerCase();

/**
 * Codes emailed to an address that does not have an account yet (a new
 * employee being created by an administrator). Same rules as password reset
 * codes: stored hashed, expire after 10 minutes, 60s resend cooldown,
 * 5 wrong tries burns the code. Keyed by email instead of employee id.
 */
class EmailVerificationRepository {
  _ready() {
    if (!this._schema) {
      this._schema = ensureAuthColumns().catch((err) => {
        this._schema = null;
        throw err;
      });
    }
    return this._schema;
  }

  async findActive(email) {
    await this._ready();
    const rows = await db.query(
      `SELECT * FROM email_verifications
        WHERE email = ? AND used = 0 AND expires_at > NOW()
        ORDER BY verification_id DESC LIMIT 1`,
      [normalize(email)]
    );
    return rows[0] || null;
  }

  async findMostRecent(email) {
    await this._ready();
    const rows = await db.query(
      'SELECT * FROM email_verifications WHERE email = ? ORDER BY verification_id DESC LIMIT 1',
      [normalize(email)]
    );
    return rows[0] || null;
  }

  /** Seconds the caller must still wait before requesting another code (0 if none). */
  async secondsUntilNextRequestAllowed(email) {
    const last = await this.findMostRecent(email);
    if (!last) return 0;
    const createdMs =
      last.created_at instanceof Date
        ? last.created_at.getTime()
        : new Date(String(last.created_at).replace(' ', 'T')).getTime();
    if (Number.isNaN(createdMs)) return 0;
    const elapsed = (Date.now() - createdMs) / 1000;
    return Math.max(0, Math.ceil(MIN_SECONDS_BETWEEN_REQUESTS - elapsed));
  }

  /** New 6-digit code (older active ones stop working). Returns the plain code to email once. */
  async createCode(email) {
    await this._ready();
    const key = normalize(email);
    await db.query('UPDATE email_verifications SET used = 1 WHERE email = ? AND used = 0', [key]);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const codeHash = await bcrypt.hash(code, 10);
    await db.query(
      `INSERT INTO email_verifications (email, code_hash, expires_at)
       VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ${CODE_TTL_MINUTES} MINUTE))`,
      [key, codeHash]
    );
    return code;
  }

  /** Removes the just-created code when its email could not be sent, so the cooldown doesn't block a retry. */
  async discardActive(email) {
    await this._ready();
    await db.query('DELETE FROM email_verifications WHERE email = ? AND used = 0', [normalize(email)]);
  }

  /** Returns 'ok', 'wrong', 'expired' or 'too_many_attempts'. */
  async verifyCode(email, code) {
    await this._ready();
    const active = await this.findActive(email);
    if (!active) return 'expired';
    if (active.attempts >= MAX_CODE_ATTEMPTS) {
      await db.query('UPDATE email_verifications SET used = 1 WHERE verification_id = ?', [active.verification_id]);
      return 'too_many_attempts';
    }

    const matches = await bcrypt.compare(String(code), active.code_hash);
    if (!matches) {
      const attempts = active.attempts + 1;
      const exhausted = attempts >= MAX_CODE_ATTEMPTS;
      await db.query('UPDATE email_verifications SET attempts = ?, used = ? WHERE verification_id = ?', [
        attempts,
        exhausted ? 1 : 0,
        active.verification_id,
      ]);
      return exhausted ? 'too_many_attempts' : 'wrong';
    }

    await db.query('UPDATE email_verifications SET used = 1 WHERE verification_id = ?', [active.verification_id]);
    return 'ok';
  }
}

module.exports = new EmailVerificationRepository();