import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import vm from 'node:vm';
const source=await fs.readFile(new URL('../public/sw.js',import.meta.url),'utf8');
const id='10000000-0000-4000-8000-000000000001';
function worker(){const handlers={},notifications=[],opens=[],cached=[];const context={URL,Response,self:{location:{origin:'https://eventcore.space'},addEventListener:(n,h)=>handlers[n]=h,registration:{showNotification:async(...a)=>notifications.push(a)},clients:{matchAll:async()=>[],openWindow:async u=>opens.push(u),claim:async()=>{}}},caches:{open:async()=>({put:(r)=>cached.push(r),addAll:async()=>{}}),match:async()=>null},fetch:async()=>({ok:true,headers:new Headers({'cache-control':'no-store'}),clone(){return this}})};vm.runInNewContext(source,context);return{handlers,notifications,opens,cached}}
test('push only renders allowlisted exact internal destinations',async()=>{const w=worker();assert.equal(typeof w.handlers.push,'function');let done;w.handlers.push({data:{json:()=>({title:'Convite',link:`/?assignment=${id}`})},waitUntil:p=>done=p});await done;assert.equal(w.notifications[0][1].data.link,`/?assignment=${id}`);w.handlers.push({data:{json:()=>({title:'Unsafe',link:'https://evil.test'})},waitUntil:p=>done=p});await done;assert.equal(w.notifications.length,1)});
test('notification click cannot navigate to a private API or external redirect',async()=>{const w=worker();assert.equal(typeof w.handlers.notificationclick,'function');for(const link of [`/?contract=${id}`,'/api/profile/photos','//evil.test',`/?contract=${id}&next=evil`]){let done;w.handlers.notificationclick({notification:{close(){},data:{link}},waitUntil:p=>done=p});await done}assert.deepEqual(w.opens,[`https://eventcore.space/?contract=${id}`])});
test('service worker never handles or caches public previews, authenticated RSC and protected API',async()=>{const w=worker();for(const path of [`/o/${id}`,'/api/notifications','/?_rsc=private','/private.pdf']){let handled=false;w.handlers.fetch({request:{url:'https://eventcore.space'+path,method:'GET',mode:'cors',headers:new Headers()},respondWith(){handled=true}});assert.equal(handled,false,path)}assert.equal(w.cached.length,0)});

test('commercial push opens only the exact request or proposal destination',async()=>{
 const w=worker();
 for(const kind of ['request','proposal']){
  let done;const link=`/?${kind}=${id}`;
  w.handlers.push({data:{json:()=>({title:'Atualização comercial',link})},waitUntil:p=>done=p});await done;
  assert.equal(w.notifications.at(-1)?.[1].data.link,link);
  w.handlers.notificationclick({notification:{close(){},data:{link}},waitUntil:p=>done=p});await done;
 }
 assert.deepEqual(w.opens,[`https://eventcore.space/?request=${id}`,`https://eventcore.space/?proposal=${id}`]);
});

test('repeat notification navigates an existing matching URL before focusing its changed React view',async()=>{
 const w=worker(),actions=[];const target=`https://eventcore.space/?assignment=${id}`;
 // The document URL still matches although the app view has moved to Dashboard.
 const window={url:target,navigate:async u=>actions.push(['navigate',u]),focus:async()=>actions.push(['focus'])};
 const handlers={};const context={URL,Response,self:{location:{origin:'https://eventcore.space'},addEventListener:(n,h)=>handlers[n]=h,clients:{matchAll:async()=>[window]}}};vm.runInNewContext(source,context);
 let done;handlers.notificationclick({notification:{close(){},data:{link:`/?assignment=${id}`}},waitUntil:p=>done=p});await done;
 assert.deepEqual(actions,[['navigate',target],['focus']]);
});

test('legacy signup is blocked while current server registration remains unaffected',async()=>{
 const w=worker();let promise=null;
 w.handlers.fetch({request:{url:'https://mzwlchgxkuqptiqyznqd.supabase.co/auth/v1/signup',method:'POST',mode:'cors',headers:new Headers()},respondWith(x){promise=Promise.resolve(x)}});
 assert.ok(promise);
 const result=await promise;
 assert.equal(result.status,409);
 assert.equal((await result.json()).code,'eventcore_registration_update_required');
 let intercepted=false;
 w.handlers.fetch({request:{url:'https://eventcore.space/api/auth/register',method:'POST',mode:'cors',headers:new Headers()},respondWith(){intercepted=true}});
 assert.equal(intercepted,false);
});
