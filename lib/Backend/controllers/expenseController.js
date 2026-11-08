const ExpenseRepository = require('../repositories/ExpenseRepository');
const { logAction } = require('../middleware/activityLogger');

// Must match _categories in the Flutter expenses_page.dart.
const CATEGORIES = ['Ingredients', 'Utilities', 'Salaries', 'Rent', 'Equipment', 'Maintenance', 'Other'];
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_AMOUNT = 10000000;

const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const round2 = (n) => Math.round(n * 100) / 100;
const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });
const bad = (res, message) => res.status(400).json({ error: message });

/** Returns [data, error]. */
function read(body) {
  const category = text(body.category, 50);
  const description = text(body.description, 255);
  const amount = body.amount === '' || body.amount === null || body.amount === undefined ? NaN : Number(body.amount);
  const expenseDate = typeof body.expenseDate === 'string' ? body.expenseDate : '';

  if (!CATEGORIES.includes(category)) return [null, `category must be one of: ${CATEGORIES.join(', ')}`];
  if (!description) return [null, 'Description is required'];
  if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_AMOUNT) return [null, 'Amount must be greater than zero'];
  if (!DATE_RE.test(expenseDate)) return [null, 'Date must be in YYYY-MM-DD format'];
  return [{ category, description, amount: round2(amount), expenseDate }, null];
}

/** GET /expenses?start=&end=&category= -> { items, summary } */
exports.list = async (req, res) => {
  try {
    const start = DATE_RE.test(req.query.start || '') ? req.query.start : undefined;
    const end = DATE_RE.test(req.query.end || '') ? req.query.end : undefined;
    const category = CATEGORIES.includes(req.query.category) ? req.query.category : undefined;
    const [items, summary] = await Promise.all([
      ExpenseRepository.findAll({ start, end, category }),
      ExpenseRepository.summary({ start, end }),
    ]);
    res.json({ items, summary });
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const [data, error] = read(req.body);
    if (error) return bad(res, error);
    const expense = await ExpenseRepository.create({ ...data, recordedBy: req.user.employeeId });
    await logAction(req.user.employeeId, `Recorded expense "${data.description}" (PHP ${data.amount})`, 'expenses');
    res.status(201).json(expense);
  } catch (err) {
    fail(res, err);
  }
};

exports.update = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const [data, error] = read(req.body);
    if (error) return bad(res, error);
    if (!(await ExpenseRepository.findById(id))) return res.status(404).json({ error: 'Expense not found' });
    const expense = await ExpenseRepository.update(id, data);
    await logAction(req.user.employeeId, `Edited expense "${data.description}"`, 'expenses');
    res.json(expense);
  } catch (err) {
    fail(res, err);
  }
};

exports.remove = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await ExpenseRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Expense not found' });
    await ExpenseRepository.remove(id);
    await logAction(req.user.employeeId, `Deleted expense "${existing.description}"`, 'expenses');
    res.json({ deleted: true });
  } catch (err) {
    fail(res, err);
  }
};