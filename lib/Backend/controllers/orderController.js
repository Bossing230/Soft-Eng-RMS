const OrderRepository = require('../repositories/OrderRepository');
const MenuRepository = require('../repositories/MenuRepository');
const notifyRoles = require('../patterns/observers/notifyRoles');
const { logAction } = require('../middleware/activityLogger');

const ORDER_TYPES = ['dine_in', 'takeout', 'delivery'];
const MANAGERS = ['administrator', 'manager'];

/**
 * Who may move an order to which status.
 *   pending -> confirmed -> preparing -> ready -> served -> completed
 * Only managers and administrators can cancel (from any status before completed).
 * Ready -> completed stays allowed so orders that are not "served" at a table
 * (takeout, delivery) can be closed straight from Ready.
 */
const TRANSITIONS = {
  pending: { confirmed: [...MANAGERS, 'cashier'], cancelled: MANAGERS },
  confirmed: { preparing: [...MANAGERS, 'kitchen'], cancelled: MANAGERS },
  preparing: { ready: [...MANAGERS, 'kitchen'], cancelled: MANAGERS },
  ready: { served: [...MANAGERS, 'cashier'], completed: [...MANAGERS, 'cashier'], cancelled: MANAGERS },
  served: { completed: [...MANAGERS, 'cashier'], cancelled: MANAGERS },
  completed: {},
  cancelled: {},
};

/** The statuses this role may move an order to from its current status. */
function allowedNext(status, role) {
  return Object.entries(TRANSITIONS[status] || {})
    .filter(([, roles]) => roles.includes(role))
    .map(([next]) => next);
}

const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

exports.list = async (req, res) => {
  try {
    const { status, date, limit } = req.query;
    res.json(await OrderRepository.findAll({ status, date, limit }));
  } catch (err) {
    fail(res, err);
  }
};

/** Feeds the Orders page: today's orders plus anything still open. */
exports.board = async (req, res) => {
  try {
    const orders = await OrderRepository.findBoard();
    res.json(orders.map((o) => ({ ...o, allowed_next: allowedNext(o.order_status, req.user.role) })));
  } catch (err) {
    fail(res, err);
  }
};

exports.getOne = async (req, res) => {
  try {
    const order = await OrderRepository.findById(req.params.id);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    res.json(order);
  } catch (err) {
    fail(res, err);
  }
};

exports.kitchenQueue = async (req, res) => {
  try {
    res.json(await OrderRepository.findKitchenQueue());
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const { items } = req.body; // items: [{ menuId, quantity }]
    const orderType = req.body.orderType || 'dine_in';
    const discount = Number(req.body.discount) || 0;

    if (!ORDER_TYPES.includes(orderType)) {
      return res.status(400).json({ error: `orderType must be one of: ${ORDER_TYPES.join(', ')}` });
    }
    if (!Array.isArray(items) || !items.length) {
      return res.status(400).json({ error: 'Order must contain at least one item' });
    }
    if (discount < 0) return res.status(400).json({ error: 'Discount cannot be negative' });

    // Only dine-in orders sit at a table; the cashier can type "3" or "T3".
    let tableId = null;
    if (orderType === 'dine_in') {
      const wanted = typeof req.body.tableNumber === 'string' ? req.body.tableNumber.trim() : '';
      if (wanted) {
        const table = await OrderRepository.findTableByNumber(wanted);
        if (!table) return res.status(400).json({ error: `Table "${wanted}" does not exist` });
        tableId = table.table_id;
      } else if (req.body.tableId) {
        tableId = Number(req.body.tableId) || null; // older clients send an id
      }
    }

    const enrichedItems = [];
    for (const i of items) {
      const quantity = Number(i.quantity);
      if (!Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
        return res.status(400).json({ error: 'Each item needs a quantity between 1 and 99' });
      }
      const menuItem = await MenuRepository.findById(i.menuId);
      if (!menuItem) return res.status(400).json({ error: `Menu item ${i.menuId} not found` });
      if (menuItem.availability !== 'available') return res.status(400).json({ error: `${menuItem.food_name} is currently unavailable` });
      enrichedItems.push({ menuId: i.menuId, quantity, unitPrice: parseFloat(menuItem.price) });
    }

    const order = await OrderRepository.create({
      tableId,
      orderType,
      employeeId: req.user.employeeId,
      items: enrichedItems,
      discount,
    });
    await logAction(req.user.employeeId, `Created order #${order.order_id}`, 'orders');

    res.status(201).json(order);
  } catch (err) {
    fail(res, err);
  }
};

/** Tells the people who need to know, and only them. */
async function announce(orderId, previous, next) {
  switch (next) {
    case 'confirmed':
      return notifyRoles(['kitchen'], {
        title: `New order #${orderId}`,
        message: 'Confirmed and sent to the kitchen.',
        type: 'order_status',
      });
    case 'ready':
      return notifyRoles(['cashier', 'manager'], {
        title: `Order #${orderId} is ready`,
        message: 'Ready to serve.',
        type: 'order_status',
      });
    case 'cancelled': {
      // The kitchen only needs to hear about orders it already has.
      const roles = ['confirmed', 'preparing'].includes(previous) ? ['kitchen', 'cashier'] : ['cashier'];
      return notifyRoles(roles, {
        title: `Order #${orderId} was cancelled`,
        message: 'This order was cancelled.',
        type: 'order_status',
      });
    }
    default:
      return undefined;
  }
}

async function changeStatus(req, res, status) {
  const order = await OrderRepository.findById(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  const current = order.order_status;
  if (!allowedNext(current, req.user.role).includes(status)) {
    const legal = Object.keys(TRANSITIONS[current] || {}).includes(status);
    return res.status(legal ? 403 : 400).json({
      error: legal
        ? `Your role cannot move an order from ${current} to ${status}`
        : `Cannot move order from ${current} to ${status}`,
    });
  }

  const updated = await OrderRepository.updateStatus(req.params.id, status);
  await logAction(req.user.employeeId, `Order #${req.params.id} -> ${status}`, 'orders');
  await announce(order.order_id, current, status);

  return res.json({ ...updated, allowed_next: allowedNext(status, req.user.role) });
}

exports.updateStatus = async (req, res) => {
  try {
    const { status } = req.body;
    if (typeof status !== 'string' || !status) return res.status(400).json({ error: 'status is required' });
    return await changeStatus(req, res, status);
  } catch (err) {
    return fail(res, err);
  }
};

/** Managers and administrators only (see the route): cancels from any status before completed. */
exports.cancel = async (req, res) => {
  try {
    return await changeStatus(req, res, 'cancelled');
  } catch (err) {
    return fail(res, err);
  }
};