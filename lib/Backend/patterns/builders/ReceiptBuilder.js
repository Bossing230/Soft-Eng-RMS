/**
 * Builder Pattern — assembles a receipt (or report) object step by
 * step, then hands it to PDFKit for rendering. Keeps document
 * assembly logic out of the controllers.
 */
class ReceiptBuilder {
  constructor() {
    this.receipt = { header: {}, items: [], totals: {}, footer: {} };
  }

  setHeader({ restaurantName, address, contact }) {
    this.receipt.header = { restaurantName, address, contact };
    return this;
  }

  setOrderInfo({ orderId, tableNumber, date, cashierName }) {
    this.receipt.orderInfo = { orderId, tableNumber, date, cashierName };
    return this;
  }

  addItem({ name, quantity, unitPrice, subtotal }) {
    this.receipt.items.push({ name, quantity, unitPrice, subtotal });
    return this;
  }

  setTotals({ subtotal, discount, tax, serviceCharge, total }) {
    this.receipt.totals = { subtotal, discount, tax, serviceCharge, total };
    return this;
  }

  setPayment({ method, amountPaid, change, reference }) {
    this.receipt.payment = { method, amountPaid, change, reference };
    return this;
  }

  setFooter(message) {
    this.receipt.footer = { message };
    return this;
  }

  build() {
    return this.receipt;
  }
}

/**
 * Renders a built receipt (or a generic report object) to a PDF
 * buffer using pdfkit.
 */
function renderReceiptPdf(receipt) {
  const PDFDocument = require('pdfkit');
  const doc = new PDFDocument({ size: [226, 500], margin: 10 }); // 80mm receipt width
  const chunks = [];

  return new Promise((resolve, reject) => {
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fontSize(12).text(receipt.header.restaurantName || 'Restaurant', { align: 'center' });
    doc.fontSize(8).text(receipt.header.address || '', { align: 'center' });
    doc.moveDown();
    doc.text(`Order #${receipt.orderInfo?.orderId ?? ''}`);
    doc.text(`Table: ${receipt.orderInfo?.tableNumber ?? 'N/A'}`);
    doc.text(`Date: ${receipt.orderInfo?.date ?? ''}`);
    doc.text(`Cashier: ${receipt.orderInfo?.cashierName ?? ''}`);
    doc.moveDown();

    receipt.items.forEach((item) => {
      doc.text(`${item.quantity}x ${item.name}`);
      doc.text(`  ${item.unitPrice} = ${item.subtotal}`, { align: 'right' });
    });

    doc.moveDown();
    const t = receipt.totals;
    doc.text(`Subtotal: ${t.subtotal}`);
    if (t.discount) doc.text(`Discount: -${t.discount}`);
    if (t.tax) doc.text(`Tax: ${t.tax}`);
    if (t.serviceCharge) doc.text(`Service Charge: ${t.serviceCharge}`);
    doc.fontSize(11).text(`TOTAL: ${t.total}`, { underline: true });

    if (receipt.payment) {
      doc.moveDown();
      doc.fontSize(9).text(`Paid via: ${receipt.payment.method}`);
      if (receipt.payment.change !== undefined) doc.text(`Change: ${receipt.payment.change}`);
      doc.text(`Ref: ${receipt.payment.reference}`);
    }

    doc.moveDown();
    doc.fontSize(8).text(receipt.footer?.message || 'Thank you!', { align: 'center' });
    doc.end();
  });
}

module.exports = { ReceiptBuilder, renderReceiptPdf };