import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

// Only Auth/PostgREST are mocked. Next route, staff helper, caller client and RPC transport are real.
// The boundary refuses every privileged event/export query, ensuring this cannot send to Google.
const actorId = '10000000-0000-4000-8000-000000000003';
const eventId = '40000000-0000-4000-8000-000000000001';
const token = `${Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: actorId, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.fixture`;
const calls = [];
const boundary = http.createServer(async (req, res) => {
  const path = new URL(req.url, 'http://localhost').pathname;
  const chunks = []; for await (const chunk of req) chunks.push(chunk);
  const bytes = Buffer.concat(chunks).toString();
  calls.push({ path, key: req.headers.apikey, authorization: req.headers.authorization, body: bytes ? JSON.parse(bytes) : null });
  res.setHeader('content-type', 'application/json');
  if (path === '/auth/v1/user') return res.end(JSON.stringify({ id: actorId, aud: 'authenticated', role: 'authenticated' }));
  if (path === '/rest/v1/profiles') return res.end(JSON.stringify({ id: actorId, role: 'admin', active: true }));
  if (path === '/rest/v1/rpc/get_event_operations') {
    res.statusCode = 400; return res.end(JSON.stringify({ code: 'P0001', message: 'forbidden' }));
  }
  res.statusCode = 403; res.end(JSON.stringify({ message: 'Unexpected privileged export request', code: '42501' }));
});
await new Promise(resolve => boundary.listen(0, '127.0.0.1', resolve));
const boundaryUrl = `http://127.0.0.1:${boundary.address().port}`;
const port = 20000 + Math.floor(Math.random() * 30000);
let output = '';
const server = spawn(process.execPath, ['node_modules/next/dist/bin/next', 'dev', '--hostname', '127.0.0.1', '--port', String(port)], {
  env: { ...process.env, NEXT_TELEMETRY_DISABLED: '1', NEXT_PUBLIC_SUPABASE_URL: boundaryUrl, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'fixture-public', SUPABASE_SERVICE_ROLE_KEY: 'fixture-service' },
  stdio: ['ignore', 'pipe', 'pipe'],
});
server.stdout.on('data', chunk => { output += chunk; });
server.stderr.on('data', chunk => { output += chunk; });
const base = `http://127.0.0.1:${port}/api/google/sync`;
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (server.exitCode !== null) throw new Error(`Next exited before readiness: ${output}`);
    try { await fetch(base, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }); ready = true; break; }
    catch { await new Promise(resolve => setTimeout(resolve, 200)); }
  }
  assert.equal(ready, true, output);
  calls.length = 0;
  const response = await fetch(base, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ eventId }) });
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'forbidden' });
  assert.deepEqual(calls.map(call => call.path), ['/auth/v1/user', '/rest/v1/profiles', '/auth/v1/user', '/rest/v1/profiles', '/rest/v1/rpc/get_event_operations']);
  const permission = calls.at(-1);
  assert.equal(permission.key, 'fixture-public');
  assert.equal(permission.authorization, `Bearer ${token}`);
  assert.deepEqual(permission.body, { p_event_id: eventId });
  assert.equal(calls.some(call => ['/rest/v1/events', '/rest/v1/clients', '/rest/v1/event_services', '/rest/v1/assignments', '/rest/v1/google_oauth_connections'].includes(call.path)), false);
  console.log('PASS: actual Next Google sync HTTP 403 after verified staff + caller JWT RPC; no privileged event/client/workforce/token read, Calendar export or event-state update');
} finally {
  if (server.exitCode === null && server.signalCode === null) {
    const exited = once(server, 'exit');
    server.kill('SIGTERM');
    await exited;
  }
  boundary.closeAllConnections();
  await new Promise(resolve => boundary.close(resolve));
}
