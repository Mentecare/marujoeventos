// Actual Next routes/renderer; only Supabase's HTTP platform boundary is isolated locally.
// SQL permissions/triggers/outbox are independently verified by notifications-security.sql.
import http from 'node:http';
import assert from 'node:assert/strict';
const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`,profileId=id(1),serviceId=id(5),assignmentId=id(7);
let preferences={mode:'relevant',cadence:'immediate',email_enabled:false,push_enabled:false,paused_until:null,specialty_ids:[],regions:[],date_from:null,date_to:null};
let publicAvailable=true;
const calls=[];
const server=http.createServer(async(req,res)=>{
 let body='';for await(const c of req)body+=c;const args=body?JSON.parse(body):null,url=new URL(req.url,'http://127.0.0.1:18765');calls.push({path:url.pathname,args});let data;
 if(url.pathname==='/auth/v1/user')data={id:profileId,email:'fixture@example.invalid',email_confirmed_at:'2026-10-06T00:00:00Z',app_metadata:{provider:'email'},user_metadata:{}};
 else if(url.pathname==='/rest/v1/profiles')data={id:profileId,active:true};
 else if(url.pathname==='/rest/v1/rpc/get_notification_center')data={preferences,email_confirmed:true,notifications:[{id:id(101),title:'Atualização do seu convite ou contrato de trabalho',link:`/?assignment=${assignmentId}`,created_at:'2026-10-06T00:00:00Z',read_at:null}],devices:[]};
 else if(url.pathname==='/rest/v1/rpc/save_notification_preferences'){preferences=args.p_preferences;data=null}
 else if(url.pathname==='/rest/v1/rpc/mark_notification_read')data=null;
 else if(url.pathname==='/rest/v1/rpc/get_public_opportunity')data=publicAvailable&&args.p_service_id===serviceId?{id:serviceId,title:'Oportunidade: Carregador',role:'Carregador',provider:'Equipe Aurora',days:2,region:'Barra',date:'2026-10-07',description:'Descrição pública'}:null;
 else if(url.pathname==='/rest/v1/rpc/claim_notification_batches')data=[];
 else{res.writeHead(404);res.end(JSON.stringify({message:'unimplemented_isolated_boundary'}));return}
 res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(data));
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(18765,'127.0.0.1',resolve)});
globalThis.eventcoreNotificationFixture={closePublic:()=>publicAvailable=false,assertPreferences:()=>{assert.deepEqual(preferences.regions,['Rio','Niterói']);assert.equal(preferences.cadence,'daily');assert.equal(preferences.email_enabled,true)},assertCalls:()=>{assert.ok(calls.some(c=>c.path==='/rest/v1/rpc/get_notification_center'));assert.ok(calls.some(c=>c.path==='/rest/v1/rpc/save_notification_preferences'))}};
process.env.EVENTCORE_NOTIFICATION_CHECK='1';process.env.EVENTCORE_CHECK_ROLE=process.env.EVENTCORE_CHECK_ROLE||'worker';process.env.EVENTCORE_CHECK_WIDTH=process.env.EVENTCORE_CHECK_WIDTH||'390';
try{await import('./aligned-flows.browser.mjs');if(process.env.EVENTCORE_CHECK_ROLE==='worker')globalThis.eventcoreNotificationFixture.assertCalls();console.log('PASS: real Next notification routes, public preview and deep-target checks; only local platform/provider fixtures')}
finally{await new Promise(resolve=>server.close(resolve));delete globalThis.eventcoreNotificationFixture}
