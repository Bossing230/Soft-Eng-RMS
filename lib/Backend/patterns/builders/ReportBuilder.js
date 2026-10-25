/**
 * Builder Pattern — assembles a tabular report (sales, inventory,
 * reservations, etc.) that can then be exported to Excel, PDF or CSV.
 *
 * Columns: [{ key, label, type?, width? }]
 *   type  : 'text' (default) | 'number' | 'money' | 'date'. Controls alignment
 *           and number formatting.
 *   width : relative weight of the column in the PDF / Excel (default 1).
 * A row may carry `_highlight: 'low' | 'critical' | 'out'` to be shaded.
 * Fields that are not listed in `columns` (like _highlight) are never printed.
 */

const ExcelJS = require('exceljs');

const TZ_OFFSET_HOURS = Number(process.env.REPORT_TZ_OFFSET_HOURS) || 0;

class ReportBuilder {
  constructor(title) {
    this.report = { title, subtitle: '', generatedAt: new Date().toISOString(), columns: [], rows: [], summary: {} };
  }

  setSubtitle(subtitle) {
    this.report.subtitle = subtitle;
    return this;
  }

  setColumns(columns) {
    this.report.columns = columns;
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

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const HIGHLIGHT_ARGB = { out: 'FFFFCDD2', critical: 'FFFFEBEE', low: 'FFFFF4D6' };
const HIGHLIGHT_HEX = { out: '#FFCDD2', critical: '#FFEBEE', low: '#FFF4D6' };

const isNumeric = (c) => c.type === 'number' || c.type === 'money';

function localStamp(iso) {
  const shifted = new Date(new Date(iso).getTime() + TZ_OFFSET_HOURS * 3600000).toISOString();
  return `${shifted.slice(0, 10)} ${shifted.slice(11, 16)}`;
}

/** Text shown in the PDF. The standard PDF font has no peso sign, so money is written as "PHP". */
function formatCell(value, type) {
  if (value === null || value === undefined || value === '') return '';
  const n = Number(value);
  if (type === 'money' && Number.isFinite(n)) {
    return `PHP ${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }
  if (type === 'number' && Number.isFinite(n)) {
    return n.toLocaleString('en-US', { maximumFractionDigits: 2 });
  }
  return String(value);
}

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

async function renderReportExcel(report) {
  const workbook = new ExcelJS.Workbook();
  workbook.created = new Date();
  const name = String(report.title).replace(/[\\/*?:[\]]/g, '').substring(0, 30) || 'Report';
  const sheet = workbook.addWorksheet(name);

  const cols = report.columns;
  const n = Math.max(cols.length, 1);
  sheet.columns = cols.map((c) => ({ key: c.key, width: Math.max(12, Math.round((c.width || 1) * 12) + 2) }));

  let r = 1;
  const writeLine = (text, font) => {
    sheet.mergeCells(r, 1, r, n);
    const cell = sheet.getCell(r, 1);
    cell.value = text;
    cell.font = font;
    r += 1;
  };

  writeLine(report.title, { bold: true, size: 16 });
  const meta = [report.subtitle, `Generated ${localStamp(report.generatedAt)}`].filter(Boolean).join('   |   ');
  writeLine(meta, { size: 10, color: { argb: 'FF7A7A7A' } });
  Object.entries(report.summary || {}).forEach(([k, v]) => writeLine(`${k}: ${v}`, { size: 11 }));
  r += 1;

  const headerRow = r;
  cols.forEach((c, i) => {
    const cell = sheet.getCell(headerRow, i + 1);
    cell.value = c.label;
    cell.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFB98A5E' } };
    cell.alignment = { vertical: 'middle', horizontal: isNumeric(c) ? 'right' : 'left' };
  });
  r += 1;

  report.rows.forEach((row) => {
    cols.forEach((c, i) => {
      const cell = sheet.getCell(r, i + 1);
      const v = row[c.key];
      if (v === undefined || v === null || v === '') {
        cell.value = null;
      } else if (isNumeric(c) && Number.isFinite(Number(v))) {
        cell.value = Number(v);
      } else {
        cell.value = v;
      }
      if (c.type === 'money') cell.numFmt = '"₱"#,##0.00';
      else if (c.type === 'number' && typeof cell.value === 'number') cell.numFmt = '#,##0.##';
      if (isNumeric(c)) cell.alignment = { horizontal: 'right' };
      if (row._highlight && HIGHLIGHT_ARGB[row._highlight]) {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: HIGHLIGHT_ARGB[row._highlight] } };
      }
    });
    r += 1;
  });

  if (report.rows.length) {
    sheet.autoFilter = { from: { row: headerRow, column: 1 }, to: { row: r - 1, column: n } };
  }
  sheet.views = [{ state: 'frozen', ySplit: headerRow }];
  sheet.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0 };

  return Buffer.from(await workbook.xlsx.writeBuffer());
}

// ---------------------------------------------------------------------------
// CSV (plain data: header row + one line per item, opens directly in Excel)
// ---------------------------------------------------------------------------

function renderReportCsv(report) {
  const escape = (value, type) => {
    let s = value === null || value === undefined ? '' : String(value);
    // Stop spreadsheets from running a name like "=SUM(...)" as a formula.
    if (type !== 'number' && type !== 'money' && /^[=+\-@]/.test(s)) s = `'${s}`;
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };

  const lines = [report.columns.map((c) => escape(c.label, 'text')).join(',')];
  report.rows.forEach((row) => {
    lines.push(report.columns.map((c) => escape(row[c.key], c.type)).join(','));
  });

  // The BOM makes Excel read the file as UTF-8.
  return Buffer.from(`\uFEFF${lines.join('\r\n')}\r\n`, 'utf8');
}

// ---------------------------------------------------------------------------
// PDF (landscape A4, repeating header row, shaded rows, page numbers)
// ---------------------------------------------------------------------------

function drawPdf(doc, report) {
  const cols = report.columns;
  const left = 30;
  const usable = doc.page.width - 60;
  const totalWeight = cols.reduce((s, c) => s + (c.width || 1), 0) || 1;
  const widths = cols.map((c) => (usable * (c.width || 1)) / totalWeight);
  const xs = [];
  let acc = left;
  widths.forEach((w) => {
    xs.push(acc);
    acc += w;
  });
  const ROW_H = 20;
  const HEAD_H = 22;
  const BOTTOM = doc.page.height - 50;

  doc.font('Helvetica-Bold').fontSize(18).fillColor('#2B2B2B').text(report.title, left, 30, { width: usable });
  doc.font('Helvetica').fontSize(9).fillColor('#7A7A7A');
  const meta = [report.subtitle, `Generated ${localStamp(report.generatedAt)}`].filter(Boolean).join('   |   ');
  doc.text(meta, left, doc.y + 2, { width: usable });
  let y = doc.y + 10;

  const entries = Object.entries(report.summary || {});
  if (entries.length) {
    const perRow = Math.min(entries.length, 6);
    const gap = 10;
    const boxW = (usable - gap * (perRow - 1)) / perRow;
    entries.forEach(([k, v], i) => {
      const bx = left + (i % perRow) * (boxW + gap);
      const by = y + Math.floor(i / perRow) * 46;
      doc.roundedRect(bx, by, boxW, 38, 6).fill('#F6EFE7');
      doc.fillColor('#7A7A7A').font('Helvetica').fontSize(8)
        .text(String(k), bx + 8, by + 7, { width: boxW - 16, height: 10, ellipsis: true });
      doc.fillColor('#2B2B2B').font('Helvetica-Bold').fontSize(12)
        .text(String(v), bx + 8, by + 19, { width: boxW - 16, height: 14, ellipsis: true });
    });
    y += Math.ceil(entries.length / perRow) * 46 + 4;
  }

  const drawHeader = (top) => {
    doc.rect(left, top, usable, HEAD_H).fill('#B98A5E');
    doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(8);
    cols.forEach((c, i) => {
      doc.text(String(c.label).toUpperCase(), xs[i] + 5, top + 7, {
        width: widths[i] - 10,
        height: 10,
        ellipsis: true,
        align: isNumeric(c) ? 'right' : 'left',
      });
    });
    return top + HEAD_H;
  };

  y = drawHeader(y);

  if (!report.rows.length) {
    doc.fillColor('#7A7A7A').font('Helvetica').fontSize(10)
      .text('No items match this report.', left, y + 14, { width: usable, align: 'center' });
  }

  report.rows.forEach((row, idx) => {
    if (y + ROW_H > BOTTOM) {
      doc.addPage();
      y = drawHeader(30);
    }
    const shade = row._highlight && HIGHLIGHT_HEX[row._highlight] ? HIGHLIGHT_HEX[row._highlight] : idx % 2 ? '#FAF7F2' : null;
    if (shade) doc.rect(left, y, usable, ROW_H).fill(shade);

    doc.fillColor('#2B2B2B').font('Helvetica').fontSize(8);
    cols.forEach((c, i) => {
      doc.text(formatCell(row[c.key], c.type), xs[i] + 5, y + 6, {
        width: widths[i] - 10,
        height: 10,
        ellipsis: true,
        align: isNumeric(c) ? 'right' : 'left',
      });
    });
    doc.moveTo(left, y + ROW_H).lineTo(left + usable, y + ROW_H).lineWidth(0.5).strokeColor('#EBE3D8').stroke();
    y += ROW_H;
  });

  // Page numbers (written last, once the page count is known).
  const range = doc.bufferedPageRange();
  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);
    doc.page.margins.bottom = 0; // otherwise writing this low would add a blank page
    doc.font('Helvetica').fontSize(8).fillColor('#7A7A7A').text(
      `${report.title}  |  Page ${i - range.start + 1} of ${range.count}`,
      left,
      doc.page.height - 28,
      { width: usable, align: 'center', lineBreak: false }
    );
  }
}

function renderReportPdf(report) {
  const PDFDocument = require('pdfkit');
  const doc = new PDFDocument({ size: 'A4', layout: 'landscape', margin: 30, bufferPages: true });
  const chunks = [];

  return new Promise((resolve, reject) => {
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    try {
      drawPdf(doc, report);
      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

module.exports = { ReportBuilder, renderReportExcel, renderReportPdf, renderReportCsv };