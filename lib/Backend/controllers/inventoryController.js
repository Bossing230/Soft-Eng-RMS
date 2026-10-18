const InventoryRepository = require('../repositories/InventoryRepository');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { ReportBuilder, renderReportExcel, renderReportPdf } = require('../patterns/builders/ReportBuilder');
const { logAction } = require('../middleware/activityLogger');

const TRANSACTION_TYPES = ['delivery', 'usage', 'adjustment'];
const MAX_RESTOCK_ITEMS = 200;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// Blank / missing values become NaN so they fail validation instead of becoming 0.
const num = (v) => (v === '' || v === null || v === undefined ? NaN : Number(v));
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const round2 = (n) => Math.round(n * 100) / 100;
// Alerts go to the administrator and manager roles. Every notification needs a
// recipient (a role or an employee): one saved with neither is never shown in
// anyone's bell.
const ALERT_ROLES = ['administrator', 'manager'];

async function notifyManagement({ title, message, type }) {
  for (const roleName of ALERT_ROLES) {
    try {
      const role = await EmployeeRepository.getRoleByName(roleName);
      if (!role) continue;
      await notificationSubject.notify({ roleId: role.role_id, title, message, type });
    } catch (err) {
      // The stock change is already saved; a failed alert must not undo it.
      console.warn(`[inventory] could not notify ${roleName}:`, err.message);
    }
  }
}

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });
const bad = (res, message) => res.status(400).json({ error: message });

/** Returns [value, error] — value is null and error is set if the input is present but invalid. */
function parseOptionalDate(raw) {
  if (raw === undefined || raw === null || raw === '') return [null, null];
  if (typeof raw !== 'string' || !DATE_RE.test(raw)) return [null, 'expiryDate must be in YYYY-MM-DD format'];
  return [raw, null];
}

function parseOptionalCost(raw) {
  if (raw === undefined || raw === null || raw === '') return [0, null];
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return [null, 'unitCost must be zero or more'];
  return [round2(n), null];
}

exports.list = async (req, res) => {
  try {
    res.json(await InventoryRepository.findAll({ status: req.query.status }));
  } catch (err) {
    fail(res, err);
  }
};

exports.lowStock = async (req, res) => {
  try {
    res.json(await InventoryRepository.findLowStock());
  } catch (err) {
    fail(res, err);
  }
};

/** Stats, category breakdown, the single most urgent item, and recent activity — for the overview panel. */
exports.overview = async (req, res) => {
  try {
    res.json(await InventoryRepository.getOverview());
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const name = text(req.body.ingredientName, 150);
    const unit = text(req.body.unit, 20);
    const category = text(req.body.category, 50) || null;
    const quantity = num(req.body.quantity);

    let maxStock = num(req.body.maxStock);
    // Older clients sent a minimum instead of a max: treat the minimum as 30% of max.
    if (!Number.isFinite(maxStock) && Number.isFinite(num(req.body.minimumStock))) {
      maxStock = Math.max(quantity, num(req.body.minimumStock) / 0.3);
    }

    const [expiryDate, expiryError] = parseOptionalDate(req.body.expiryDate);
    const [unitCost, costError] = parseOptionalCost(req.body.unitCost);

    if (!name) return bad(res, 'Item name is required');
    if (!unit) return bad(res, 'Unit is required');
    if (!Number.isFinite(maxStock) || maxStock <= 0) return bad(res, 'Max stock must be greater than zero');
    if (!Number.isFinite(quantity) || quantity < 0) return bad(res, 'Current stock must be zero or more');
    if (quantity > maxStock) return bad(res, 'Current stock cannot be more than max stock');
    if (expiryError) return bad(res, expiryError);
    if (costError) return bad(res, costError);

    if (await InventoryRepository.findByName(name)) {
      return res.status(409).json({ error: `"${name}" is already in the inventory` });
    }

    const item = await InventoryRepository.create({
      ingredientName: name,
      category,
      quantity: round2(quantity),
      unit,
      maxStock: round2(maxStock),
      expiryDate,
      unitCost,
    });
    await logAction(req.user.employeeId, `Added ingredient "${name}"`, 'inventory');
    res.status(201).json(item);
  } catch (err) {
    fail(res, err);
  }
};

/** Edits name, category, unit, max stock, expiry date and unit cost. Nothing else can be changed here. */
exports.update = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const name = text(req.body.ingredientName, 150);
    const unit = text(req.body.unit, 20);
    const category = text(req.body.category, 50) || null;
    const maxStock = num(req.body.maxStock);
    const [expiryDate, expiryError] = parseOptionalDate(req.body.expiryDate);
    const [unitCost, costError] = parseOptionalCost(req.body.unitCost);

    if (!name) return bad(res, 'Item name is required');
    if (!unit) return bad(res, 'Unit is required');
    if (!Number.isFinite(maxStock) || maxStock <= 0) return bad(res, 'Max stock must be greater than zero');
    if (expiryError) return bad(res, expiryError);
    if (costError) return bad(res, costError);

    const existing = await InventoryRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Inventory item not found' });
    if (maxStock < Number(existing.quantity)) {
      return bad(res, `Max stock can't be less than the current stock (${Number(existing.quantity)} ${existing.unit})`);
    }
    if (await InventoryRepository.findByName(name, id)) {
      return res.status(409).json({ error: `"${name}" is already in the inventory` });
    }

    const item = await InventoryRepository.update(id, {
      ingredientName: name,
      category,
      unit,
      maxStock: round2(maxStock),
      expiryDate,
      unitCost,
    });
    await logAction(req.user.employeeId, `Edited ingredient "${name}"`, 'inventory');
    res.json(item);
  } catch (err) {
    fail(res, err);
  }
};

/**
 * delivery   -> quantity is added
 * usage      -> quantity is taken out (never more than what is in stock)
 * adjustment -> a signed correction after a physical count (positive or negative)
 */
exports.adjustStock = async (req, res) => {
  try {
    const { type } = req.body;
    const quantity = num(req.body.quantity);

    if (!TRANSACTION_TYPES.includes(type)) return bad(res, `type must be one of: ${TRANSACTION_TYPES.join(', ')}`);
    if (!Number.isFinite(quantity) || quantity === 0) return bad(res, 'Enter a quantity greater than zero');
    if (type !== 'adjustment' && quantity < 0) return bad(res, 'Quantity must be greater than zero');

    const delta = round2(type === 'usage' ? -quantity : quantity);
    const result = await InventoryRepository.adjustStock(req.params.id, delta, type, req.user.employeeId);

    await logAction(req.user.employeeId, `${type} of ${quantity} for inventory #${req.params.id}`, 'inventory');

    // Observer Pattern: alert once when an item drops into low or out of stock,
    // not on every later adjustment while it stays low.
    if (result.crossedIntoLow) {
      const isOut = result.status === 'out';
      await notifyManagement({
        title: isOut ? 'Out of Stock Alert' : 'Low Stock Alert',
        message: isOut
          ? `${result.ingredient_name} is out of stock.`
          : `${result.ingredient_name} is running low (${result.quantity} ${result.unit} remaining).`,
        type: 'low_stock',
      });
    }

    res.json(result);
  } catch (err) {
    fail(res, err);
  }
};

/** Body: { items: [{ inventoryId, quantity }] }. Records one delivery per item, all or nothing. */
exports.restock = async (req, res) => {
  try {
    const raw = Array.isArray(req.body.items) ? req.body.items : [];
    if (!raw.length) return bad(res, 'Nothing to restock');
    if (raw.length > MAX_RESTOCK_ITEMS) return bad(res, `Restock at most ${MAX_RESTOCK_ITEMS} items at a time`);

    const items = raw.map((i) => ({ inventoryId: Number(i.inventoryId), quantity: round2(num(i.quantity)) }));
    if (items.some((i) => !Number.isInteger(i.inventoryId) || !(i.quantity > 0))) {
      return bad(res, 'Each item needs an inventoryId and a quantity greater than zero');
    }
    if (new Set(items.map((i) => i.inventoryId)).size !== items.length) {
      return bad(res, 'Each item can only appear once');
    }
    items.sort((a, b) => a.inventoryId - b.inventoryId); // same lock order every time

    await InventoryRepository.restockMany(items, req.user.employeeId);
    await logAction(req.user.employeeId, `Restocked ${items.length} low-stock item(s)`, 'inventory');
    res.json({ restocked: items.length });
  } catch (err) {
    fail(res, err);
  }
};

exports.history = async (req, res) => {
  try {
    res.json(await InventoryRepository.history(req.params.id));
  } catch (err) {
    fail(res, err);
  }
};

exports.report = async (req, res) => {
  try {
    const format = req.query.format || 'json';
    const items = await InventoryRepository.findAll();

    const builder = new ReportBuilder('Inventory Report')
      .setColumns([
        { key: 'ingredient_name', label: 'Ingredient' },
        { key: 'category', label: 'Category' },
        { key: 'quantity', label: 'Quantity' },
        { key: 'unit', label: 'Unit' },
        { key: 'minimum_stock', label: 'Min Stock' },
        { key: 'status', label: 'Status' },
        { key: 'expiry_date', label: 'Expiry Date' },
        { key: 'unit_cost', label: 'Unit Cost' },
      ])
      .addRows(items)
      .setSummary({
        'Total Items': items.length,
        'Low/Out of Stock': items.filter((i) => i.status !== 'ok').length,
        'Total Value': items.reduce((sum, i) => sum + Number(i.quantity) * Number(i.unit_cost || 0), 0).toFixed(2),
      });

    const report = builder.build();

    if (format === 'pdf') {
      const buffer = await renderReportPdf(report);
      res.set('Content-Type', 'application/pdf');
      res.set('Content-Disposition', 'attachment; filename="inventory-report.pdf"');
      return res.send(buffer);
    }
    if (format === 'excel') {
      const buffer = await renderReportExcel(report);
      res.set('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      res.set('Content-Disposition', 'attachment; filename="inventory-report.xlsx"');
      return res.send(buffer);
    }
    res.json(report);
  } catch (err) {
    fail(res, err);
  }
};