const OrderRepository = require('../repositories/OrderRepository');
const InventoryRepository = require('../repositories/InventoryRepository');
const db = require('../patterns/singletons/DatabaseManager');
const { ReportBuilder, renderReportExcel, renderReportPdf } = require('../patterns/builders/ReportBuilder');
const { SHIFT_MAX_HOURS } = require('./attendanceController');

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
  try {
    const { start, end } = dateRange(req);
    const rows = await OrderRepository.bestSellers(start, end, Number(req.query.limit) || 10);
    const builder = new ReportBuilder(`Best Selling Items (${start} to ${end})`)
      .setColumns([{ key: 'food_name', label: 'Item' }, { key: 'total_sold', label: 'Qty Sold' }, { key: 'total_revenue', label: 'Revenue' }])
      .addRows(rows);
    await sendReport(res, builder.build(), req.query.format);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
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

// ---------------------------------------------------------------------------
// Manager overview: one call that feeds the whole manager dashboard.
// "Today" always means CURDATE() in the database's time zone, so every number
// on the page uses the same day boundary.
// ---------------------------------------------------------------------------
const LOW_STOCK_ALERTS_SHOWN = 3; // extra low-stock items are rolled into one line
const PEAK_MIN_ORDERS = 20;       // never call it a "peak" below this many orders
const PEAK_FACTOR = 1.25;         // peak = today is 25%+ above the recent daily average
const SEVERITY_ORDER = { critical: 0, warning: 1, info: 2 };

// Front-of-house and kitchen staff with today's order activity and, when the
// attendance table exists, whether they are on duty, on break or off.
function staffQuery(withAttendance) {
  const presence = withAttendance
    ? `CASE WHEN a.attendance_id IS NULL THEN 'off'
            WHEN a.break_started_at IS NOT NULL THEN 'on_break'
            ELSE 'on_duty' END`
    : `'off'`;
  const attendanceJoin = withAttendance
    ? `LEFT JOIN attendance a
         ON a.attendance_id = (
              SELECT MAX(x.attendance_id) FROM attendance x
               WHERE x.employee_id = e.employee_id
                 AND x.clock_out IS NULL
                 AND x.clock_in >= DATE_SUB(NOW(), INTERVAL ${SHIFT_MAX_HOURS} HOUR))`
    : '';
  return `SELECT e.employee_id, e.name, r.role_name,
                ${presence} AS presence,
                COALESCE(s.order_count, 0) AS order_count,
                COALESCE(s.total_sales, 0) AS total_sales
           FROM employees e
           JOIN roles r ON r.role_id = e.role_id
           ${attendanceJoin}
           LEFT JOIN (
                  SELECT employee_id,
                         COUNT(*) AS order_count,
                         COALESCE(SUM(CASE WHEN order_status = 'completed' THEN total_amount END), 0) AS total_sales
                    FROM orders
                   WHERE DATE(order_date) = CURDATE() AND order_status <> 'cancelled'
                   GROUP BY employee_id) s
             ON s.employee_id = e.employee_id
          WHERE e.status = 'active' AND r.role_name IN ('cashier', 'kitchen')`;
}

// If the attendance table hasn't been created on this database yet, the
// dashboard still loads: everyone shows as off duty and the server log says
// which database is missing the table.
async function loadStaffRows() {
  try {
    return { rows: await db.query(staffQuery(true)), attendanceReady: true };
  } catch (err) {
    if (err.code !== 'ER_NO_SUCH_TABLE' && err.errno !== 1146) throw err;
    console.warn(
      `[manager-overview] "attendance" table not found on ${process.env.DB_HOST || 'localhost'} / ` +
        `${process.env.DB_NAME || 'rms_db'}. Run: node database/create-attendance-table.js`
    );
    return { rows: await db.query(staffQuery(false)), attendanceReady: false };
  }
}

exports.managerOverview = async (req, res) => {
  try {
    const [{ today }] = await db.query(`SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d') AS today`);

    const [
      [todayRow],
      [yesterdayRow],
      trendRows,
      topItems,
      [avgRow],
      staffResult,
      lowStock,
    ] = await Promise.all([
      // Sales count completed orders; "orders" is everything that wasn't cancelled.
      db.query(
        `SELECT
           COALESCE(SUM(CASE WHEN order_status = 'completed' THEN total_amount END), 0) AS sales,
           COALESCE(SUM(order_status <> 'cancelled'), 0) AS orders
         FROM orders
         WHERE DATE(order_date) = CURDATE()`
      ),
      db.query(
        `SELECT COALESCE(SUM(total_amount), 0) AS sales
           FROM orders
          WHERE order_status = 'completed'
            AND DATE(order_date) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)`
      ),
      db.query(
        `SELECT DATE_FORMAT(order_date, '%Y-%m-%d') AS day, COALESCE(SUM(total_amount), 0) AS total_sales
           FROM orders
          WHERE order_status = 'completed'
            AND DATE(order_date) >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
          GROUP BY day`
      ),
      db.query(
        `SELECT m.food_name, SUM(oi.quantity) AS total_sold
           FROM order_items oi
           JOIN orders o ON o.order_id = oi.order_id
           JOIN menu_items m ON m.menu_id = oi.menu_id
          WHERE o.order_status = 'completed'
            AND DATE(o.order_date) >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
          GROUP BY m.menu_id, m.food_name
          ORDER BY total_sold DESC
          LIMIT 5`
      ),
      db.query(
        `SELECT COUNT(*) / 7 AS avg_orders
           FROM orders
          WHERE order_status <> 'cancelled'
            AND DATE(order_date) BETWEEN DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND DATE_SUB(CURDATE(), INTERVAL 1 DAY)`
      ),
      loadStaffRows(),
      InventoryRepository.findLowStock(),
    ]);

    const { rows: staffRows, attendanceReady } = staffResult;

    // ---- Today vs yesterday ----
    const sales = Number(todayRow.sales);
    const orders = Number(todayRow.orders);
    const yesterdaySales = Number(yesterdayRow.sales);
    const salesChangePct = yesterdaySales > 0 ? Math.round(((sales - yesterdaySales) / yesterdaySales) * 100) : null;

    // ---- 7-day trend, one point per day (days with no sales are 0) ----
    const byDay = new Map(trendRows.map((r) => [r.day, Number(r.total_sales)]));
    const base = new Date(`${today}T00:00:00Z`);
    const trend = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(base);
      d.setUTCDate(d.getUTCDate() - i);
      const day = d.toISOString().slice(0, 10);
      trend.push({ day, total_sales: byDay.get(day) || 0 });
    }

    // ---- Staff ----
    const staffActivity = staffRows
      .map((r) => ({
        employee_id: r.employee_id,
        name: r.name,
        role_name: r.role_name,
        presence: r.presence,
        order_count: Number(r.order_count),
        total_sales: Number(r.total_sales),
      }))
      .sort(
        (a, b) =>
          Number(a.presence === 'off') - Number(b.presence === 'off') ||
          b.total_sales - a.total_sales ||
          a.name.localeCompare(b.name)
      );

    const staff = {
      onDuty: staffActivity.filter((s) => s.presence === 'on_duty').length,
      onBreak: staffActivity.filter((s) => s.presence === 'on_break').length,
      total: staffActivity.length,
    };

    // ---- Alerts ----
    const alerts = [];

    lowStock.slice(0, LOW_STOCK_ALERTS_SHOWN).forEach((item) => {
      const isOut = item.status === 'out' || Number(item.quantity) <= 0;
      alerts.push({
        type: isOut ? 'out_of_stock' : 'low_stock',
        severity: 'critical',
        title: `${isOut ? 'Out of stock' : 'Low stock'}: ${item.ingredient_name}`,
        message: isOut ? 'None remaining' : `${Number(item.quantity)} ${item.unit} remaining`,
      });
    });
    if (lowStock.length > LOW_STOCK_ALERTS_SHOWN) {
      const extra = lowStock.length - LOW_STOCK_ALERTS_SHOWN;
      alerts.push({
        type: 'low_stock_more',
        severity: 'warning',
        title: `${extra} more low-stock ${extra === 1 ? 'item' : 'items'}`,
        message: 'Open Inventory to see the full list',
      });
    }

    const avgOrders = Number(avgRow.avg_orders);
    if (orders >= PEAK_MIN_ORDERS && orders >= avgOrders * PEAK_FACTOR) {
      alerts.push({
        type: 'peak_volume',
        severity: 'warning',
        title: 'Peak volume alert',
        message: `${orders} orders today`,
      });
    }

    if (staff.onBreak > 0) {
      const kitchenOnBreak = staffActivity.some((s) => s.presence === 'on_break' && s.role_name === 'kitchen');
      alerts.push({
        type: 'staff_break',
        severity: 'info',
        title: `${staff.onBreak} staff on break`,
        message: kitchenOnBreak ? 'Kitchen coverage may be reduced' : 'Front counter coverage may be reduced',
      });
    }

    alerts.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);

    res.json({
      today: { sales, orders, salesChangePct },
      staff,
      attendanceReady,
      lowStockCount: lowStock.length,
      trend,
      topItems: topItems.map((r) => ({ food_name: r.food_name, total_sold: Number(r.total_sold) })),
      staffActivity,
      alerts,
    });
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