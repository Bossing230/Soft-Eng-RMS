const OrderRepository = require('../repositories/OrderRepository');
const MenuRepository = require('../repositories/MenuRepository');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { logAction } = require('../middleware/activityLogger');

const VALID_TRANSITIONS = {
  pending: ['confirmed', 'cancelled'],
  confirmed: ['preparing', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['completed'],
  completed: [],
  cancelled: [],
};

exports.list = async (req, res) => {
  const { status, date } = req.query;
  res.json(await OrderRepository.findAll({ status, date }));
};

exports.getOne = async (req, res) => {
  const order = await OrderRepository.findById(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  res.json(order);
};

exports.kitchenQueue = async (req, res) => {
  res.json(await OrderRepository.findKitchenQueue());
};

exports.create = async (req, res) => {
  try {
    const { tableId, items, discount } = req.body; // items: [{ menuId, quantity }]
    if (!items || !items.length) return res.status(400).json({ error: 'Order must contain at least one item' });

    const enrichedItems = [];
    for (const i of items) {
      const menuItem = await MenuRepository.findById(i.menuId);
      if (!menuItem) return res.status(400).json({ error: `Menu item ${i.menuId} not found` });
      if (menuItem.availability !== 'available') return res.status(400).json({ error: `${menuItem.food_name} is currently unavailable` });
      enrichedItems.push({ menuId: i.menuId, quantity: i.quantity, unitPrice: parseFloat(menuItem.price) });
    }

    const order = await OrderRepository.create({ tableId, employeeId: req.user.employeeId, items: enrichedItems, discount: discount || 0 });
    await logAction(req.user.employeeId, `Created order #${order.order_id}`, 'orders');

    res.status(201).json(order);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.updateStatus = async (req, res) => {
  try {
    const { status } = req.body;
    const order = await OrderRepository.findById(req.params.id);
    if (!order) return res.status(404).json({ error: 'Order not found' });

    const allowed = VALID_TRANSITIONS[order.order_status] || [];
    if (!allowed.includes(status)) {
      return res.status(400).json({ error: `Cannot move order from ${order.order_status} to ${status}` });
    }

    const updated = await OrderRepository.updateStatus(req.params.id, status);
    await logAction(req.user.employeeId, `Order #${req.params.id} -> ${status}`, 'orders');

    const messages = {
      confirmed: 'Order confirmed and sent to kitchen.',
      preparing: 'Kitchen has started preparing the order.',
      ready: 'Order is ready to serve!',
      completed: 'Order completed.',
      cancelled: 'Order was cancelled.',
    };
    await notificationSubject.notify({
      title: `Order #${req.params.id} — ${status}`,
      message: messages[status] || `Order status changed to ${status}`,
      type: 'order_status',
    });

    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.cancel = async (req, res) => {
  // Managers/Admins can force-cancel regardless of current status (except completed).
  const order = await OrderRepository.findById(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (order.order_status === 'completed') return res.status(400).json({ error: 'Cannot cancel a completed order' });

  const updated = await OrderRepository.updateStatus(req.params.id, 'cancelled');
  await logAction(req.user.employeeId, `Force-cancelled order #${req.params.id}`, 'orders');
  res.json(updated);
};