import test from 'node:test';
import assert from 'node:assert/strict';
import * as identity from '../lib/identity.ts';

test('unified document input infers CPF and both CNPJ formats without claiming verification', () => {
  assert.equal(typeof identity.parseDocument, 'function');
  assert.deepEqual(identity.parseDocument('529.982.247-25'), { type: 'cpf', number: '52998224725' });
  assert.deepEqual(identity.parseDocument('11.222.333/0001-81'), { type: 'cnpj', number: '11222333000181' });
  assert.deepEqual(identity.parseDocument('12.abc.345/01de-35'), { type: 'cnpj', number: '12ABC34501DE35' });
});
test('invalid documents and punctuation cannot be silently normalized into a valid identity', () => {
  assert.equal(typeof identity.parseDocument, 'function');
  for (const input of ['', '00000000000', '11111111111111', '52998224724', '12ABC34501DE34', '12ABC34501DE3A', '52998224725!', '１２ABC34501DE35']) assert.equal(identity.parseDocument(input), null);
});
test('sale line totals use quantity and days once, independent of worker remuneration', async () => {
  const { saleLineTotal } = await import('../lib/commercial.ts');
  assert.equal(saleLineTotal({ quantity: 10, contract_days: 2, client_unit_price: 280 }), 5600);
  assert.equal(saleLineTotal({ quantity: 3, contract_days: 1, client_unit_price: 0.1 }), 0.3);
  for (const values of [{quantity: 0, contract_days: 2, client_unit_price: 280}, {quantity: 1, contract_days: 1.5, client_unit_price: 1}, {quantity: 1, contract_days: 1, client_unit_price: NaN}, {quantity: 1, contract_days: 1, client_unit_price: 1.001}]) assert.throws(() => saleLineTotal(values));
});

test('sale totals reject overflow and bounds while preserving zero and cent precision', async () => {
  const { saleLineTotal } = await import('../lib/commercial.ts');
  assert.equal(saleLineTotal({ quantity: 10000, contract_days: 366, client_unit_price: 0 }), 0);
  assert.equal(saleLineTotal({ quantity: 2, contract_days: 2, client_unit_price: 0.29 }), 1.16);
  for (const line of [
    { quantity: 10001, contract_days: 1, client_unit_price: 1 },
    { quantity: 1, contract_days: 367, client_unit_price: 1 },
    { quantity: 1, contract_days: 1, client_unit_price: -1 },
    { quantity: 10000, contract_days: 366, client_unit_price: 9999999999.99 },
  ]) assert.throws(() => saleLineTotal(line));
});

test('commercial adapter preserves caller client and canonical revision/evidence/receipt arguments', async () => {
  const { commercialApi, getEventOperations, getWorkerSchedule } = await import('../lib/commercial.ts');
  const calls = [];
  const db = { rpc: async (name, args) => { calls.push({ name, args }); return { data: 'result', error: null }; } };
  const api = commercialApi(db);
  await api.request('buyer', 'provider', 'Assembly', 'Two days', '2026-10-10', 'Venue');
  await api.submitQuote('quote', 3);
  await api.acceptQuote('quote', 3, 'Signed external acceptance');
  await api.recordReceipt('contract', 1000, 'pix', '2026-10-05', 'receipt-1');
  await getEventOperations(db, 'event');
  await getWorkerSchedule(db);
  assert.deepEqual(calls, [
    { name: 'create_contract_request', args: { p_buyer_organization_id: 'buyer', p_provider_organization_id: 'provider', p_title: 'Assembly', p_description: 'Two days', p_event_date: '2026-10-10', p_venue: 'Venue' } },
    { name: 'submit_sale_quote', args: { p_proposal_id: 'quote', p_expected_revision: 3 } },
    { name: 'accept_sale_quote', args: { p_proposal_id: 'quote', p_expected_revision: 3, p_external_evidence: 'Signed external acceptance' } },
    { name: 'record_customer_receipt', args: { p_contract_id: 'contract', p_amount: 1000, p_method: 'pix', p_received_on: '2026-10-05', p_idempotency_key: 'receipt-1' } },
    { name: 'get_event_operations', args: { p_event_id: 'event' } },
    { name: 'get_my_schedule', args: undefined },
  ]);
  await assert.rejects(() => commercialApi({ rpc: async () => ({ data: null, error: { message: 'stale_quote' } }) }).submitQuote('quote', 1), /stale_quote/);
});

test('server actor rejects missing/empty caller JWT before database access', async () => {
  const { commercialActor, ActorError } = await import('../lib/actor-server.ts');
  for (const authorization of [undefined, 'Basic credentials', 'Bearer ', 'Bearer    ']) {
    const request = new Request('https://example.invalid/api/commercial', { headers: authorization ? { authorization } : {} });
    await assert.rejects(() => commercialActor(request), error => error instanceof ActorError && error.status === 401 && error.message === 'unauthorized');
  }
});

test('daily remuneration uses cent-safe per-worker totals independently from sale pricing', async () => {
  const { remunerationTotal } = await import('../lib/commercial.ts');
  assert.equal(typeof remunerationTotal, 'function');
  assert.equal(remunerationTotal({ basis: 'daily', rate: 220, contract_days: 2, additions: 0, deductions: 0 }), 440);
  assert.equal(remunerationTotal({ basis: 'service', rate: 220, contract_days: 2, additions: 0.1, deductions: 0.03 }), 220.07);
  assert.equal(remunerationTotal({ basis: 'daily', rate: 0.29, contract_days: 4 }), 1.16);
  for (const terms of [{basis:'daily',rate:1.001,contract_days:2}, {basis:'daily',rate:NaN,contract_days:2}, {basis:'daily',rate:1,contract_days:0}, {basis:'service',rate:1,contract_days:2,deductions:2}]) assert.throws(() => remunerationTotal(terms));
});
test('workflow adapter uses stable revision/completion/base/team/finance DTO endpoints', async () => {
  const { workflowApi } = await import('../lib/commercial.ts');
  assert.equal(typeof workflowApi, 'function');
  const calls = [], terms = { basis: 'daily', rate: 230, contract_days: 2, planned_hours: null, benefits: 'Meals', additions: 0, deductions: 0 };
  const api = workflowApi({rpc: async (name,args) => {calls.push({name,args});return {data:'result',error:null};}});
  await api.proposeTerms('assignment', terms); await api.acceptTerms('revision');
  await api.setBaseMember('org','worker',true); await api.saveTeam('org',null,'Team');
  await api.inviteSelected('service',['worker']); await api.workerAssignments();
  await api.confirmWorkerCompletion('assignment'); await api.confirmContractCompletion('contract');
  await api.providerHistory('buyer'); await api.workerHistory('provider'); await api.finance('event');
  await api.providerPresentation('provider');
  assert.deepEqual(calls,[
    {name:'propose_assignment_terms',args:{p_assignment_id:'assignment',p_terms:terms}},
    {name:'accept_assignment_terms',args:{p_term_id:'revision'}},
    {name:'set_provider_base_member',args:{p_organization_id:'org',p_freelancer_id:'worker',p_enabled:true}},
    {name:'save_provider_team',args:{p_organization_id:'org',p_team_id:null,p_name:'Team'}},
    {name:'invite_selected_workers',args:{p_service_id:'service',p_freelancer_ids:['worker']}},
    {name:'get_my_work_assignments',args:undefined},
    {name:'confirm_assignment_completion',args:{p_assignment_id:'assignment'}},
    {name:'confirm_contract_completion',args:{p_contract_id:'contract'}},
    {name:'get_buyer_provider_history',args:{p_organization_id:'buyer'}},
    {name:'get_provider_worker_history',args:{p_organization_id:'provider'}},
    {name:'get_work_finance',args:{p_event_id:'event'}},
    {name:'get_provider_presentation',args:{p_organization_id:'provider'}},
  ]);
});

test('workflow caller carries built creation conditions and retained candidature/attendance arguments unchanged', async () => {
  const { workflowApi } = await import('../lib/commercial.ts');
  const { buildEventCreation } = await import('../lib/event-creation.ts');
  const fields = new FormData();
  for (const [key, value] of Object.entries({ organization_id: 'provider', client_id: 'external-client', name: 'Assembly', venue: 'Private address', origin: 'referral', public_region: 'Rio', start_at: '2026-10-10T08:00:00-03:00', end_at: '2026-10-11T18:00:00-03:00', status: 'planning', 'function.loader.specialty_id': 'loader', 'function.loader.quantity_needed': '10', 'function.loader.contract_days': '2', 'function.loader.remuneration_basis': 'daily', 'function.loader.remuneration_rate': '220' })) fields.set(key, value);
  const input = buildEventCreation(fields, ['loader']);
  const created = { event: { id: 'event', origin: 'referral' }, services: [{ id: 'service', freelancer_unit_cost: 440 }] };
  const calls = [];
  const api = workflowApi({ rpc: async (name, args) => { calls.push({ name, args }); return { data: name === 'create_event_with_services' ? created : 'id', error: null }; } });
  assert.equal(await api.createWork(input.event, input.services), created);
  await api.createAssignment('service', 'worker');
  await api.createAssignment('service', 'reserve-worker', 'reserve');
  await api.applyOpportunity('service', 'Available for both days');
  await api.hireApplication('application');
  await api.recordAttendance('assignment', 'in', -22.9, -43.2);
  await api.validateAttendance('assignment');
  assert.deepEqual(calls, [
    { name: 'create_event_with_services', args: { p_event: input.event, p_services: input.services } },
    { name: 'create_event_assignment', args: { p_service_id: 'service', p_freelancer_id: 'worker', p_status: 'invited' } },
    { name: 'create_event_assignment', args: { p_service_id: 'service', p_freelancer_id: 'reserve-worker', p_status: 'reserve' } },
    { name: 'apply_for_opportunity', args: { p_service_id: 'service', p_message: 'Available for both days' } },
    { name: 'hire_application', args: { p_application_id: 'application' } },
    { name: 'record_assignment_attendance', args: { p_assignment_id: 'assignment', p_kind: 'in', p_lat: -22.9, p_lng: -43.2 } },
    { name: 'validate_assignment_attendance', args: { p_assignment_id: 'assignment' } },
  ]);
  const denied = workflowApi({ rpc: async () => ({ data: null, error: { message: 'worker_acceptance_required' } }) });
  await assert.rejects(() => denied.pay('assignment', 'pix'), /worker_acceptance_required/);
});
