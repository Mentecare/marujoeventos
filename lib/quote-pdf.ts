import PDFDocument from 'pdfkit';
import path from 'node:path';
import { openSync } from 'fontkit';
const regularFont=path.join(process.cwd(),'lib/fonts/DejaVuSans.ttf');
const boldFont=path.join(process.cwd(),'lib/fonts/DejaVuSans-Bold.ttf');
const fonts=[openSync(regularFont),openSync(boldFont)];
function displayText(value:string):string {
 const text=value.normalize('NFC');
 for(const char of text) {
  if (/\s/u.test(char)) continue;
  if(fonts.some(font=>!font.hasGlyphForCodePoint(char.codePointAt(0)!))) throw new Error('unsupported_pdf_text');
 }
 return text;
}
import type { SaleQuoteDTO } from './commercial.ts';

export type QuotePdfDetails = 'totals' | 'units';
export type QuotePdfOptions = { details?: QuotePdfDetails; issuerLogo?: Buffer | null };

const MARGIN = 48;
const WIDTH = 595.28 - MARGIN * 2;
const BOTTOM = 775;
const numberFormat = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const money = (value: number) => `R$ ${numberFormat.format(value)}`;
function date(value: string | null | undefined): string {
  if (!value) return 'Não informada';
  const parsed = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T12:00:00-03:00`) : new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
}

/** Measured lines, including unbroken identifiers; no approximate glyph widths. */
function lines(doc: PDFKit.PDFDocument, value: string, width: number, size: number, bold = false): string[] {
  doc.font(bold ? 'EventCoreBold' : 'EventCoreRegular').fontSize(size);
  const result: string[] = [];
  let current = '';
  for (const word of value.replace(/\s+/g, ' ').trim().split(' ')) {
    const candidate = current ? `${current} ${word}` : word;
    if (doc.widthOfString(candidate) <= width) { current = candidate; continue; }
    if (current) result.push(current);
    current = '';
    for (const char of word) {
      if (current && doc.widthOfString(current + char) > width) { result.push(current); current = ''; }
      current += char;
    }
  }
  if (current) result.push(current);
  return result.length ? result : [''];
}

export async function renderQuotePdf(quote: SaleQuoteDTO, options: QuotePdfOptions = {}): Promise<Buffer> {
  // Validate every displayed value before exporting any commercial document.
  quote={...quote,title:displayText(quote.title),venue:quote.venue?displayText(quote.venue):null,payment_terms:quote.payment_terms?displayText(quote.payment_terms):null,issuer:{...quote.issuer,display_name:displayText(quote.issuer.display_name)},client:{...quote.client,display_name:displayText(quote.client.display_name)},items:quote.items.map(i=>({...i,label:displayText(i.label)}))};
  const showUnits = (options.details ?? (quote.show_unit_prices ? 'units' : 'totals')) === 'units' && quote.show_unit_prices;
  const doc = new PDFDocument({ size: 'A4', margins: { top: MARGIN, bottom: 62, left: MARGIN, right: MARGIN }, bufferPages: true, info: { Title: quote.title, Author: 'EventCore', Creator: 'EventCore' } });
  doc.registerFont('EventCoreRegular',regularFont);
  doc.registerFont('EventCoreBold',boldFont);
  const chunks: Buffer[] = [];
  const result = new Promise<Buffer>((resolve, reject) => {
    doc.on('data', chunk => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });
  let y = MARGIN;
  function page() { doc.addPage(); y = MARGIN; }
  function ensure(height: number) { if (y + height > BOTTOM) page(); }
  function text(value: string, x: number, top: number, size = 9.5, bold = false, gray = '#29342f') {
    doc.font(bold ? 'EventCoreBold' : 'EventCoreRegular').fontSize(size).fillColor(gray).text(value, x, top, { lineBreak: false });
  }
  function wrapped(value: string, size = 9.5, bold = false, x = MARGIN, width = WIDTH, gray = '#29342f') {
    const height = size * 1.35;
    for (const line of lines(doc, value, width, size, bold)) { ensure(height); text(line, x, y, size, bold, gray); y += height; }
  }
  function label(labelText: string, value: string) {
    ensure(30);
    wrapped(labelText, 7.5, true, MARGIN, WIDTH, '#65716a');
    wrapped(value);
    y += 7;
  }
  function rule(top: number) { doc.moveTo(MARGIN, top).lineTo(MARGIN + WIDTH, top).lineWidth(0.6).strokeColor('#d6dcd8').stroke(); }

  // Only trusted decoded image bytes enter the renderer. Absent images use a
  // neutral EventCore mark plus the issuer's full name, without a fake logo.
  if (options.issuerLogo) doc.image(options.issuerLogo, MARGIN, y, { fit: [44, 44], align: 'center', valign: 'center' });
  else {
    doc.roundedRect(MARGIN, y, 44, 44, 6).fill('#e9efec');
    text('EC', MARGIN + 9, y + 12, 19, true, '#527563');
  }
  const brandTop = y;
  wrapped(quote.issuer.display_name, 14, true, MARGIN + 58, WIDTH - 58);
  y = Math.max(y, brandTop + 28);
  wrapped('Orçamento de venda', 9, false, MARGIN + 58, WIDTH - 58, '#65716a');
  y = Math.max(y + 14, brandTop + 62);
  wrapped(quote.title, 20, true);
  y += 5;
  wrapped('Documento comercial com preços de venda e condições da contratação.', 9, false, MARGIN, WIDTH, '#65716a');
  y += 16;
  label('Emitente', quote.issuer.display_name);
  label('Cliente', quote.client.display_name);
  // Short fixed date values share one measured row. Unbounded names/local do not.
  ensure(36);
  const dateTop = y;
  for (const [index, [key, value]] of [['Emissão', date(quote.issued_at)], ['Validade', date(quote.valid_until)], ['Data do evento', date(quote.event_date)]].entries()) {
    const x = MARGIN + index * (WIDTH / 3);
    text(key, x, dateTop, 7.5, true, '#65716a');
    text(value, x, dateTop + 12, 9.5);
  }
  y += 35;
  label('Local', quote.venue || 'Não informado');
  rule(y); y += 14;
  ensure(55);
  wrapped('Serviços e funções', 12, true); y += 8;

  const columns = showUnits
    ? [{ label: 'Serviço / função', width: WIDTH - 313 }, { label: 'Qtd.', width: 36 }, { label: 'Dias', width: 35 }, { label: 'Horas', width: 40 }, { label: 'Unitário', width: 100 }, { label: 'Total', width: 102 }]
    : [{ label: 'Serviço / função', width: WIDTH - 213 }, { label: 'Qtd.', width: 36 }, { label: 'Dias', width: 35 }, { label: 'Horas', width: 40 }, { label: 'Total', width: 102 }];
  function tableHeader() {
    ensure(40);
    doc.rect(MARGIN, y, WIDTH, 25).fill('#eef2ef');
    let x = MARGIN;
    for (const column of columns) { text(column.label, x + 6, y + 8, 7.7, true, '#56625a'); x += column.width; }
    y += 25;
  }
  tableHeader();
  for (const [itemIndex, item] of quote.items.entries()) {
    const rowLines = lines(doc, item.label, columns[0].width - 12, 8.7);
    const wholeRowHeight = Math.max(28, rowLines.length * 12 + 14);
    if (wholeRowHeight <= BOTTOM - MARGIN - 25 && y + wholeRowHeight > BOTTOM) { page(); tableHeader(); }
    let offset = 0;
    // A single unusually long description can span pages. Continue its text,
    // repeat the column headings, and show its amounts exactly once.
    while (offset < rowLines.length) {
      if (BOTTOM - y < 29) { page(); tableHeader(); }
      const count = Math.min(rowLines.length - offset, Math.floor((BOTTOM - y - 14) / 12));
      const rowHeight = Math.max(28, count * 12 + 14);
      if (itemIndex % 2 === 0) doc.rect(MARGIN, y, WIDTH, rowHeight).fill('#f8faf8');
      let x = MARGIN;
      for (let index = 0; index < count; index++) text(rowLines[offset + index], x + 6, y + 7 + index * 12, 8.7);
      x += columns[0].width;
      const values = [String(item.quantity), String(item.contract_days), item.planned_hours == null ? '-' : String(item.planned_hours), ...(showUnits ? [money(item.client_unit_price)] : []), money(item.line_total)];
      for (const [index, value] of values.entries()) {
        const width = columns[index + 1].width - 12;
        const cell = offset === 0 ? value : '-';
        const bold = index === values.length - 1;
        doc.font(bold ? 'EventCoreBold' : 'EventCoreRegular').fontSize(8.2);
        const size = Math.min(8.2, 8.2 * width / Math.max(width, doc.widthOfString(cell)));
        text(cell, x + 6, y + 7, size, bold);
        x += columns[index + 1].width;
      }
      y += rowHeight; rule(y);
      offset += count;
      if (offset < rowLines.length) { page(); tableHeader(); }
    }
  }
  y += 16;
  ensure(77);
  doc.rect(MARGIN + WIDTH - 220, y, 220, 54).fill('#eef2ef');
  text('Total de venda', MARGIN + WIDTH - 208, y + 9, 9, true, '#56625a');
  text(money(quote.client_total), MARGIN + WIDTH - 208, y + 28, 14, true);
  y += 73;
  ensure(34);
  wrapped('Condições de pagamento', 11, true); y += 4;
  wrapped(quote.payment_terms || 'Não informadas'); y += 9;
  wrapped('Os valores acima representam a venda ao cliente e permanecem sujeitos à validade informada. Outras despesas e impostos permanecem fora deste total.', 8.5, false, MARGIN, WIDTH, '#65716a');

  const range = doc.bufferedPageRange();
  for (let index = 0; index < range.count; index++) {
    doc.switchToPage(index);
    doc.save().fillOpacity(0.075).rotate(-35, { origin: [190, 475] });
    text('EventCore', 190, 475, 50, true, '#527563');
    doc.restore();
    rule(793);
    const footer = 'Orçamento emitido pelo EventCore · https://eventcore.space';
    text(footer, MARGIN, 804, 8, false, '#65716a');
    doc.link(MARGIN, 804, doc.widthOfString(footer), 10, 'https://eventcore.space');
    const pageText = `Página ${index + 1} de ${range.count}`;
    doc.font('EventCoreRegular').fontSize(8);
    text(pageText, MARGIN + WIDTH - doc.widthOfString(pageText), 804, 8, false, '#65716a');
  }
  doc.end();
  return result;
}
