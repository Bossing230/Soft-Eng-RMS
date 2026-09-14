const InventoryRepository = require('../repositories/InventoryRepository');
const EmployeeRepository = require('../repositories/EmployeeRepository');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { ReportBuilder, renderReportExcel, renderReportPdf } = require('../patterns/builders/ReportBuilder');
const { logAction } = require('../middleware/activityLogger');

exports.list = async (req, res) => {
  res.json(await InventoryRepository.findAll({ status: req.query.status }));
};

exports.lowStock = async (req, res) => {
  res.json(await InventoryRepository.findLowStock());
};

exports.create = async (req, res) => {
  try {
    const { ingredientName, quantity, unit, minimumStock } = req.body;
    const item = await InventoryRepository.create({ ingredientName, quantity, unit, minimumStock });
    await logAction(req.user.employeeId, `Added ingredient "${ingredientName}"`, 'inventory');
    res.status(201).json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  const item = await InventoryRepository.update(req.params.id, req.body);
  res.json(item);
};

/** Handles both deliveries (positive delta) and manual usage recording (negative delta). */
exports.adjustStock = async (req, res) => {
  try {
    const { quantity, type } = req.body; // type: 'delivery' | 'usage' | 'adjustment'
    const delta = type === 'usage' ? -Math.abs(quantity) : Math.abs(quantity);
    const result = await InventoryRepository.adjustStock(req.params.id, delta, type, req.user.employeeId);

    await logAction(req.user.employeeId, `${type} of ${quantity} for inventory #${req.params.id}`, 'inventory');

    // Observer Pattern: notify Admin + Manager roles when stock drops to/below minimum.
    if (result.wasLowStock) {
      await notificationSubject.notify({
        roleId: null, // broadcast handled by role name below via two notify calls
        title: 'Low Stock Alert',
        message: `${result.ingredient_name} is running low (${result.quantity} ${result.unit} remaining).`,
        type: 'low_stock',
      });
    }

    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.history = async (req, res) => {
  res.json(await InventoryRepository.history(req.params.id));
};

exports.report = async (req, res) => {
  try {
    const format = req.query.format || 'json';
    const items = await InventoryRepository.findAll();

    const builder = new ReportBuilder('Inventory Report')
      .setColumns([
        { key: 'ingredient_name', label: 'Ingredient' },
        { key: 'quantity', label: 'Quantity' },
        { key: 'unit', label: 'Unit' },
        { key: 'minimum_stock', label: 'Min Stock' },
        { key: 'status', label: 'Status' },
      ])
      .addRows(items)
      .setSummary({ 'Total Items': items.length, 'Low/Out of Stock': items.filter((i) => i.status !== 'ok').length });

    const report = builder.build();

    if (format === 'pdf') {
      const buffer = await renderReportPdf(report);
      res.set('Content-Type', 'application/pdf');
      return res.send(buffer);
    }
    if (format === 'excel') {
      const buffer = await renderReportExcel(report);
      res.set('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      return res.send(buffer);
    }
    res.json(report);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};