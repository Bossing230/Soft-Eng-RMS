const InventoryRepository = require('../repositories/InventoryRepository');
const RecipeRepository = require('../repositories/RecipeRepository');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { ReportBuilder, renderReportExcel, renderReportPdf, renderReportCsv } = require('../patterns/builders/ReportBuilder');
const { logAction } = require('../middleware/activityLogger');

// 'waste' writes stock off (expired, spilled, ...) and needs a reason.
const TRANSACTION_TYPES = ['delivery', 'usage', 'adjustment', 'waste'];
const WASTE_REASONS = ['Expired', 'Spoiled', 'Spilled or damaged', 'Returned to supplier', 'Other'];
const MAX_RESTOCK_ITEMS = 200;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const PHONE_RE = /^[0-9+()\-\s]*$/;

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

/**
 * The item's own low-stock line. Returns [value, error]:
 *   undefined = not sent (keep what the item has), null = blank (use the 30% default).
 */
function parseReorderLevel(raw) {
  if (raw === undefined) return [undefined, null];
  if (raw === null || raw === '') return [null, null];
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return [null, 'Reorder level must be greater than zero'];
  return [round2(n), null];
}

/** Optional text: undefined = not sent (keep), '' = cleared (null), otherwise trimmed. */
const optionalText = (raw, max) => (raw === undefined ? undefined : text(raw, max) || null);

/** A photo link must be one our upload route gave back (a Cloudinary https link, or a local /uploads path). */
const validImage = (v) => /^https?:\/\//i.test(v) || v.startsWith('/uploads/');
const IMAGE_ERROR = 'image must be the link returned by the photo upload';

exports.list = async (req, res) => {
  try {
    const archived = req.query.archived === '1' || req.query.archived === 'true';
    res.json(await InventoryRepository.findAll({ status: req.query.status, archived }));
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
    const image = text(req.body.image, 500) || null;
    const supplierName = text(req.body.supplierName, 100) || null;
    const supplierPhone = text(req.body.supplierPhone, 30) || null;
    const storageLocation = text(req.body.storageLocation, 50) || null;
    const notes = text(req.body.notes, 500) || null;
    const quantity = num(req.body.quantity);

    let maxStock = num(req.body.maxStock);
    // Older clients sent a minimum instead of a max: treat the minimum as 30% of max.
    if (!Number.isFinite(maxStock) && Number.isFinite(num(req.body.minimumStock))) {
      maxStock = Math.max(quantity, num(req.body.minimumStock) / 0.3);
    }

    const [expiryDate, expiryError] = parseOptionalDate(req.body.expiryDate);
    const [unitCost, costError] = parseOptionalCost(req.body.unitCost);
    const [reorderLevel, reorderError] = parseReorderLevel(req.body.reorderLevel);

    if (!name) return bad(res, 'Item name is required');
    if (!unit) return bad(res, 'Unit is required');
    if (!Number.isFinite(maxStock) || maxStock <= 0) return bad(res, 'Max stock must be greater than zero');
    if (!Number.isFinite(quantity) || quantity < 0) return bad(res, 'Current stock must be zero or more');
    if (quantity > maxStock) return bad(res, 'Current stock cannot be more than max stock');
    if (expiryError) return bad(res, expiryError);
    if (costError) return bad(res, costError);
    if (reorderError) return bad(res, reorderError);
    if (reorderLevel && reorderLevel > maxStock) return bad(res, "Reorder level can't be more than max stock");
    if (supplierPhone && !PHONE_RE.test(supplierPhone)) return bad(res, 'Phone can only have digits, spaces and + ( ) -');
    if (image && !validImage(image)) return bad(res, IMAGE_ERROR);

    const duplicate = await InventoryRepository.findByName(name);
    if (duplicate) {
      return res.status(409).json({
        error: Number(duplicate.is_archived)
          ? `"${name}" is already in the archive. Restore it from the Archived list instead.`
          : `"${name}" is already in the inventory`,
      });
    }

    const item = await InventoryRepository.create({
      ingredientName: name,
      category,
      quantity: round2(quantity),
      unit,
      maxStock: round2(maxStock),
      expiryDate,
      unitCost,
      image,
      reorderLevel: reorderLevel ?? null,
      supplierName,
      supplierPhone,
      storageLocation,
      notes,
    });
    await logAction(req.user.employeeId, `Added ingredient "${name}"`, 'inventory');
    res.status(201).json(item);
  } catch (err) {
    fail(res, err);
  }
};

/**
 * Edits name, category, unit, max stock, reorder level, expiry date, unit
 * cost, photo, supplier, storage location and notes. Nothing else can be
 * changed here. For optional fields, leave them out to keep what the item has;
 * send an empty value to clear them (an empty reorder level means "use 30% of
 * max stock").
 */
exports.update = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const name = text(req.body.ingredientName, 150);
    const unit = text(req.body.unit, 20);
    const category = text(req.body.category, 50) || null;
    const maxStock = num(req.body.maxStock);
    const image = optionalText(req.body.image, 500);
    const supplierName = optionalText(req.body.supplierName, 100);
    const supplierPhone = optionalText(req.body.supplierPhone, 30);
    const storageLocation = optionalText(req.body.storageLocation, 50);
    const notes = optionalText(req.body.notes, 500);
    const [expiryDate, expiryError] = parseOptionalDate(req.body.expiryDate);
    const [unitCost, costError] = parseOptionalCost(req.body.unitCost);
    const [reorderLevel, reorderError] = parseReorderLevel(req.body.reorderLevel);

    if (!name) return bad(res, 'Item name is required');
    if (!unit) return bad(res, 'Unit is required');
    if (!Number.isFinite(maxStock) || maxStock <= 0) return bad(res, 'Max stock must be greater than zero');
    if (expiryError) return bad(res, expiryError);
    if (costError) return bad(res, costError);
    if (reorderError) return bad(res, reorderError);
    if (supplierPhone && !PHONE_RE.test(supplierPhone)) return bad(res, 'Phone can only have digits, spaces and + ( ) -');
    if (image && !validImage(image)) return bad(res, IMAGE_ERROR);

    const existing = await InventoryRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Inventory item not found' });
    if (maxStock < Number(existing.quantity)) {
      return bad(res, `Max stock can't be less than the current stock (${Number(existing.quantity)} ${existing.unit})`);
    }

    // The reorder level that will apply after this edit must still fit under the max.
    const effectiveReorder = reorderLevel === undefined ? existing.reorder_level : reorderLevel;
    if (effectiveReorder && Number(effectiveReorder) > maxStock) {
      return bad(res, "Reorder level can't be more than max stock");
    }

    const duplicate = await InventoryRepository.findByName(name, id);
    if (duplicate) {
      return res.status(409).json({
        error: Number(duplicate.is_archived)
          ? `"${name}" is already in the archive. Restore it from the Archived list instead.`
          : `"${name}" is already in the inventory`,
      });
    }

    const item = await InventoryRepository.update(id, {
      ingredientName: name,
      category,
      unit,
      maxStock: round2(maxStock),
      expiryDate,
      unitCost,
      image,
      reorderLevel,
      supplierName,
      supplierPhone,
      storageLocation,
      notes,
    });
    await logAction(req.user.employeeId, `Edited ingredient "${name}"`, 'inventory');
    res.json(item);
  } catch (err) {
    fail(res, err);
  }
};

/** Uploads a photo and returns its link. Same storage as the menu photos. */
exports.uploadImage = async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No image file was uploaded' });
  }
  // With Cloudinary storage, req.file.path IS already the full https URL.
  res.status(201).json({ imageUrl: req.file.path });
};

/** Sets or removes (empty string) just the photo of one item. Body: { image }. */
exports.setImage = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const image = text(req.body.image, 500);
    if (image && !validImage(image)) return bad(res, IMAGE_ERROR);

    const existing = await InventoryRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Inventory item not found' });

    const item = await InventoryRepository.setImage(id, image || null);
    await logAction(
      req.user.employeeId,
      `${image ? 'Changed' : 'Removed'} the photo of ingredient "${existing.ingredient_name}"`,
      'inventory'
    );
    res.json(item);
  } catch (err) {
    fail(res, err);
  }
};

/**
 * Archives an item (hides it from the list, stats, alerts and reports, but
 * keeps its history) or restores it. Body: { archived: true | false }.
 * An item that is still part of a recipe can't be archived, since orders
 * would keep taking stock from something nobody can see.
 */
exports.setArchived = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { archived } = req.body;
    if (typeof archived !== 'boolean') return bad(res, 'archived must be true or false');

    const existing = await InventoryRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Inventory item not found' });

    if (archived) {
      const usedIn = await RecipeRepository.countUsing(id);
      if (usedIn > 0) {
        return bad(
          res,
          `${existing.ingredient_name} is used in ${usedIn} recipe${usedIn === 1 ? '' : 's'}, so it can't be archived. Remove it from those recipes first.`
        );
      }
    }

    const item = await InventoryRepository.setArchived(id, archived);
    await logAction(
      req.user.employeeId,
      `${archived ? 'Archived' : 'Restored'} ingredient "${existing.ingredient_name}"`,
      'inventory'
    );
    res.json(item);
  } catch (err) {
    fail(res, err);
  }
};

/**
 * delivery   -> quantity is added
 * usage      -> quantity is taken out (never more than what is in stock)
 * waste      -> quantity is written off, with a reason (never more than in stock)
 * adjustment -> a signed correction after a physical count (positive or negative)
 */
exports.adjustStock = async (req, res) => {
  try {
    const { type } = req.body;
    const quantity = num(req.body.quantity);
    const reason = text(req.body.reason, 100);

    if (!TRANSACTION_TYPES.includes(type)) return bad(res, `type must be one of: ${TRANSACTION_TYPES.join(', ')}`);
    if (!Number.isFinite(quantity) || quantity === 0) return bad(res, 'Enter a quantity greater than zero');
    if (type !== 'adjustment' && quantity < 0) return bad(res, 'Quantity must be greater than zero');
    if (type === 'waste' && !WASTE_REASONS.includes(reason)) {
      return bad(res, `reason must be one of: ${WASTE_REASONS.join(', ')}`);
    }

    const takesOut = type === 'usage' || type === 'waste';
    const delta = round2(takesOut ? -quantity : quantity);
    const result = await InventoryRepository.adjustStock(
      req.params.id,
      delta,
      type,
      req.user.employeeId,
      type === 'waste' ? reason : null
    );

    await logAction(
      req.user.employeeId,
      type === 'waste'
        ? `Wasted ${quantity} of inventory #${req.params.id} (${reason})`
        : `${type} of ${quantity} for inventory #${req.params.id}`,
      'inventory'
    );

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

// ---------------------------------------------------------------------------
// Report
//   GET /inventory/report?format=pdf|excel|csv|json
//                        &filter=all|low|expiring   (default all)
//                        &category=Beverages        (optional)
//                        &search=cab                (optional)
// Archived items are never included.
// ---------------------------------------------------------------------------
const REPORT_FORMATS = ['pdf', 'excel', 'csv', 'json'];
const REPORT_FILTERS = ['all', 'low', 'expiring'];
const EXPIRING_SOON_DAYS = 7;
const REPORT_TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;
const SEVERITY_LABEL = { ok: 'In Stock', low: 'Low Stock', critical: 'Critical', out: 'Out of Stock' };
const SEVERITY_RANK = { out: 0, critical: 1, low: 2, ok: 3 };

const peso = (n) => `PHP ${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** 'YYYY-MM-DD' from a Date or a date string, or '' when there is none. */
function dateOnly(v) {
  if (!v) return '';
  if (v instanceof Date) {
    if (Number.isNaN(v.getTime())) return '';
    const p = (n) => String(n).padStart(2, '0');
    return `${v.getFullYear()}-${p(v.getMonth() + 1)}-${p(v.getDate())}`;
  }
  const s = String(v);
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : '';
}

/** Restaurant-local 'YYYY-MM-DD HH:MM' from a stored timestamp. */
function localDateTime(v) {
  if (!v) return '';
  const d = v instanceof Date ? v : new Date(String(v).replace(' ', 'T'));
  if (Number.isNaN(d.getTime())) return '';
  const iso = new Date(d.getTime() + REPORT_TZ_OFFSET_HOURS * 3600000).toISOString();
  return `${iso.slice(0, 10)} ${iso.slice(11, 16)}`;
}

/** Whole days from today (restaurant-local) until the given 'YYYY-MM-DD'. Negative = already past. */
function daysUntil(dateStr) {
  const now = new Date(Date.now() + REPORT_TZ_OFFSET_HOURS * 3600000);
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const [y, m, d] = dateStr.split('-').map(Number);
  return Math.round((Date.UTC(y, m - 1, d) - today) / 86400000);
}

exports.report = async (req, res) => {
  try {
    const format = String(req.query.format || 'json').toLowerCase();
    const filter = String(req.query.filter || 'all').toLowerCase();
    const category = text(req.query.category, 50);
    const search = text(req.query.search, 100).toLowerCase();

    if (!REPORT_FORMATS.includes(format)) return bad(res, `format must be one of: ${REPORT_FORMATS.join(', ')}`);
    if (!REPORT_FILTERS.includes(filter)) return bad(res, `filter must be one of: ${REPORT_FILTERS.join(', ')}`);

    const all = await InventoryRepository.findAll();
    const items = all
      .filter((i) => {
        const itemCategory = i.category || 'Uncategorized';
        if (category && itemCategory !== category) return false;
        if (search && !i.ingredient_name.toLowerCase().includes(search) && !itemCategory.toLowerCase().includes(search)) {
          return false;
        }
        if (filter === 'low') return i.status !== 'ok';
        if (filter === 'expiring') {
          const exp = dateOnly(i.expiry_date);
          return exp !== '' && daysUntil(exp) <= EXPIRING_SOON_DAYS;
        }
        return true;
      })
      .sort(
        (a, b) =>
          (SEVERITY_RANK[a.severity] ?? 9) - (SEVERITY_RANK[b.severity] ?? 9) ||
          a.ingredient_name.localeCompare(b.ingredient_name)
      );

    let totalValue = 0;
    let expiringCount = 0;
    const rows = items.map((i) => {
      const quantity = Number(i.quantity);
      const maxStock = Number(i.max_stock) || 0;
      const unitCost = Number(i.unit_cost) || 0;
      const exp = dateOnly(i.expiry_date);
      const days = exp ? daysUntil(exp) : null;
      const stockValue = round2(quantity * unitCost);

      totalValue += stockValue;
      if (days !== null && days >= 0 && days <= EXPIRING_SOON_DAYS) expiringCount += 1;

      return {
        ingredient_name: i.ingredient_name,
        category: i.category || 'Uncategorized',
        storage_location: i.storage_location || '',
        quantity,
        unit: i.unit,
        max_stock: maxStock,
        level: maxStock > 0 ? `${Math.min(100, Math.round((quantity / maxStock) * 100))}%` : '',
        status: SEVERITY_LABEL[i.severity] || i.status,
        unit_cost: unitCost > 0 ? unitCost : '',
        stock_value: unitCost > 0 ? stockValue : '',
        expiry_date: exp ? (days < 0 ? `${exp} (expired)` : exp) : '',
        supplier: [i.supplier_name, i.supplier_phone].filter(Boolean).join(' · '),
        updated: localDateTime(i.updated_at),
        _highlight: i.severity !== 'ok' ? i.severity : null,
      };
    });

    const scope = [];
    if (category) scope.push(`Category: ${category}`);
    if (search) scope.push(`Search: "${search}"`);
    if (filter === 'low') scope.push('Low, critical and out-of-stock items only');
    if (filter === 'expiring') scope.push(`Expiring within ${EXPIRING_SOON_DAYS} days or already expired`);

    const report = new ReportBuilder('Inventory Report')
      .setSubtitle(scope.length ? scope.join('  |  ') : 'All inventory items')
      .setColumns([
        { key: 'ingredient_name', label: 'Ingredient', width: 2.1 },
        { key: 'category', label: 'Category', width: 1.4 },
        { key: 'storage_location', label: 'Location', width: 1.2 },
        { key: 'quantity', label: 'Stock', type: 'number', width: 0.9 },
        { key: 'unit', label: 'Unit', width: 0.7 },
        { key: 'max_stock', label: 'Max Stock', type: 'number', width: 0.9 },
        { key: 'level', label: 'Level', type: 'number', width: 0.8 },
        { key: 'status', label: 'Status', width: 1.1 },
        { key: 'unit_cost', label: 'Unit Cost', type: 'money', width: 1.1 },
        { key: 'stock_value', label: 'Stock Value', type: 'money', width: 1.3 },
        { key: 'expiry_date', label: 'Expiry', width: 1.4 },
        { key: 'supplier', label: 'Supplier', width: 2 },
        { key: 'updated', label: 'Last Updated', width: 1.5 },
      ])
      .addRows(rows)
      .setSummary({
        'Total Items': rows.length,
        'Low / Critical': items.filter((i) => i.severity === 'low' || i.severity === 'critical').length,
        'Out of Stock': items.filter((i) => i.severity === 'out').length,
        'Expiring Soon': expiringCount,
        'Total Value': peso(totalValue),
      })
      .build();

    await logAction(req.user.employeeId, `Downloaded the inventory report (${format})`, 'inventory');

    if (format === 'json') return res.json(report);

    const stamp = new Date(Date.now() + REPORT_TZ_OFFSET_HOURS * 3600000).toISOString().slice(0, 10);
    const filename = `inventory-report-${stamp}`;

    if (format === 'pdf') {
      const buffer = await renderReportPdf(report);
      res.set('Content-Type', 'application/pdf');
      res.set('Content-Disposition', `attachment; filename="${filename}.pdf"`);
      return res.send(buffer);
    }
    if (format === 'excel') {
      const buffer = await renderReportExcel(report);
      res.set('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      res.set('Content-Disposition', `attachment; filename="${filename}.xlsx"`);
      return res.send(buffer);
    }
    const buffer = renderReportCsv(report);
    res.set('Content-Type', 'text/csv; charset=utf-8');
    res.set('Content-Disposition', `attachment; filename="${filename}.csv"`);
    return res.send(buffer);
  } catch (err) {
    fail(res, err);
  }
};