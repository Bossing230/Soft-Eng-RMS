const bcrypt = require('bcrypt');
const db = require('../patterns/singletons/DatabaseManager');
const ensureAuthColumns = require('../database/ensure-auth-columns');

const CODE_TTL_MINUTES = 10;
const MAX_CODE_ATTEMPTS = 5;
const MIN_SECONDS_BETWEEN_REQUESTS = 60;

class PasswordResetRepository {
  _ready() {
    if (!this._schema) {
      this._schema = ensureAuthColumns().catch((err) => {
        this._schema = null;
        throw err;
      });
    }
    return this._schema;
  }

  /** The most recent still-valid (unused, unexpired) code row for this employee, if any. */
  async findActive(employeeId) {
    await this._ready();
    const rows = await db.query(
      `SELECT * FROM password_resets
        WHERE employee_id = ? AND used = 0 AND expires_at > NOW()
        ORDER BY reset_id DESC LIMIT 1`,
      [employeeId]
    );
    return rows[0] || null;
  }

  /** The most recent code request of any kind (used, expired or not), to enforce a cooldown. */
  async findMostRecent(employeeId) {
    await this._ready();
    const rows = await db.query(`SELECT * FROM password_resets WHERE employee_id = ? ORDER BY reset_id DESC LIMIT 1`, [
      employeeId,
    ]);
    return rows[0] || null;
  }

  /** Seconds the caller must still wait before requesting another code (0 if none). */
  async secondsUntilNextRequestAllowed(employeeId) {
    const last = await this.findMostRecent(employeeId);
    if (!last) return 0;
    const createdMs = new Date(String(last.created_at).replace(' ', 'T')).getTime();
    const elapsed = (Date.now() - createdMs) / 1000;
    return Math.max(0, Math.ceil(MIN_SECONDS_BETWEEN_REQUESTS - elapsed));
  }

  /**
   * Generates a new 6-digit code, invalidates any still-active code for this
   * employee (so only the newest one ever works), and stores a bcrypt hash of
   * it — never the code itself. Returns the plain code so it can be emailed
   * once; nothing else ever sees it again.
   */
  async createCode(employeeId) {
    await this._ready();
    await db.query('UPDATE password_resets SET used = 1 WHERE employee_id = ? AND used = 0', [employeeId]);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const codeHash = await bcrypt.hash(code, 10);
    await db.query(
      `INSERT INTO password_resets (employee_id, code_hash, expires_at)
       VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ${CODE_TTL_MINUTES} MINUTE))`,
      [employeeId, codeHash]
    );
    return code;
  }

  /**
   * Checks a code against the employee's active one. Returns 'ok', 'wrong',
   * 'expired', or 'too_many_attempts' (the code is burned at that point —
   * request a new one). Every wrong guess counts, so this can't be brute-forced.
   */
  async verifyCode(employeeId, code) {
    await this._ready();
    const active = await this.findActive(employeeId);
    if (!active) return 'expired';
    if (active.attempts >= MAX_CODE_ATTEMPTS) {
      await db.query('UPDATE password_resets SET used = 1 WHERE reset_id = ?', [active.reset_id]);
      return 'too_many_attempts';
    }

    const matches = await bcrypt.compare(String(code), active.code_hash);
    if (!matches) {
      const attempts = active.attempts + 1;
      const exhausted = attempts >= MAX_CODE_ATTEMPTS;
      await db.query('UPDATE password_resets SET attempts = ?, used = ? WHERE reset_id = ?', [
        attempts,
        exhausted ? 1 : 0,
        active.reset_id,
      ]);
      return exhausted ? 'too_many_attempts' : 'wrong';
    }

    await db.query('UPDATE password_resets SET used = 1 WHERE reset_id = ?', [active.reset_id]);
    return 'ok';
  }
}

module.exports = new PasswordResetRepository();
module.exports.CODE_TTL_MINUTES = CODE_TTL_MINUTES;
module.exports.MAX_CODE_ATTEMPTS = MAX_CODE_ATTEMPTS;