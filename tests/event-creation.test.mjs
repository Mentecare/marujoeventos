import test from 'node:test';
import assert from 'node:assert/strict';

import { buildEventCreation as build } from '../lib/event-creation.ts';

function form(values = {}) {
  const fields = new FormData();
  for (const [key, value] of Object.entries({
    name: '  Evento de montagem  ', client_id: 'client-id', venue: '  Riocentro  ',
    start_at: '2026-10-10T08:00:00-03:00', end_at: '2026-10-10T18:00:00-03:00',
    status: 'planning', tolerance: '15', notes: '  Nota interna  ', ...values,
  })) fields.set(key, value);
  return fields;
}
function addFunction(fields, key, values = {}) {
  for (const [name, value] of Object.entries({
    specialty_id: 'specialty-id', quantity_needed: '2', reserve_target: '1', contract_days: '1',
    cost: '', briefing: '', requirements: '', ...values,
  })) fields.set(`function.${key}.${name}`, value);
}

test('event creation includes all requested functions and preserves absent versus zero costs', () => {
  const fields = form();
  addFunction(fields, 'first', { contract_days: '3', cost: '0', briefing: '  Chegar cedo  ', open_marketplace: 'on' });
  addFunction(fields, 'second', { specialty_id: 'another-specialty', quantity_needed: '5', reserve_target: '0', contract_days: '2', requirements: '  Sapato fechado  ' });
  assert.deepEqual(build(fields, ['first', 'second']), {
    event: { name: 'Evento de montagem', client_id: 'client-id', venue: 'Riocentro', start_at: '2026-10-10T11:00:00.000Z', end_at: '2026-10-10T21:00:00.000Z', status: 'planning', arrival_tolerance_minutes: 15, notes: 'Nota interna' },
    services: [
      { specialty_id: 'specialty-id', quantity_needed: 2, reserve_target: 1, contract_days: 3, freelancer_unit_cost: 0, briefing: 'Chegar cedo', requirements: null, open_marketplace: true },
      { specialty_id: 'another-specialty', quantity_needed: 5, reserve_target: 0, contract_days: 2, freelancer_unit_cost: null, briefing: null, requirements: 'Sapato fechado', open_marketplace: false },
    ],
  });
});

test('each function defaults to one day when omitted and preserves the supplied financial amount', () => {
  const fields = form();
  addFunction(fields, 'legacy-client');
  fields.delete('function.legacy-client.contract_days');
  addFunction(fields, 'multiple-days', { contract_days: '4', cost: '150.25' });
  const { services } = build(fields, ['legacy-client', 'multiple-days']);
  assert.equal(services[0].contract_days, 1);
  assert.equal(services[1].contract_days, 4);
  assert.equal(services[1].freelancer_unit_cost, 150.25);
});

test('invalid day counts reject the entire event with the affected function identified', () => {
  for (const contract_days of ['', '0', '-1', '1.5', 'NaN', 'Infinity', 'abc', '2147483648']) {
    const fields = form();
    addFunction(fields, 'valid');
    addFunction(fields, 'invalid', { contract_days });
    assert.throws(() => build(fields, ['valid', 'invalid']), /dias.*função 2/i);
  }
});

test('removed draft functions are excluded and an event can be created without functions', () => {
  const fields = form();
  addFunction(fields, 'removed', { cost: '-1' });
  assert.deepEqual(build(fields, []).services, []);
});

test('an invalid function prevents any creation payload from being submitted', () => {
  for (const values of [
    { specialty_id: '' }, { quantity_needed: '0' }, { quantity_needed: '1.5' },
    { quantity_needed: '2147483648' }, { reserve_target: '-1' }, { reserve_target: '0.5' },
    { cost: '-0.01' }, { cost: 'NaN' }, { cost: '12.345' }, { cost: '10000000000' },
  ]) {
    const fields = form(); addFunction(fields, 'valid'); addFunction(fields, 'invalid', values);
    assert.throws(() => build(fields, ['valid', 'invalid']), /função|funções/i);
  }
});

test('event creation rejects missing details and invalid date ranges before requesting a save', () => {
  for (const values of [
    { name: '   ' }, { client_id: '' }, { venue: '  ' }, { start_at: 'invalid' },
    { end_at: '' }, { end_at: '2026-10-10T07:00:00-03:00' },
    { end_at: '2026-10-10T08:00:00-03:00' }, { tolerance: '-1' },
    { tolerance: '15.5' }, { status: 'completed' },
  ]) assert.throws(() => build(form(values), []), /evento|término|tolerância/i);
});

test('new daily conditions, origin and provider context are passed separately from legacy total costs', () => {
  const fields = form({ organization_id: 'provider', origin: 'whatsapp' });
  addFunction(fields, 'daily', { contract_days: '2', remuneration_basis: 'daily', remuneration_rate: '220', benefits: ' Meals ', additions: '0.1', deductions: '0.03', planned_hours: '8' });
  const result = build(fields,['daily']);
  assert.equal(result.event.organization_id,'provider'); assert.equal(result.event.origin,'whatsapp');
  assert.deepEqual(result.services[0],{ specialty_id:'specialty-id',quantity_needed:2,reserve_target:1,contract_days:2,freelancer_unit_cost:440.07,briefing:null,requirements:null,open_marketplace:false,remuneration_basis:'daily',remuneration_rate:220,benefits:'Meals',additions:0.1,deductions:0.03,planned_hours:8 });
});
