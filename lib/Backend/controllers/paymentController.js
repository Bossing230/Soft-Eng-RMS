const OrderRepository = require('../repositories/OrderRepository');
const PaymentRepository = require('../repositories/PaymentRepository');
const { PaymentContext } = require('../patterns/strategies/PaymentStrategy');
const { ReceiptBuilder, renderReceiptPdf } = require('../patterns/builders/ReceiptBuilder');
const ConfigManager = require('../patterns/singletons/ConfigManager');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { logAction } = require('../middleware/activityLogger');

exports.process = async (req, res) => {
  try {
    const { orderId, method, ...payload } = req.body;
    const order = await OrderRepository.findById(orderId);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.payment_status === 'paid') return res.status(400).json({ error: 'Order is already paid' });

    // Strategy Pattern: delegate to the right payment implementation.
    const strategy = PaymentContext.getStrategy(method);
    const result = await strategy.process(order, payload);

    const payment = await PaymentRepository.create({
      orderId,
      method: result.method,
      amount: result.amount,
      status: result.status,
      reference: result.transactionReference,
      processedBy: req.user.employeeId,
      change: result.change,
    });

    if (result.status === 'paid') {
      await OrderRepository.updatePaymentStatus(orderId, 'paid');
      await notificationSubject.notify({
        title: 'Payment Received',
        message: `Order #${orderId} paid via ${result.method} (${result.amount}).`,
        type: 'payment_confirmation',
      });
    }

    await logAction(req.user.employeeId, `Processed ${method} payment for order #${orderId}`, 'payments');

    res.status(201).json({ payment, checkoutUrl: result.checkoutUrl });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

/** Webhook endpoint PayMongo calls back to confirm/fail an e-wallet payment. */
exports.paymongoWebhook = async (req, res) => {
  try {
    const event = req.body?.data?.attributes?.type;
    const sourceId = req.body?.data?.attributes?.data?.id;
    if (!sourceId) return res.sendStatus(400);

    const status = event === 'source.chargeable' ? 'paid' : 'failed';
    // In production, look up the payment by transaction_reference = sourceId.
    res.sendStatus(200);
  } catch (err) {
    res.sendStatus(500);
  }
};

exports.receipt = async (req, res) => {
  try {
    const order = await OrderRepository.findById(req.params.orderId);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    const payments = await PaymentRepository.findByOrderId(order.order_id);
    const latestPayment = payments[0];

    const builder = new ReceiptBuilder()
      .setHeader({ restaurantName: ConfigManager.get('restaurantName'), address: '', contact: '' })
      .setOrderInfo({ orderId: order.order_id, tableNumber: order.table_number, date: order.order_date, cashierName: order.employee_name })
      .setTotals({ subtotal: order.subtotal, discount: order.discount, tax: order.tax, total: order.total_amount });

    order.items.forEach((item) => builder.addItem({ name: item.food_name, quantity: item.quantity, unitPrice: item.unit_price, subtotal: item.subtotal }));

    if (latestPayment) {
      builder.setPayment({ method: latestPayment.payment_method, amountPaid: latestPayment.amount, reference: latestPayment.transaction_reference });
    }
    builder.setFooter('Thank you for dining with us!');

    const receipt = builder.build();

    if (req.query.format === 'pdf') {
      const buffer = await renderReceiptPdf(receipt);
      res.set('Content-Type', 'application/pdf');
      return res.send(buffer);
    }
    res.json(receipt);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.list = async (req, res) => {
  const { status, date } = req.query;
  res.json(await PaymentRepository.findAll({ status, date }));
};