const OrderRepository = require('../repositories/OrderRepository');
const InventoryRepository = require('../repositories/InventoryRepository');
const db = require('../patterns/singletons/DatabaseManager');
const { ReportBuilder, renderReportExcel, renderReportPdf } = require('../patterns/builders/ReportBuilder');

function dateRange(req) {
  const today = new Date().toISOString().slice(0, 10);
  return { start: req.query.start || today, end: req.query.end || today };
}

exports.salesReport = async (req, res) => {
  try {
    const { start, end } = dateRange(req);
    const rows = await OrderRepository.salesSummary(start, end);
    const builder = new ReportBuilder(`Sales Report (${start} to ${end})`)
      .setColumns([{ key: 'day', label: 'Date' }, { key: 'order_count', label: 'Orders' }, { key: 'total_sales', label: 'Total Sales' }])
      .addRows(rows)
      .setSummary({
        'Total Orders': rows.reduce((s, r) => s + r.order_count, 0),
        'Total Sales': rows.reduce((s, r) => s + parseFloat(r.total_sales), 0).toFixed(2),
      });

    await sendReport(res, builder.build(), req.query.format);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.bestSellers = async (req, res) => {
  const { start, end } = dateRange(req);
  const rows = await OrderRepository.bestSellers(start, end, Number(req.query.limit) || 10);
  const builder = new ReportBuilder(`Best Selling Items (${start} to ${end})`)
    .setColumns([{ key: 'food_name', label: 'Item' }, { key: 'total_sold', label: 'Qty Sold' }, { key: 'total_revenue', label: 'Revenue' }])
    .addRows(rows);
  await sendReport(res, builder.build(), req.query.format);
};

exports.inventoryReport = async (req, res) => {
  const items = await InventoryRepository.findAll();
  const builder = new ReportBuilder('Inventory Report')
    .setColumns([
      { key: 'ingredient_name', label: 'Ingredient' }, { key: 'quantity', label: 'Qty' },
      { key: 'unit', label: 'Unit' }, { key: 'status', label: 'Status' },
    ])
    .addRows(items);
  await sendReport(res, builder.build(), req.query.format);
};

exports.dashboardSummary = async (req, res) => {
  try {
    const role = req.user.role;
    const today = new Date().toISOString().slice(0, 10);

    const [todaySales] = await db.query(
      `SELECT COUNT(*) AS order_count, COALESCE(SUM(total_amount),0) AS total FROM orders WHERE order_status='completed' AND DATE(order_date)=?`,
      [today]
    );
    const [pendingOrders] = await db.query(`SELECT COUNT(*) AS count FROM orders WHERE order_status IN ('pending','confirmed','preparing')`);
    const [activeReservations] = await db.query(`SELECT COUNT(*) AS count FROM reservations WHERE status IN ('pending','confirmed') AND reservation_date >= CURDATE()`);
    const lowStock = await InventoryRepository.findLowStock();

    const summary = {
      todayOrders: todaySales.order_count,
      todaySales: todaySales.total,
      pendingOrders: pendingOrders.count,
      activeReservations: activeReservations.count,
      lowStockCount: lowStock.length,
    };

    if (role === 'administrator') {
      const [employeeCount] = await db.query(`SELECT COUNT(*) AS count FROM employees WHERE status='active'`);
      const [totalOrders] = await db.query(`SELECT COUNT(*) AS count, COALESCE(SUM(total_amount),0) AS revenue FROM orders WHERE order_status='completed'`);
      summary.totalEmployees = employeeCount.count;
      summary.totalOrders = totalOrders.count;
      summary.totalRevenue = totalOrders.revenue;
    }

    res.json(summary);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.staffPerformance = async (req, res) => {
  try {
    const date = req.query.date || new Date().toISOString().slice(0, 10);
    const rows = await OrderRepository.staffPerformance(date);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

async function sendReport(res, report, format) {
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
}