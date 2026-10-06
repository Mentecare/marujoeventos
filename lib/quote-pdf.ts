import type { SaleQuoteDTO } from './commercial.ts';

export type QuotePdfDetails = 'totals' | 'units';

export type QuotePdfOptions = {
  details?: QuotePdfDetails;
};

type PdfPage = {
  commands: string[];
};

const PAGE_WIDTH = 595.28;
const PAGE_HEIGHT = 841.89;
const MARGIN = 48;
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2;
const BOTTOM = 62;

const numberFormat = new Intl.NumberFormat('pt-BR', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

function money(value: number): string {
  return `R$ ${numberFormat.format(value)}`;
}

function date(value: string | null | undefined): string {
  if (!value) return 'Não informada';
  const parsed = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T12:00:00-03:00`) : new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
}

/**
 * The built-in PDF Type 1 fonts use WinAnsiEncoding. Keeping the encoder here
 * avoids loading untrusted font files or remote logos in a customer document,
 * while preserving the Portuguese characters used by EventCore.
 */
const WIN_ANSI: Record<string, number> = {
  '€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87,
  'ˆ': 0x88, '‰': 0x89, 'Š': 0x8a, '‹': 0x8b, 'Œ': 0x8c, 'Ž': 0x8e,
  '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97,
  '˜': 0x98, '™': 0x99, 'š': 0x9a, '›': 0x9b, 'œ': 0x9c, 'ž': 0x9e, 'Ÿ': 0x9f, '·': 0xb7,
  'À': 0xc0, 'Á': 0xc1, 'Â': 0xc2, 'Ã': 0xc3, 'Ä': 0xc4, 'Å': 0xc5, 'Ç': 0xc7,
  'È': 0xc8, 'É': 0xc9, 'Ê': 0xca, 'Ë': 0xcb, 'Ì': 0xcc, 'Í': 0xcd, 'Î': 0xce,
  'Ï': 0xcf, 'Ñ': 0xd1, 'Ò': 0xd2, 'Ó': 0xd3, 'Ô': 0xd4, 'Õ': 0xd5, 'Ö': 0xd6,
  'Ù': 0xd9, 'Ú': 0xda, 'Û': 0xdb, 'Ü': 0xdc, 'Ý': 0xdd, 'à': 0xe0, 'á': 0xe1,
  'â': 0xe2, 'ã': 0xe3, 'ä': 0xe4, 'å': 0xe5, 'ç': 0xe7, 'è': 0xe8, 'é': 0xe9,
  'ê': 0xea, 'ë': 0xeb, 'ì': 0xec, 'í': 0xed, 'î': 0xee, 'ï': 0xef, 'ñ': 0xf1,
  'ò': 0xf2, 'ó': 0xf3, 'ô': 0xf4, 'õ': 0xf5, 'ö': 0xf6, 'ù': 0xf9, 'ú': 0xfa,
  'û': 0xfb, 'ü': 0xfc, 'ý': 0xfd, 'ÿ': 0xff,
};

function winAnsi(value: string): string {
  let output = '';
  for (const character of value) {
    const code = character.codePointAt(0) ?? 0x3f;
    const byte = code <= 0x7f ? code : WIN_ANSI[character] ?? 0x3f;
    output += String.fromCharCode(byte);
  }
  return output;
}

function pdfString(value: string): string {
  return `(${winAnsi(value.replace(/[\r\n]+/g, ' ')).replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)')})`;
}

function pdfNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

function textWidth(value: string, size: number): number {
  // Helvetica's average glyph width is close enough for line wrapping and is
  // deliberately conservative so text never reaches a table boundary.
  return [...value].length * size * 0.48;
}

function wrap(value: string, width: number, size: number): string[] {
  const normalized = value.replace(/\s+/g, ' ').trim();
  if (!normalized) return [''];
  const words = normalized.split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    if (!line && textWidth(word, size) <= width) {
      line = word;
      continue;
    }
    const candidate = line ? `${line} ${word}` : word;
    if (textWidth(candidate, size) <= width) {
      line = candidate;
      continue;
    }
    if (line) lines.push(line);
    if (textWidth(word, size) <= width) {
      line = word;
      continue;
    }
    let fragment = '';
    for (const character of [...word]) {
      const candidateFragment = fragment + character;
      if (fragment && textWidth(candidateFragment, size) > width) {
        lines.push(fragment);
        fragment = character;
      } else {
        fragment = candidateFragment;
      }
    }
    line = fragment;
  }
  if (line) lines.push(line);
  return lines.length ? lines : [''];
}

function color(gray: number): string {
  const value = Math.max(0, Math.min(1, gray));
  return `${pdfNumber(value)} ${pdfNumber(value)} ${pdfNumber(value)} rg`;
}

function lineColor(gray: number): string {
  const value = Math.max(0, Math.min(1, gray));
  return `${pdfNumber(value)} ${pdfNumber(value)} ${pdfNumber(value)} RG`;
}

class PdfDocument {
  readonly pages: PdfPage[] = [];
  private current: PdfPage;
  y = PAGE_HEIGHT - MARGIN;

  constructor() {
    this.current = { commands: [] };
    this.pages.push(this.current);
  }

  pageBreak(): void {
    this.current = { commands: [] };
    this.pages.push(this.current);
    this.y = PAGE_HEIGHT - MARGIN;
  }

  ensure(height: number): void {
    if (this.y - height < BOTTOM) this.pageBreak();
  }

  command(value: string): void {
    this.current.commands.push(value);
  }

  text(value: string, x: number, y: number, size = 10, options: { bold?: boolean; gray?: number } = {}): void {
    this.command(`${color(options.gray ?? 0.16)} BT /${options.bold ? 'F2' : 'F1'} ${pdfNumber(size)} Tf 1 0 0 1 ${pdfNumber(x)} ${pdfNumber(y)} Tm ${pdfString(value)} Tj ET`);
  }

  wrapped(value: string, x: number, width: number, size = 10, lineHeight = size * 1.35, options: { bold?: boolean; gray?: number } = {}): number {
    const lines = wrap(value, width, size);
    for (const line of lines) {
      this.ensure(lineHeight);
      this.text(line, x, this.y, size, options);
      this.y -= lineHeight;
    }
    return lines.length * lineHeight;
  }

  rule(x1: number, x2: number, y: number, gray = 0.84, thickness = 0.7): void {
    this.command(`${lineColor(gray)} ${pdfNumber(thickness)} w ${pdfNumber(x1)} ${pdfNumber(y)} m ${pdfNumber(x2)} ${pdfNumber(y)} l S`);
  }

  rect(x: number, y: number, width: number, height: number, gray = 0.97, stroke = 0.84): void {
    this.command(`${color(gray)} ${lineColor(stroke)} ${pdfNumber(x)} ${pdfNumber(y)} ${pdfNumber(width)} ${pdfNumber(height)} re B`);
  }

  finishPage(page: PdfPage, pageNumber: number, pageCount: number): void {
    const footerY = 31;
    page.commands.push(`${lineColor(0.84)} 0.7 w ${MARGIN} ${footerY + 18} m ${PAGE_WIDTH - MARGIN} ${footerY + 18} l S`);
    page.commands.push(`${color(0.42)} BT /F1 8 Tf 1 0 0 1 ${MARGIN} ${footerY} Tm ${pdfString('Orçamento emitido pelo EventCore · https://eventcore.space')} Tj ET`);
    const pageLabel = `Página ${pageNumber} de ${pageCount}`;
    page.commands.push(`${color(0.42)} BT /F1 8 Tf 1 0 0 1 ${PAGE_WIDTH - MARGIN - textWidth(pageLabel, 8)} ${footerY} Tm ${pdfString(pageLabel)} Tj ET`);
    page.commands.unshift(`${color(0.92)} BT /F2 50 Tf 0.7071 0.7071 -0.7071 0.7071 150 285 Tm ${pdfString('EventCore')} Tj ET`);
  }

  toBuffer(title: string): Buffer {
    const pageCount = this.pages.length;
    this.pages.forEach((page, index) => this.finishPage(page, index + 1, pageCount));
    const objects: string[] = [];
    const add = (value: string) => { objects.push(value); return objects.length; };
    const catalogId = add('');
    const pagesId = add('');
    const regularFontId = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    const boldFontId = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    const infoId = add(`<< /Title ${pdfString(title)} /Author ${pdfString('EventCore')} /Creator ${pdfString('EventCore')} >>`);
    const pageIds: number[] = [];
    for (const page of this.pages) {
      const stream = page.commands.join('\n');
      const streamBytes = Buffer.byteLength(stream, 'latin1');
      const contentId = add(`<< /Length ${streamBytes} >>\nstream\n${stream}\nendstream`);
      const pageId = add(`<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 ${PAGE_WIDTH} ${PAGE_HEIGHT}] /Resources << /ProcSet [/PDF /Text] /Font << /F1 ${regularFontId} 0 R /F2 ${boldFontId} 0 R >> >> /Contents ${contentId} 0 R >>`);
      pageIds.push(pageId);
    }
    objects[catalogId - 1] = `<< /Type /Catalog /Pages ${pagesId} 0 R /PageMode /UseNone /ViewerPreferences << /DisplayDocTitle true >> >>`;
    objects[pagesId - 1] = `<< /Type /Pages /Kids [${pageIds.map(id => `${id} 0 R`).join(' ')}] /Count ${pageIds.length} >>`;

    const chunks: Buffer[] = [Buffer.from('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n', 'binary')];
    const offsets: number[] = [0];
    let offset = chunks[0].length;
    objects.forEach((object, index) => {
      offsets.push(offset);
      const chunk = Buffer.from(`${index + 1} 0 obj\n${object}\nendobj\n`, 'binary');
      chunks.push(chunk);
      offset += chunk.length;
    });
    const xrefOffset = offset;
    let xref = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
    for (let index = 1; index < offsets.length; index += 1) xref += `${String(offsets[index]).padStart(10, '0')} 00000 n \n`;
    xref += `trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R /Info ${infoId} 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
    chunks.push(Buffer.from(xref, 'binary'));
    return Buffer.concat(chunks);
  }
}

function drawBrand(document: PdfDocument, issuer: string): void {
  const x = MARGIN;
  const y = document.y - 4;
  document.command(`${color(0.16)} ${pdfNumber(x)} ${pdfNumber(y - 30)} m ${pdfNumber(x + 32)} ${pdfNumber(y - 30)} l ${pdfNumber(x + 44)} ${pdfNumber(y - 22)} l ${pdfNumber(x + 12)} ${pdfNumber(y - 22)} l h f`);
  document.command(`${color(0.26)} ${pdfNumber(x)} ${pdfNumber(y - 16)} m ${pdfNumber(x + 32)} ${pdfNumber(y - 16)} l ${pdfNumber(x + 44)} ${pdfNumber(y - 8)} l ${pdfNumber(x + 12)} ${pdfNumber(y - 8)} l h f`);
  document.command(`${color(0.36)} ${pdfNumber(x)} ${pdfNumber(y - 2)} m ${pdfNumber(x + 24)} ${pdfNumber(y - 2)} l ${pdfNumber(x + 36)} ${pdfNumber(y + 6)} l ${pdfNumber(x + 12)} ${pdfNumber(y + 6)} l h f`);
  document.text(issuer, x + 58, y - 17, 15, { bold: true, gray: 0.14 });
  document.text('Orçamento de venda', x + 58, y - 34, 9, { gray: 0.4 });
  document.y = y - 58;
}

function drawLabelValue(document: PdfDocument, label: string, value: string, x: number, width: number): void {
  document.text(label, x, document.y, 7.5, { bold: true, gray: 0.42 });
  document.y -= 12;
  document.wrapped(value, x, width, 9.5, 12, { gray: 0.16 });
}

function drawQuoteTable(document: PdfDocument, quote: SaleQuoteDTO, showUnits: boolean): void {
  const tableX = MARGIN;
  const tableWidth = CONTENT_WIDTH;
  const columns = showUnits
    ? [{ key: 'service', label: 'Serviço / função', width: 197 }, { key: 'qty', label: 'Qtd.', width: 43 }, { key: 'days', label: 'Dias', width: 43 }, { key: 'hours', label: 'Horas', width: 48 }, { key: 'unit', label: 'Unitário', width: 82 }, { key: 'total', label: 'Total', width: 84 }]
    : [{ key: 'service', label: 'Serviço / função', width: 285 }, { key: 'qty', label: 'Qtd.', width: 50 }, { key: 'days', label: 'Dias', width: 50 }, { key: 'hours', label: 'Horas', width: 57 }, { key: 'total', label: 'Total', width: 55 }];
  const rowLineHeight = 11;
  const headerHeight = 25;
  const drawHeader = () => {
    document.ensure(headerHeight + 8);
    const top = document.y;
    document.rect(tableX, top - headerHeight, tableWidth, headerHeight, 0.94, 0.84);
    let x = tableX;
    for (const column of columns) {
      document.text(column.label, x + 6, top - 16, 7.7, { bold: true, gray: 0.3 });
      x += column.width;
    }
    document.y = top - headerHeight;
  };
  drawHeader();
  quote.items.forEach((item, itemIndex) => {
    const labelLines = wrap(item.label, columns[0].width - 12, 8.7);
    const rowHeight = Math.max(28, labelLines.length * rowLineHeight + 14);
    if (document.y - rowHeight < BOTTOM + 22) {
      document.pageBreak();
      drawHeader();
    }
    const top = document.y;
    if (itemIndex % 2 === 0) document.rect(tableX, top - rowHeight, tableWidth, rowHeight, 0.985, 0.9);
    let x = tableX;
    labelLines.forEach((line, index) => document.text(line, x + 6, top - 15 - index * rowLineHeight, 8.7, { gray: 0.16 }));
    x += columns[0].width;
    document.text(String(item.quantity), x + 6, top - 15, 8.7);
    x += columns[1].width;
    document.text(String(item.contract_days), x + 6, top - 15, 8.7);
    x += columns[2].width;
    document.text(item.planned_hours == null ? '—' : String(item.planned_hours), x + 6, top - 15, 8.7);
    x += columns[3].width;
    if (showUnits) {
      document.text(money(item.client_unit_price), x + 5, top - 15, 8.2);
      x += columns[4].width;
    }
    document.text(money(item.line_total), x + 5, top - 15, 8.2, { bold: true });
    document.rule(tableX, tableX + tableWidth, top - rowHeight, 0.88, 0.5);
    document.y = top - rowHeight;
  });
  document.y -= 12;
}

export async function renderQuotePdf(quote: SaleQuoteDTO, options: QuotePdfOptions = {}): Promise<Buffer> {
  const showUnits = (options.details ?? (quote.show_unit_prices ? 'units' : 'totals')) === 'units' && quote.show_unit_prices;
  const document = new PdfDocument();
  drawBrand(document, quote.issuer.display_name);
  document.wrapped(quote.title, MARGIN, CONTENT_WIDTH, 20, 24, { bold: true, gray: 0.12 });
  document.y -= 2;
  document.wrapped('Documento comercial com preços de venda e condições da contratação.', MARGIN, CONTENT_WIDTH, 9, 12, { gray: 0.42 });
  document.y -= 10;
  const metadataTop = document.y;
  const columnWidth = (CONTENT_WIDTH - 20) / 3;
  drawLabelValue(document, 'Emitente', quote.issuer.display_name, MARGIN, columnWidth);
  const afterIssuer = document.y;
  document.y = metadataTop;
  drawLabelValue(document, 'Cliente', quote.client.display_name, MARGIN + columnWidth + 10, columnWidth);
  document.y = metadataTop;
  drawLabelValue(document, 'Emissão', date(quote.issued_at), MARGIN + (columnWidth + 10) * 2, columnWidth);
  document.y = Math.min(afterIssuer, document.y) - 5;
  const secondRow = document.y;
  drawLabelValue(document, 'Validade', date(quote.valid_until), MARGIN, columnWidth);
  document.y = secondRow;
  drawLabelValue(document, 'Data do evento', date(quote.event_date), MARGIN + columnWidth + 10, columnWidth);
  document.y = secondRow;
  drawLabelValue(document, 'Local', quote.venue || 'Não informado', MARGIN + (columnWidth + 10) * 2, columnWidth);
  document.y = Math.min(document.y, secondRow - 24) - 2;
  document.rule(MARGIN, PAGE_WIDTH - MARGIN, document.y, 0.82, 0.8);
  document.y -= 18;
  document.text('Serviços e funções', MARGIN, document.y, 12, { bold: true, gray: 0.18 });
  document.y -= 18;
  drawQuoteTable(document, quote, showUnits);
  document.ensure(80);
  document.rect(PAGE_WIDTH - MARGIN - 190, document.y - 52, 190, 52, 0.96, 0.82);
  document.text('Total de venda', PAGE_WIDTH - MARGIN - 178, document.y - 18, 9, { bold: true, gray: 0.32 });
  document.text(money(quote.client_total), PAGE_WIDTH - MARGIN - 178, document.y - 39, 14, { bold: true, gray: 0.12 });
  document.y -= 72;
  document.text('Condições de pagamento', MARGIN, document.y, 11, { bold: true, gray: 0.2 });
  document.y -= 16;
  document.wrapped(quote.payment_terms || 'Não informadas', MARGIN, CONTENT_WIDTH, 9.5, 13, { gray: 0.2 });
  document.y -= 5;
  document.wrapped('Os valores acima representam a venda ao cliente e permanecem sujeitos à validade informada. Outras despesas e impostos permanecem fora deste total.', MARGIN, CONTENT_WIDTH, 8.5, 11, { gray: 0.42 });
  return document.toBuffer(quote.title);
}
