/**
 * Builder Pattern — assembles a tabular report (sales, inventory,
 * reservations, etc.) that can then be exported to Excel or PDF.
 */

const ExcelJS = require('exceljs');

class ReportBuilder {
  constructor(title) {
    this.report = { title, generatedAt: new Date().toISOString(), columns: [], rows: [], summary: {} };
  }

  setColumns(columns) {
    this.report.columns = columns; // [{ key, label }]
    return this;
  }

  addRow(row) {
    this.report.rows.push(row);
    return this;
  }

  addRows(rows) {
    this.report.rows.push(...rows);
    return this;
  }

  setSummary(summary) {
    this.report.summary = summary;
    return this;
  }

  build() {
    return this.report;
  }
}

async function renderReportExcel(report) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet(report.title.substring(0, 30));

  sheet.columns = report.columns.map((c) => ({ header: c.label, key: c.key, width: 20 }));
  sheet.getRow(1).font = { bold: true };
  report.rows.forEach((row) => sheet.addRow(row));

  if (Object.keys(report.summary).length) {
    sheet.addRow({});
    Object.entries(report.summary).forEach(([k, v]) => sheet.addRow({ [report.columns[0].key]: `${k}: ${v}` }));
  }

  return workbook.xlsx.writeBuffer();
}

function renderReportPdf(report) {
  const PDFDocument = require('pdfkit');
  const doc = new PDFDocument({ margin: 30 });
  const chunks = [];

  return new Promise((resolve, reject) => {
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fontSize(16).text(report.title, { align: 'center' });
    doc.fontSize(9).text(`Generated: ${report.generatedAt}`, { align: 'center' });
    doc.moveDown();

    const colWidth = 500 / report.columns.length;
    report.columns.forEach((c, i) => doc.fontSize(10).text(c.label, 30 + i * colWidth, doc.y, { width: colWidth, continued: i < report.columns.length - 1 }));
    doc.moveDown();

    report.rows.forEach((row) => {
      report.columns.forEach((c, i) => doc.fontSize(9).text(String(row[c.key] ?? ''), 30 + i * colWidth, doc.y, { width: colWidth, continued: i < report.columns.length - 1 }));
      doc.moveDown(0.5);
    });

    if (Object.keys(report.summary).length) {
      doc.moveDown();
      Object.entries(report.summary).forEach(([k, v]) => doc.fontSize(10).text(`${k}: ${v}`));
    }

    doc.end();
  });
}

module.exports = { ReportBuilder, renderReportExcel, renderReportPdf };