import test from 'node:test';
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
  return execFileSync('/usr/bin/pdftotext', [file, '-'], { encoding: 'utf8' });
}

function pdfPages(file) {
  const output = execFileSync('/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/pdfinfo', [file], { encoding: 'utf8' });
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
  assert.match(text, /Orçamento muito extenso para uma operação\s+cenográfica/);
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
  const text = pdfText(file);
  const pageTexts = text.split('\f').filter(Boolean);
  assert.equal(pageTexts.length, pages);
  for (const page of pageTexts) {
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
