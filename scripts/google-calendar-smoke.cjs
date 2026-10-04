// Run only in an isolated preview build. No credentials or real event content is logged.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const required = ['NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_TOKEN_ENCRYPTION_KEY'];
for (const key of required) assert(process.env[key], `Missing configuration: ${key}`);
const root = process.cwd();
const temp = fs.mkdtempSync(path.join(root, '.google-smoke-'));
fs.writeFileSync(path.join(temp, 'package.json'), '{"type":"commonjs"}');
for (const name of ['supabase-server', 'google']) {
  const source = fs.readFileSync(path.join(root, 'lib', `${name}.ts`), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true } }).outputText;
  fs.writeFileSync(path.join(temp, `${name}.js`), output);
}
const { serviceSupabase } = require(path.join(temp, 'supabase-server.js'));
const { getGoogleAccessToken } = require(path.join(temp, 'google.js'));
const marker = `eventcore-smoke-${crypto.randomUUID()}`;
const base = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';
const start = new Date();
start.setUTCDate(start.getUTCDate() + 7);
start.setUTCHours(12, 0, 0, 0);
const end = new Date(start.getTime() + 5 * 60_000);
let token;
let fixtureId;
let attemptedCreation = false;
let cleanupVerified = false;
const report = {};

async function google(url, method = 'GET', body) {
  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  let data = {};
  if (text) { try { data = JSON.parse(text); } catch { throw new Error(`Invalid Google response: HTTP ${response.status}`); } }
  if (!response.ok) throw new Error(`Google request failed: ${method} HTTP ${response.status}`);
  return data;
}

async function fixtures() {
  const params = new URLSearchParams({ q: marker, timeMin: start.toISOString(), timeMax: end.toISOString(), singleEvents: 'true', maxResults: '20' });
  const data = await google(`${base}?${params}`);
  return (data.items || []).filter(item => item.summary?.includes(marker));
}

function comparable(event) {
  return JSON.stringify({ summary: event.summary, location: event.location, description: event.description, start: event.start, end: event.end, attendees: event.attendees || [], reminders: event.reminders });
}

(async () => {
  try {
    const db = serviceSupabase();
    const connections = await db.from('google_oauth_connections').select('user_id,email,access_expires_at').limit(2);
    assert.ifError(connections.error);
    assert.equal(connections.data.length, 1, 'Expected the single previously verified Google connection');
    const connection = connections.data[0];
    const profile = await db.from('profiles').select('role,active').eq('id', connection.user_id).single();
    assert.ifError(profile.error);
    assert(profile.data.active && ['admin', 'coordinator'].includes(profile.data.role), 'An active staff connection is required');
    const events = await db.from('events').select('id,name,start_at,end_at,google_event_id').not('google_event_id', 'is', null).limit(2);
    assert.ifError(events.error);
    assert.equal(events.data.length, 1, 'Expected the single previously verified synchronized event');
    const event = events.data[0];

    token = await getGoogleAccessToken(connection.user_id);
    const identity = await google('https://www.googleapis.com/oauth2/v2/userinfo');
    assert(identity.email === connection.email, 'Connected Google account mismatch');
    const refreshed = await db.from('google_oauth_connections').select('access_expires_at').eq('user_id', connection.user_id).single();
    assert.ifError(refreshed.error);
    assert(new Date(refreshed.data.access_expires_at).getTime() > Date.now() + 60000, 'A current access token is required');
    report.account_verified = true;
    report.token_refresh_verified = new Date(connection.access_expires_at).getTime() <= Date.now() + 60000 && refreshed.data.access_expires_at !== connection.access_expires_at;
    console.log('GOOGLE_SMOKE: connection and current access token verified');

    const existingUrl = `${base}/${encodeURIComponent(event.google_event_id)}`;
    const before = await google(existingUrl);
    assert(before.summary === event.name, 'The existing event title must match the database');
    assert(new Date(before.start.dateTime).getTime() === new Date(event.start_at).getTime(), 'The existing event start must match the database');
    assert(new Date(before.end.dateTime).getTime() === new Date(event.end_at).getTime(), 'The existing event end must match the database');
    report.existing_event_matches_database = true;

    const payload = {
      summary: `[TESTE TÉCNICO] ${marker}`,
      description: 'Verificação temporária do EventCore. Será removida automaticamente.',
      location: 'Teste técnico sem operação real',
      start: { dateTime: start.toISOString(), timeZone: 'America/Sao_Paulo' },
      end: { dateTime: end.toISOString(), timeZone: 'America/Sao_Paulo' },
      attendees: [],
      reminders: { useDefault: false, overrides: [] },
      transparency: 'transparent',
      visibility: 'private',
      extendedProperties: { private: { eventcoreSmoke: marker } },
    };
    attemptedCreation = true;
    const created = await google(`${base}?sendUpdates=none`, 'POST', payload);
    assert(created.id, 'Google must return a created event ID');
    fixtureId = created.id;
    console.log(`GOOGLE_SMOKE: temporary event created ${fixtureId}`);
    report.create_verified = true;
    const fixtureUrl = `${base}/${encodeURIComponent(fixtureId)}`;
    const read = await google(fixtureUrl);
    assert.equal(read.summary, payload.summary);
    assert.equal(read.start.timeZone, 'America/Sao_Paulo');
    assert.equal(read.reminders.useDefault, false);
    assert.equal(read.transparency, 'transparent');
    assert.equal((read.attendees || []).length, 0);

    payload.summary += ' — atualizado';
    const updated = await google(`${fixtureUrl}?sendUpdates=none`, 'PUT', payload);
    assert.equal(updated.id, fixtureId, 'Updating must retain the original event ID');
    const reread = await google(fixtureUrl);
    assert.equal(reread.summary, payload.summary);
    const current = await fixtures();
    assert.equal(current.length, 1, 'An update must not duplicate the event');
    assert.equal(current[0].id, fixtureId);
    report.update_without_duplicate_verified = true;
    assert(comparable(await google(existingUrl)) === comparable(before), 'The original event must remain unchanged');
    report.original_event_preserved = true;
  } finally {
    try {
      if (token && attemptedCreation) {
        const current = await fixtures();
        const ids = new Set(current.map(item => item.id));
        if (fixtureId) ids.add(fixtureId);
        for (const id of ids) await google(`${base}/${encodeURIComponent(id)}?sendUpdates=none`, 'DELETE');
        assert.equal((await fixtures()).length, 0, 'Temporary events must be removed');
        cleanupVerified = true;
        console.log('GOOGLE_SMOKE: temporary event cleanup verified');
      }
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
  }
  assert(cleanupVerified, 'Google fixture cleanup is required');
  report.cleanup_verified = cleanupVerified;
  console.log(`GOOGLE_SMOKE_PASS ${JSON.stringify(report)}`);
})().catch(error => {
  console.error(`GOOGLE_SMOKE_FAIL ${error.name}: ${error.message}`);
  process.exitCode = 1;
});
