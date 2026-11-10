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
const SEVERITY_LABEL = { ok: 'Good', low: 'Low', critical: 'Critical', out: 'Out of Stock' };
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
        reorder_at: Number(i.minimum_stock) || 0,
        level: maxStock > 0 ? `${Math.min(100, Math.round((quantity / maxStock) * 100))}%` : '',
        status: SEVERITY_LABEL[i.severity] || i.status,
        unit_cost: unitCost > 0 ? unitCost : '',
        stock_value: unitCost > 0 ? stockValue : '',
        expiry_date: exp ? (days < 0 ? `${exp} (expired)` : exp) : '',
        supplier: [i.supplier_name, i.supplier_phone].filter(Boolean).join(' · '),
        updated: (i.updated_at_local || '').slice(0, 16),
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
        { key: 'reorder_at', label: 'Reorder At', type: 'number', width: 0.9 },
        { key: 'level', label: 'Stock Level', type: 'number', width: 0.9 },
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
        'Good': items.filter((i) => i.severity === 'ok').length,
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