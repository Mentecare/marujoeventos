import test from 'node:test';
import {pdfTool,python} from './runtime-tools.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { renderQuotePdf } from '../lib/quote-pdf.ts';
import { quotePdfResponse } from '../lib/quote-pdf-route.ts';
import { ActorError } from '../lib/actor-server.ts';

const id = '10000000-0000-4000-8000-000000000001';
const baseQuote = {
  id,
  revision: 2,
  status: 'sent',
  title: 'Orçamento Aurora',
  issued_at: '2026-10-06T12:00:00Z',
  event_date: '2026-10-07',
  venue: 'São Paulo — Centro',
  valid_until: '2026-10-20',
  payment_terms: '50% na reserva e 50% após o evento.',
  show_unit_prices: true,
  client_total: 5600,
  issuer: { id: '20000000-0000-4000-8000-000000000001', display_name: 'Equipe Aurora' },
  client: { display_name: 'Agência Cenográfica' },
  request_id: null,
  contract_id: null,
  items: [{ id: '30000000-0000-4000-8000-000000000001', label: 'Montagem de cenário', quantity: 10, contract_days: 2, planned_hours: 8, client_unit_price: 280, line_total: 5600 }],
};

function tempPdf(name) {
  return path.join(os.tmpdir(), `eventcore-${process.pid}-${name}.pdf`);
}

function pdfText(file) {
  return execFileSync(pdfTool('pdftotext'), [file, '-'], { encoding: 'utf8' });
}

function pdfLinks(file) {
  return JSON.parse(execFileSync(python, ['-c', 'import fitz,json,sys; print(json.dumps([[dict(uri=link.get("uri"),rect=list(link["from"])) for link in page.get_links()] for page in fitz.open(sys.argv[1])]))', file], { encoding: 'utf8' }));
}

function assertPlatformLinkOnEveryPage(file) {
  const pages = pdfLinks(file);
  assert.equal(pages.length, pdfPages(file));
  for (const [index, links] of pages.entries()) {
    const platform = links.filter(link => link.uri === 'https://eventcore.space');
    assert.equal(platform.length, 1, `page ${index + 1} must have one explicit platform URI annotation`);
    assert.ok(platform[0].rect[1] >= 793 && platform[0].rect[3] <= 820, 'platform link covers the footer, not body content');
  }
}

function pdfPages(file) {
  const output = execFileSync(pdfTool('pdfinfo'), [file], { encoding: 'utf8' });
  return Number(output.match(/^Pages:\s+(\d+)/m)?.[1] || 0);
}

test('PDF de totais e unitários usa moeda/data brasileiras e mantém o total calculado', async () => {
  const unitPath = tempPdf('units');
  const totalPath = tempPdf('totals');
  fs.writeFileSync(unitPath, await renderQuotePdf(baseQuote, { details: 'units' }));
  fs.writeFileSync(totalPath, await renderQuotePdf(baseQuote, { details: 'totals' }));
  const units = pdfText(unitPath);
  const totals = pdfText(totalPath);
  assert.equal(pdfPages(unitPath), 1);
  assert.equal(pdfPages(totalPath), 1);
  assertPlatformLinkOnEveryPage(unitPath);
  assertPlatformLinkOnEveryPage(totalPath);
  assert.match(units, /Orçamento Aurora/);
  assert.match(units, /São Paulo/);
  assert.match(units, /R\$ 280,00/);
  assert.match(units, /R\$ 5\.600,00/);
  assert.match(totals, /R\$ 5\.600,00/);
  assert.doesNotMatch(totals, /R\$ 280,00/);
  assert.doesNotMatch(units, /220|freelancer|margem|freelancer_unit_cost/i);
  assert.equal((units.match(/R\$ 5\.600,00/g) || []).length, (totals.match(/R\$ 5\.600,00/g) || []).length);
});

test('PDF converte timestamps para a data brasileira e quebra título extenso', async () => {
  const file = tempPdf('timezone-title');
  const quote = { ...baseQuote, title: 'Orçamento muito extenso para uma operação cenográfica com várias frentes de montagem', issued_at: '2026-10-07T01:30:00Z' };
  fs.writeFileSync(file, await renderQuotePdf(quote, { details: 'totals' }));
  const text = pdfText(file);
  assert.match(text, /06\/10\/2026/);
  assert.match(text, /Orçamento muito extenso para uma\s+operação\s+cenográfica/);
  assert.equal(pdfPages(file), 1);
});

test('PDF longo quebra páginas e repete marca d’água e rodapé em cada página', async () => {
  const longQuote = { ...baseQuote, title: 'Orçamento longo para montagem e operação', items: Array.from({ length: 64 }, (_, index) => ({
    id: `30000000-0000-4000-8000-${String(index + 10).padStart(12, '0')}`,
    label: `Serviço de montagem e operação ${index + 1} — área cenográfica com orientação`,
    quantity: 10,
    contract_days: 2,
    planned_hours: 8,
    client_unit_price: 280,
    line_total: 5600,
  })), client_total: 358400 };
  const file = tempPdf('long');
  fs.writeFileSync(file, await renderQuotePdf(longQuote, { details: 'totals' }));
  const pages = pdfPages(file);
  assert.ok(pages > 1, `esperava mais de uma página, recebi ${pages}`);
  assertPlatformLinkOnEveryPage(file);
  const text = pdfText(file);
  const pageTexts = text.split('\f').filter(Boolean);
  assert.equal(pageTexts.length, pages);
  for (const page of pageTexts) {
    const normalized = page.replace(/\s+/g, ' ');
    assert.equal((normalized.match(/Serviço de montagem e operação/g) || []).length, (normalized.match(/área cenográfica com orientação/g) || []).length, 'short rows must remain together on their page');
    assert.match(page, /EventCore/);
    assert.match(page, /Orçamento emitido pelo EventCore/);
    assert.match(page, /Página \d+ de \d+/);
  }
});

test('rota do PDF exige UUID e autenticação, usa a consulta autorizada e não enumera orçamento', async () => {
  let fetched = 0;
  let rendered = 0;
  const deps = {
    actor: async request => {
      if (request.headers.get('authorization') !== 'Bearer fixture-token') throw new ActorError('unauthorized', 401);
      return { db: { fixture: true } };
    },
    fetchQuote: async (db, quoteId) => { fetched += 1; assert.deepEqual(db, { fixture: true }); assert.equal(quoteId, id); return baseQuote; },
    render: async (quote, options) => { rendered += 1; assert.equal(quote.id, id); assert.equal(options.details, 'totals'); return Buffer.from('%PDF-fixture'); },
  };
  const malformed = await quotePdfResponse(new Request(`https://eventcore.space/api/quotes/not-a-uuid/pdf`), 'not-a-uuid', deps);
  assert.equal(malformed.status, 404);
  assert.equal(fetched, 0);
  const unauthorized = await quotePdfResponse(new Request(`https://eventcore.space/api/quotes/${id}/pdf`), id, deps);
  assert.equal(unauthorized.status, 401);
  const response = await quotePdfResponse(new Request(`https://eventcore.space/api/quotes/${id}/pdf?details=totals`, { headers: { authorization: 'Bearer fixture-token' } }), id, deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/pdf');
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
  assert.match(response.headers.get('content-disposition'), /orcamento-eventcore-/);
  assert.equal(await response.text(), '%PDF-fixture');
  assert.equal(rendered, 1);
});

test('rota não permite pedir unitários quando o DTO autorizado não os oferece', async () => {
  let rendered = 0;
  const quote = { ...baseQuote, show_unit_prices: false };
  const response = await quotePdfResponse(new Request(`https://eventcore.space/api/quotes/${id}/pdf?details=units`, { headers: { authorization: 'Bearer fixture-token' } }), id, {
    actor: async () => ({ db: {} }),
    fetchQuote: async () => quote,
    render: async () => { rendered += 1; return Buffer.from('%PDF'); },
  });
  assert.equal(response.status, 400);
  assert.equal(rendered, 0);
});

test('rota diferencia falha de renderização de orçamento não encontrado', async () => {
  const response = await quotePdfResponse(new Request(`https://eventcore.space/api/quotes/${id}/pdf`, { headers: { authorization: 'Bearer fixture-token' } }), id, {
    actor: async () => ({ db: {} }),
    fetchQuote: async () => baseQuote,
    render: async () => { throw new Error('renderer unavailable'); },
  });
  assert.equal(response.status, 500);
});

test('PDF mede nomes extensos, valores grandes e divide uma única linha maior que uma página sem cortar texto', async () => {
  const file = tempPdf('edge-layout');
  const quote = { ...baseQuote,
    issuer: { ...baseQuote.issuer, display_name: 'WWWW Empresa de montagem e operações cenográficas '.repeat(5) },
    client: { display_name: 'WWWW Cliente com razão social extensa e departamento de produção '.repeat(6) },
    venue: 'WWWW Local de realização e endereço autorizado '.repeat(6),
    items: [{ ...baseQuote.items[0], label: 'WWWW Estrutura cenográfica '.repeat(180) + 'FIM-DESCRICAO', client_unit_price: 99999999.99, line_total: 9999999999.99 }],
    client_total: 9999999999.99,
    freelancer_unit_cost: 'PRIVATE-DO-NOT-PRINT',
  };
  fs.writeFileSync(file, await renderQuotePdf(quote, { details: 'units' }));
  const text = pdfText(file);
  assert.match(text, /FIM-DESCRICAO/);
  assert.match(text, /R\$ 9\.999\.999\.999,99/);
  assert.doesNotMatch(text, /PRIVATE-DO-NOT-PRINT/);
  const bbox = execFileSync(pdfTool('pdftotext'), ['-bbox', file, '-'], { encoding: 'utf8' });
  for (const word of bbox.matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<\/word>/g)) {
    if (word[5] === 'EventCore') continue; // diagonal watermark intentionally has its own box
    assert.ok(+word[1] >= 47 && +word[3] <= 549, `horizontal clipping: ${word[5]} ${word[1]}..${word[3]}`);
    assert.ok(+word[2] >= 40 && +word[4] <= 815, `vertical clipping: ${word[5]} ${word[2]}..${word[4]}`);
  }
  for (const page of text.split('\f').filter(Boolean)) {
    assert.match(page, /Orçamento emitido pelo EventCore/);
    assert.match(page, /Página \d+ de \d+/);
  }
});

test('PDF incorpora bytes de marca confiáveis em vez de ignorar o avatar do emitente', async () => {
  const { default: sharp } = await import('sharp');
  const logo = await sharp({ create: { width: 40, height: 24, channels: 3, background: '#1e6b52' } }).png().toBuffer();
  const file = tempPdf('issuer-logo');
  fs.writeFileSync(file, await renderQuotePdf(baseQuote, { details: 'totals', issuerLogo: logo }));
  const images = execFileSync(pdfTool('pdfimages'), ['-list', file], { encoding: 'utf8' });
  assert.match(images, /\simage\s+40\s+24/);
});

 test('PDF preserves decomposed Portuguese and supported Cyrillic/Greek, rejects unsupported glyphs', async () => {
 const file=tempPdf('unicode');
 const q={...baseQuote,client:{display_name:'Agência São João'.normalize('NFD')},issuer:{...baseQuote.issuer,display_name:'Компания Αθήνα'},items:[{...baseQuote.items[0],label:'Montagem de cenário'.normalize('NFD')}]};
 fs.writeFileSync(file,await renderQuotePdf(q));
 const text=pdfText(file);
 assert.match(text,/Agência São João/);assert.match(text,/Montagem de cenário/);assert.match(text,/Компания Αθήνα/);
 await assert.rejects(renderQuotePdf({...baseQuote,client:{display_name:'東京'}}),/unsupported_pdf_text/);
 await assert.rejects(renderQuotePdf({...baseQuote,title:'Contrato 🧑'}),/unsupported_pdf_text/);
 });
