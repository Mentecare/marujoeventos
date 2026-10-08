import test from 'node:test';
import assert from 'node:assert/strict';
import { createGoogleSyncHandler } from '../lib/google-sync.ts';

const eventId = '40000000-0000-4000-8000-000000000001';
const request = () => new Request('https://example.invalid/api/google/sync', {
  method: 'POST', headers: { authorization: 'Bearer fixture-caller', 'content-type': 'application/json' }, body: JSON.stringify({ eventId }),
});

function boundary({ authorized = false, permissionError = null, actorId = 'staff', googleEventId = null } = {}) {
  const calls = [];
  const event = { id: eventId, name: 'Private work', venue: 'Venue', notes: 'Authorized operating note', start_at: '2026-10-10T10:00:00Z', end_at: '2026-10-10T18:00:00Z', client_id: 'client', google_event_id: googleEventId };
  const serviceDb = {
    from(table) {
      calls.push(['privileged-read', table]);
      const result = { data: table === 'events' ? event : table === 'clients' ? { trade_name: 'Client' } : table === 'event_services' ? [{ id: 'service', quantity_needed: 10 }] : [{ status: 'confirmed' }, { status: 'invited' }], error: null };
      return {
        select(columns) { calls.push(['select', table, columns]); return this; },
        eq() { return this; }, in() { return this; },
        single: async () => result, maybeSingle: async () => result,
        update(row) { calls.push(['state-update', table, row]); return this; },
        then(resolve) { return Promise.resolve(result).then(resolve); },
      };
    },
  };
  return {
    calls,
    dependencies: {
      verifyStaffToken: async token => { calls.push(['staff', token]); return { user: { id: 'staff' } }; },
      commercialActor: async req => {
        calls.push(['actor', req.headers.get('authorization')]);
        return { id: actorId, db: { rpc: async (name, args) => {
          calls.push(['permission', name, args]);
          return { data: authorized ? { event: { id: eventId }, can_finance: false, can_hire: false } : null, error: permissionError || (authorized ? null : { message: 'forbidden' }) };
        } } };
      },
      serviceSupabase: () => { calls.push(['service-client']); return serviceDb; },
      getGoogleAccessToken: async id => { calls.push(['google-token', id]); return 'fixture-google-token'; },
      calendarFetch: async (url, init) => { calls.push(['google-adapter', url, init]); return Response.json({ id: 'google-event', htmlLink: 'https://example.invalid/calendar' }); },
    },
  };
}

test('Google sync rejects unrelated staff before privileged reads, token lookup, export or state update', async () => {
  const fixture = boundary();
  const response = await createGoogleSyncHandler(fixture.dependencies)(request());
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'forbidden' });
  assert.deepEqual(fixture.calls, [
    ['staff', 'fixture-caller'], ['actor', 'Bearer fixture-caller'],
    ['permission', 'get_event_operations', { p_event_id: eventId }],
  ]);
});

test('Google sync fails closed for missing permission rows, permission failures and mismatched verified actors', async () => {
  for (const options of [{ permissionError: { message: 'unavailable' } }, { actorId: 'different-user', authorized: true }]) {
    const fixture = boundary(options);
    const response = await createGoogleSyncHandler(fixture.dependencies)(request());
    assert.equal(response.status, 403);
    assert.equal(fixture.calls.some(([call]) => ['service-client', 'privileged-read', 'google-token', 'google-adapter', 'state-update'].includes(call)), false);
  }
  const fixture = boundary({ authorized: true });
  fixture.dependencies.commercialActor = async () => ({ id: 'staff', db: { rpc: async () => ({ data: { event: { id: 'another-event' } }, error: null }) } });
  assert.equal((await createGoogleSyncHandler(fixture.dependencies)(request())).status, 403);
  assert.equal(fixture.calls.some(([call]) => call === 'service-client'), false);
});

test('authorized staff operator retains create/update Calendar behavior without requiring finance', async () => {
  for (const googleEventId of [null, 'existing/event']) {
    const fixture = boundary({ authorized: true, googleEventId });
    const response = await createGoogleSyncHandler(fixture.dependencies)(request());
    assert.equal(response.status, 200);
    assert.equal(fixture.calls.findIndex(([call]) => call === 'permission') < fixture.calls.findIndex(([call]) => call === 'service-client'), true);
    const [, url, init] = fixture.calls.find(([call]) => call === 'google-adapter');
    assert.equal(init.method, googleEventId ? 'PUT' : 'POST');
    assert.equal(url.endsWith('existing%2Fevent'), Boolean(googleEventId));
    const payload = JSON.parse(init.body);
    assert.equal(payload.description.includes('Equipe: 1/10'), true);
    assert.equal(payload.description.includes('Authorized operating note'), true);
    assert.equal(JSON.stringify(payload).includes('freelancer_unit_cost'), false);
    assert.equal(fixture.calls.filter(([call]) => call === 'state-update').length, 1);
  }
});
