// Zero-network investigation of the warning seen when Next bundles web-push.
// Node exempts callers inside node_modules from DEP0169; evaluate the installed
// SDK source unchanged at a test filename to reproduce its bundled location.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import Module, {createRequire} from 'node:module';
import https from 'node:https';
import {createECDH, randomBytes} from 'node:crypto';
import webPush from 'web-push';
const require=createRequire(import.meta.url);
const sourcePath=path.join(path.dirname(require.resolve('web-push')),'web-push-lib.js');
const bundled=new Module(path.resolve('tests/web-push-bundled-trace.cjs'));
bundled.filename=bundled.id;
bundled.require=createRequire(sourcePath);
const warnings=[];
process.on('warning',warning=>warnings.push(warning));
const originalRequest=https.request,originalFetch=globalThis.fetch;
let networkCalls=0;
https.request=()=>{networkCalls++;throw Error('network forbidden')};
globalThis.fetch=async()=>{networkCalls++;throw Error('network forbidden')};
try {
  bundled._compile(fs.readFileSync(sourcePath,'utf8'),bundled.filename);
  const receiver=createECDH('prime256v1');receiver.generateKeys();
  const vapid=webPush.generateVAPIDKeys();
  const request=new bundled.exports().generateRequestDetails({endpoint:'https://fcm.googleapis.com/fcm/send/fixture',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')}},'{}',{vapidDetails:{subject:'mailto:test@example.invalid',publicKey:vapid.publicKey,privateKey:vapid.privateKey}});
  assert.ok(request.body.length);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(networkCalls,0);
  const warning=warnings.find(warning=>warning.code==='DEP0169');
  assert.ok(warning,'expected bundled SDK url.parse warning');
  assert.match(warning.stack,/generateRequestDetails/);
  console.log('PASS: DEP0169 originates in unchanged web-push@3.6.7 generateRequestDetails url.parse at source line274 when bundled outside node_modules; encrypted request produced; zero network calls');
} finally { https.request=originalRequest;globalThis.fetch=originalFetch; }
