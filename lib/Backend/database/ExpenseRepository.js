const db = require('../patterns/singletons/DatabaseManager');
const ensureTables = require('../database/ensure-supplier-expense-tables');

const SELECT = `
  SELECT e.expense_id,
         DATE_FORMAT(e.expense_date, '%Y-%m-%d') AS expense_date,
         e.category, e.description, e.amount, e.supplier_id,
         s.name AS supplier_name,
         emp.name AS recorded_by
    FROM expenses e
    LEFT JOIN suppliers s ON s.supplier_id = e.supplier_id
    LEFT JOIN employees emp ON emp.employee_id = e.recorded_by`;

class ExpenseRepository {
  _ready() {
    if (!this._schema) {
      this._schema = ensureTables().catch((err) => {
        this._schema = null;
        throw err;
      });
    }
    return this._schema;
  }

  /** Newest first. start / end are 'YYYY-MM-DD' (both optional). */
  async findAll({ start, end, category } = {}) {
    await this._ready();
    let sql = `${SELECT} WHERE 1 = 1`;
    const params = [];
    if (start) { sql += ' AND e.expense_date >= ?'; params.push(start); }
    if (end) { sql += ' AND e.expense_date <= ?'; params.push(end); }
    if (category) { sql += ' AND e.category = ?'; params.push(category); }
    sql += ' ORDER BY e.expense_date DESC, e.expense_id DESC LIMIT 1000';
    return db.query(sql, params);
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query(`${SELECT} WHERE e.expense_id = ?`, [id]);
    return rows[0] || null;
  }

  /** Total, number of entries and a per-category breakdown for the period. */
  async summary({ start, end } = {}) {
    await this._ready();
    let where = 'WHERE 1 = 1';
    const params = [];
    if (start) { where += ' AND expense_date >= ?'; params.push(start); }
    if (end) { where += ' AND expense_date <= ?'; params.push(end); }

    const [totals] = await db.query(
      `SELECT COALESCE(SUM(amount), 0) AS total, COUNT(*) AS count FROM expenses ${where}`,
      params
    );
    const byCategory = await db.query(
      `SELECT category, COALESCE(SUM(amount), 0) AS total FROM expenses ${where}
        GROUP BY category ORDER BY total DESC`,
      params
    );
    return {
      total: Number(totals.total),
      count: Number(totals.count),
      byCategory: byCategory.map((r) => ({ category: r.category, total: Number(r.total) })),
    };
  }

  async total(start, end) {
    return (await this.summary({ start, end })).total;
  }

  async create({ expenseDate, category, description, amount, supplierId, recordedBy }) {
    await this._ready();
    const result = await db.query(
      `INSERT INTO expenses (expense_date, category, description, amount, supplier_id, recorded_by)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [expenseDate, category, description, amount, supplierId, recordedBy]
    );
    return this.findById(result.insertId);
  }

  async update(id, { expenseDate, category, description, amount, supplierId }) {
    await this._ready();
    await db.query(
      `UPDATE expenses SET expense_date = ?, category = ?, description = ?, amount = ?, supplier_id = ?
        WHERE expense_id = ?`,
      [expenseDate, category, description, amount, supplierId, id]
    );
    return this.findById(id);
  }

  async remove(id) {
    await this._ready();
    await db.query('DELETE FROM expenses WHERE expense_id = ?', [id]);
  }
}

module.exports = new ExpenseRepository();