import test from 'node:test';
import assert from 'node:assert/strict';
import { safeNotificationLink, validatePushSubscription, pushSupport, notificationApi } from '../lib/notifications.ts';
import { dispatchNotifications, authorizedDispatcher, deliveryConfiguration, createDeliveryAdapters } from '../lib/notification-delivery.ts';
const id='10000000-0000-4000-8000-000000000001';
const subscription={endpoint:'https://fcm.googleapis.com/fcm/send/fixture',keys:{p256dh:Buffer.alloc(65,4).toString('base64url'),auth:Buffer.alloc(16,1).toString('base64url')}};
test('notification links only accept exact internal opportunity and own-work/contract targets',()=>{
 for(const link of [`/o/${id}`,`/?opportunity=${id}`,`/?assignment=${id}`,`/?contract=${id}`,`/?request=${id}`,`/?proposal=${id}`])assert.equal(safeNotificationLink(link),link);
 for(const link of ['https://evil.test','//evil.test','/?contract=bad',`/?contract=${id}&next=https://evil.test`,`/o/${id}?private=1`,'/api/profile/photos','javascript:alert(1)'])assert.equal(safeNotificationLink(link),null);
});
test('commercial alert links cannot append destinations or combine private targets',()=>{
 for(const link of [`/?request=${id}&next=https://evil.test`,`/?proposal=${id}&request=${id}`,`/?proposal=${id}#private`,'/?request=unknown','/?proposal=unknown'])assert.equal(safeNotificationLink(link),null);
});
test('push endpoint validation rejects SSRF, credentials, redirects and malformed keys',()=>{
 assert.deepEqual(validatePushSubscription(subscription),subscription);
 for(const endpoint of ['http://fcm.googleapis.com/fcm/send/x','https://127.0.0.1/x','https://localhost/x','https://fcm.googleapis.com.evil.test/x','https://user@fcm.googleapis.com/x','https://fcm.googleapis.com:8443/x','https://fcm.googleapis.com/arbitrary','https://evil.push.apple.com/x'])assert.throws(()=>validatePushSubscription({...subscription,endpoint}));
 assert.throws(()=>validatePushSubscription({...subscription,keys:{p256dh:'bad',auth:'bad'}}));
});
test('denial and unsupported browsers preserve non-push channel compatibility',()=>{
 assert.equal(pushSupport({serviceWorker:true,pushManager:true,notification:true,permission:'denied'}),'denied');
 assert.equal(pushSupport({serviceWorker:true,pushManager:false,notification:false,permission:'default'}),'unsupported');
 assert.equal(pushSupport({serviceWorker:true,pushManager:true,notification:true,permission:'default'}),'available');
});
test('dispatcher refuses wrong or absent token and weak configuration',()=>{
 assert.equal(authorizedDispatcher('Bearer '+ 'a'.repeat(32),'a'.repeat(32)),true);
 for(const token of [null,'Bearer '+ 'b'.repeat(32),'Bearer short'])assert.equal(authorizedDispatcher(token,'a'.repeat(32)),false);
 assert.equal(authorizedDispatcher('Bearer short','short'),false);
});
test('absent resources are explicit and never acknowledge delivery',async()=>{
 assert.deepEqual(deliveryConfiguration({}),{push:{enabled:false,missing:['NOTIFICATION_VAPID_PUBLIC_KEY','NOTIFICATION_VAPID_PRIVATE_KEY','NOTIFICATION_VAPID_SUBJECT']},email:{enabled:false,missing:['RESEND_API_KEY','NOTIFICATION_EMAIL_FROM']}});
 const adapters=createDeliveryAdapters({});
 assert.equal((await adapters.email({id,to:'confirmed@example.invalid',notifications:[{title:'Convite',link:`/?assignment=${id}`}]})).status,'disabled');
 assert.equal((await adapters.push(subscription,{title:'Convite',link:`/?assignment=${id}`})).status,'disabled');
});
test('durable dispatcher records acknowledgment only after isolated adapter result; failures retry and expired devices disable',async()=>{
 const calls=[];const db={rpc:async(name,args)=>{calls.push([name,args]);return{data:name==='recheck_notification_batch'?true:name==='claim_notification_batches'?[{id,channel:'push',notifications:[{title:'Convite',link:`/?assignment=${id}`}],devices:[{id:'device',subscription}]}]:null,error:null}}};
 await dispatchNotifications(db,{push:async()=>({status:'retry',reason:'provider_unavailable'}),email:async()=>({status:'disabled',reason:'email_not_configured'})});
 assert.equal(calls.at(-1)[1].p_outcome,'retry');assert.equal(calls.some(([n])=>n==='ack_notification_device'),false);
 calls.length=0;
 await dispatchNotifications(db,{push:async()=>({status:'acknowledged'}),email:async()=>({status:'disabled',reason:'email_not_configured'})});
 assert.ok(calls.some(([n])=>n==='ack_notification_device'));assert.equal(calls.at(-1)[1].p_outcome,'acknowledged');
 calls.length=0;
 await dispatchNotifications(db,{push:async()=>({status:'expired'}),email:async()=>({status:'disabled',reason:'email_not_configured'})});
 assert.ok(calls.some(([n])=>n==='disable_notification_device'));assert.equal(calls.at(-1)[1].p_outcome,'suppressed');
});
test('API preferences do not filter opportunity browsing; methods preserve caller RPC scope',async()=>{
 const calls=[];const api=notificationApi({rpc:async(n,a)=>{calls.push([n,a]);return{data:[],error:null}}});
 await api.center();await api.savePreferences({mode:'all_eligible',cadence:'daily',email_enabled:true,push_enabled:false,paused_until:null,specialty_ids:[],regions:[],date_from:null,date_to:null});
 assert.deepEqual(calls.map(([n])=>n),['get_notification_center','save_notification_preferences']);
});
test('real email adapter uses fixed provider and durable idempotency, requires provider id',async()=>{
 const requests=[];const env={RESEND_API_KEY:'isolated-fixture-key',NOTIFICATION_EMAIL_FROM:'EventCore <notification@example.invalid>'};
 const transport={fetch:async(url,init)=>{requests.push([url,init]);return Response.json({id:'isolated-provider-ack'},{status:200})}};
 const result=await createDeliveryAdapters(env,transport).email({id,to:'confirmed@example.invalid',notifications:[{title:'Atualização',link:`/?contract=${id}`}]});
 assert.equal(result.status,'acknowledged');assert.equal(requests[0][0],'https://api.resend.com/emails');assert.equal(requests[0][1].redirect,'error');assert.equal(requests[0][1].headers['Idempotency-Key'],`eventcore-${id}`);
 const body=JSON.parse(requests[0][1].body);assert.deepEqual(body.to,['confirmed@example.invalid']);assert.ok(body.text.includes(`https://eventcore.space/?contract=${id}`));assert.ok(!('html' in body));
 assert.equal((await createDeliveryAdapters(env,{fetch:async()=>Response.json({})}).email({id,to:'confirmed@example.invalid',notifications:[{title:'Atualização',link:`/?contract=${id}`}]})).status,'retry');
});
test('real Web Push adapter recognizes expiration and never follows user endpoint URLs',async()=>{
 const env={NOTIFICATION_VAPID_PUBLIC_KEY:'fixture-public',NOTIFICATION_VAPID_PRIVATE_KEY:'fixture-private',NOTIFICATION_VAPID_SUBJECT:'mailto:test@example.invalid'};let sends=0;
 const adapter=createDeliveryAdapters(env,{sendNotification:async()=>{sends++;throw Object.assign(new Error('isolated expiration'),{statusCode:410})}});
 assert.equal((await adapter.push(subscription,{title:'Atualização',link:`/?assignment=${id}`})).status,'expired');assert.equal(sends,1);
 assert.equal((await adapter.push({...subscription,endpoint:'https://127.0.0.1/private'},{title:'Unsafe',link:`/?assignment=${id}`})).status,'retry');assert.equal(sends,1);
});
test('recovered already-acknowledged push batch finishes without repeating adapter sends',async()=>{
 let sends=0;const calls=[];const db={rpc:async(n,a)=>{calls.push([n,a]);return{error:null,data:n==='recheck_notification_batch'?true:n==='claim_notification_batches'?[{id,channel:'push',delivered_device_count:1,notifications:[{title:'Atualização',link:`/?assignment=${id}`}],devices:[]}]:null}}};
 await dispatchNotifications(db,{push:async()=>{sends++;return{status:'acknowledged'}},email:async()=>({status:'disabled'})});assert.equal(sends,0);assert.equal(calls.at(-1)[1].p_outcome,'acknowledged');
});
