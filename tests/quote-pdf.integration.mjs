import {browserRuntime,pdfTool,python,evidence} from './runtime-tools.mjs';
// Actual Next Auth/RPC/Storage/PDF/UI path; only external services are isolated.
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import sharp from 'sharp';
import {createECDH} from 'node:crypto';
const require=createRequire(import.meta.url);
const {chromium,executablePath}=browserRuntime();
const output=process.env.EVENTCORE_PDF_OUTPUT||path.join(os.tmpdir(),'eventcore-task6-evidence');
const chromiumExecutable=executablePath;
await fs.mkdir(output,{recursive:true});
const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`,actorId=id(1),orgId=id(2),quoteId=id(3),photoId=id(4);
const user={id:actorId,aud:'authenticated',role:'authenticated',email:'fixture@example.invalid',email_confirmed_at:'2026-10-07T00:00:00Z',app_metadata:{provider:'email'},user_metadata:{}};
const expires=Math.floor(Date.now()/1000)+3600,token=[Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url'),Buffer.from(JSON.stringify({sub:actorId,role:'authenticated',aud:'authenticated',exp:expires})).toString('base64url'),'fixture'].join('.');
const profile={id:actorId,full_name:'Responsável Aurora',role:'freelancer',profile_type:'company',active:true,onboarding_completed:true,professional_status:'available',bio:'Trabalho real'};
const org={id:orgId,owner_profile_id:actorId,display_name:'Equipe Aurora',organization_type:'company',market_role:'provider',buyer_subtype:null,active:true,is_owner:true,can_operate:true,can_finance:true};
let quote={id:quoteId,revision:1,status:'draft',title:'Orçamento Aurora',issued_at:'2026-10-07T01:30:00Z',event_date:'2099-10-07',venue:'Local autorizado',valid_until:'2099-10-07',payment_terms:'Pix após o evento',show_unit_prices:true,client_total:5600,issuer:{id:orgId,display_name:'Equipe Aurora'},client:{display_name:'Cliente Aurora'},request_id:null,contract_id:null,items:[{id:id(5),label:'Equipe montagem',quantity:10,contract_days:2,planned_hours:8,client_unit_price:280,line_total:5600}],freelancer_unit_cost:'PRIVATE-COST-SECRET'};
const avatar=await sharp({create:{width:80,height:50,channels:3,background:'#156341'}}).webp().toBuffer();
let mode='logo',delayPdf=false,pendingPdf=null,activeRole='provider',deliveryMode='ack';const calls=[];
const preferences={mode:'all_eligible',cadence:'immediate',email_enabled:false,push_enabled:false,paused_until:null,specialty_ids:[],regions:[],date_from:null,date_to:null};
const syntheticVapid=require('web-push').generateVAPIDKeys(),receiver=createECDH('prime256v1');receiver.generateKeys();
const subscription={endpoint:'https://fcm.googleapis.com/fcm/send/fixture',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:Buffer.alloc(16,1).toString('base64url')}};
const boundary=http.createServer(async(req,res)=>{
 try {
  const url=new URL(req.url,'http://localhost');let raw='';for await(const chunk of req)raw+=chunk;const args=raw?JSON.parse(raw):null;
  const call={path:url.pathname,key:req.headers.apikey,authorization:req.headers.authorization,args};calls.push(call);
  const headers={'content-type':'application/json','access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,PUT,PATCH,OPTIONS'};
  const json=(data,status=200)=>{res.writeHead(status,headers);res.end(JSON.stringify(data))};
  if(req.method==='OPTIONS')return json(null,204);
  if(url.pathname==='/auth/v1/user')return req.headers.authorization===`Bearer ${token}`?json(user):json({message:'Invalid JWT'},401);
  if(url.pathname==='/rest/v1/profiles')return json(activeRole==='worker'?{...profile,profile_type:'freelancer'}:profile);
  if(url.pathname==='/test/email'){assert.equal(req.headers['idempotency-key'],'eventcore-'+id(100));assert.deepEqual(args.to,['fixture@example.invalid']);assert.equal(args.from,'EventCore <notification@example.invalid>');assert.ok(args.text.includes('https://eventcore.space/?assignment='+id(7)));return json(deliveryMode==='no-email-ack'?{}:{id:'provider-fixture-ack'});}
  if(url.pathname==='/test/push'){assert.equal(args.hostname,'fcm.googleapis.com');assert.equal(args.path,'/fcm/send/fixture');assert.equal(Number(args.headers.TTL),300);assert.match(args.headers.Authorization,/^vapid /);const payload=require('http_ece').decrypt(Buffer.from(args.body,'base64'),{version:'aes128gcm',privateKey:receiver,authSecret:subscription.keys.auth});assert.equal(JSON.parse(payload.toString()).link,'/?assignment='+id(7));return json({},deliveryMode==='expired'?410:201);}
  if(url.pathname.startsWith('/storage/v1/object/')){
   assert.equal(req.headers.apikey,'fixture-service');assert.equal(url.pathname,`/storage/v1/object/eventcore-profile-photos/${actorId}/${photoId}.webp`);
   res.writeHead(200,{'content-type':'image/webp'});return res.end(avatar);
  }
  const name=url.pathname.split('/').at(-1);
  if(url.pathname.includes('/rpc/')){
   if(['claim_notification_batches','recheck_notification_batch','finish_notification_batch','ack_notification_device','disable_notification_device'].includes(name)){
    assert.equal(req.headers.apikey,'fixture-service');
    if(name==='claim_notification_batches')return json([{id:id(100),lease_token:id(110),channel:'email',to:'fixture@example.invalid',notifications:[{title:'Convite',link:'/?assignment='+id(7)}],devices:[]},{id:id(101),lease_token:id(111),channel:'push',to:null,notifications:[{title:'Convite',link:'/?assignment='+id(7)}],devices:[{id:id(102),subscription}]}]);
    if(name==='recheck_notification_batch')return json(true);
    return json(null);
   }
   assert.equal(req.headers.apikey,'fixture-public','commercial/photo RPC must use caller public key');assert.equal(req.headers.authorization,`Bearer ${token}`);
   if(name==='get_sale_quote'){
    assert.deepEqual(args,{p_proposal_id:quoteId});
    if(mode==='denied')return json({code:'P0001',message:'forbidden'},400);
    const snapshot=structuredClone(quote);
    if(delayPdf){delayPdf=false;pendingPdf=()=>json(snapshot);return;}
    return json(snapshot);
   }
   if(name==='get_provider_photo_collection'){
    assert.deepEqual(args,{p_organization_id:orgId});
    return json(mode==='absent'?[]:mode==='unsafe'?[{id:photoId,kind:'avatar',object_path:'https://169.254.169.254/private'}]:[{id:photoId,kind:'avatar',object_path:`${actorId}/${photoId}.webp`}]);
   }
   if(name==='get_commercial_context')return json({profile_id:actorId,identity_complete:true,document_type:'cpf',document_last4:'4725',organizations:activeRole==='worker'?[]:[org]});
   if(name==='get_my_work_assignments')return json([]);
   if(name==='get_my_schedule')return json({events:[],services:[]});
   if(name==='get_notification_center')return json({preferences,email_confirmed:true,notifications:[],devices:[]});
   if(name==='get_commercial_workspace')return json({requests:[],quotes:[quote],contracts:[],receipts:[]});
   if(name==='save_sale_quote'){quote={...quote,...args.p_quote,revision:quote.revision+1,items:args.p_items.map(i=>({...i,id:id(5),line_total:i.quantity*i.contract_days*i.client_unit_price}))};return json(quoteId);}
   if(['get_organization_roster','get_work_finance_index','get_work_opportunities','get_professional_directory','get_profile_photo_collection'].includes(name))return json([]);
   throw Error('Unexpected RPC '+name);
  }
  const tables={specialties:[{id:id(6),slug:'loader',name:'Carregador',active:true,sort_order:1}],profile_specialties:[],organizations:activeRole==='worker'?[]:[org],freelancers:[{id:id(20),profile_id:actorId,full_name:'Responsável Aurora',active:true}],events:[],job_applications:[],ratings:[],clients:[],profile_photo_cleanup:[]};
  assert.ok(name in tables,'Unexpected raw table '+name);
  if(name==='profile_photo_cleanup')assert.equal(req.headers.apikey,'fixture-service');
  else if(name!=='specialties')assert.equal(req.headers.apikey,'fixture-public','raw commercial read cannot use service role');
  return json(req.headers.accept?.includes('application/vnd.pgrst.object+json')?tables[name][0]||null:tables[name]);
 }catch(error){res.writeHead(500,{'content-type':'application/json'});res.end(JSON.stringify({error:error.message}));}
});
const production = process.env.EVENTCORE_PDF_SERVER_MODE === 'production';
await new Promise((resolve,reject)=>{boundary.once('error',reject);boundary.listen(production?18765:0,'127.0.0.1',resolve)});
const boundaryUrl=`http://127.0.0.1:${boundary.address().port}`,port=20000+Math.floor(Math.random()*30000),base=`http://127.0.0.1:${port}`;
let logs='';const server=spawn(process.execPath,['node_modules/next/dist/bin/next',production?'start':'dev','--hostname','127.0.0.1','--port',String(port)],{env:{...process.env,NEXT_TELEMETRY_DISABLED:'1',NEXT_PUBLIC_SUPABASE_URL:boundaryUrl,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'fixture-public',SUPABASE_SERVICE_ROLE_KEY:'fixture-service',NOTIFICATION_DISPATCH_SECRET:'a'.repeat(32),NOTIFICATION_VAPID_PUBLIC_KEY:syntheticVapid.publicKey,NOTIFICATION_VAPID_PRIVATE_KEY:syntheticVapid.privateKey,NOTIFICATION_VAPID_SUBJECT:'mailto:test@example.invalid',RESEND_API_KEY:'fixture-resend',NOTIFICATION_EMAIL_FROM:'EventCore <notification@example.invalid>',EVENTCORE_TEST_DELIVERY_BOUNDARY:boundaryUrl,NODE_OPTIONS:`${process.env.NODE_OPTIONS||''} --import ${path.resolve('tests/delivery-provider-boundary.mjs')}`},stdio:['ignore','pipe','pipe']});
server.stdout.on('data',c=>logs+=c);server.stderr.on('data',c=>logs+=c);
let browser;
const route=`${base}/api/quotes/${quoteId}/pdf`,headers={Authorization:`Bearer ${token}`};
const text=file=>execFileSync(pdfTool('pdftotext'),[file,'-'],{encoding:'utf8'});
async function pdf(name,details='totals'){
 const response=await fetch(route+'?details='+details,{headers});assert.equal(response.status,200,await response.clone().text());assert.equal(response.headers.get('content-type'),'application/pdf');assert.equal(response.headers.get('cache-control'),'private, no-store');assert.equal(response.headers.get('x-content-type-options'),'nosniff');
 const file=path.join(output,name+'.pdf');await fs.writeFile(file,Buffer.from(await response.arrayBuffer()));const links=JSON.parse(execFileSync(python,['-c','import fitz,json,sys; print(json.dumps([[link.get("uri") for link in page.get_links()] for page in fitz.open(sys.argv[1])]))',file],{encoding:'utf8'}));assert.ok(links.length);for(const pageLinks of links)assert.deepEqual(pageLinks,['https://eventcore.space']);assert.match(text(file),/R\$ 5\.600,00/);assert.doesNotMatch(text(file),/PRIVATE-COST-SECRET|freelancer_unit_cost/);return file;
}
try {
 for(let i=0;i<100;i++){if(server.exitCode!==null)throw Error(logs);try{await fetch(route);break}catch{await new Promise(r=>setTimeout(r,200));}}
 calls.length=0;assert.equal((await fetch(route)).status,401);assert.equal(calls.length,0);
 assert.equal((await fetch(route,{headers:{Authorization:'Bearer invalid'}})).status,401);
 calls.length=0;mode='denied';assert.equal((await fetch(route,{headers})).status,404);assert.equal(calls.some(c=>c.path.includes('photo_collection')||c.path.includes('/storage/')),false);
 mode='logo';const savedClient=quote.client;quote.client={display_name:'東京'};const unsupported=await fetch(route,{headers});assert.equal(unsupported.status,422);assert.equal((await unsupported.json()).error,'unsupported_pdf_text');quote.client=savedClient;calls.length=0;const units=await pdf('route-units','units');
 assert.match(text(units),/R\$ 280,00/);assert.match(execFileSync(pdfTool('pdfimages'),['-list',units],{encoding:'utf8'}),/\simage\s+80\s+50/);
 assert.deepEqual(calls.map(c=>c.path),['/auth/v1/user','/rest/v1/profiles','/rest/v1/rpc/get_sale_quote','/rest/v1/rpc/get_provider_photo_collection',`/storage/v1/object/eventcore-profile-photos/${actorId}/${photoId}.webp`]);
 mode='absent';calls.length=0;const totals=await pdf('route-totals');assert.doesNotMatch(text(totals),/R\$ 280,00/);assert.equal(calls.some(c=>c.path.includes('/storage/')),false);
 mode='unsafe';calls.length=0;await pdf('route-unsafe-fallback');assert.equal(calls.some(c=>c.path.includes('/storage/')),false);
 quote.show_unit_prices=false;assert.equal((await fetch(route+'?details=units',{headers})).status,400);quote.show_unit_prices=true;mode='logo';
 console.log('PASS: actual Next route Auth 401 / tenant 404 / unit policy 400 / sale PDF 200; caller RPC + fixed-bucket Storage image; absent/unsafe image fallback; internal fields absent');
 calls.length=0;assert.equal((await fetch(base+'/api/internal/notifications',{method:'POST',headers:{Authorization:'Bearer wrong'}})).status,401);assert.equal(calls.length,0);
 for(const scenario of ['ack','no-email-ack','expired']){
  deliveryMode=scenario;calls.length=0;const response=await fetch(base+'/api/internal/notifications',{method:'POST',headers:{Authorization:'Bearer '+'a'.repeat(32)}});assert.equal(response.status,200);const result=await response.json();assert.equal(result.claimed,2);assert.equal(result.acknowledged,scenario==='ack'?2:1);assert.equal(result.retry,scenario==='no-email-ack'?1:0);assert.equal(result.suppressed,scenario==='expired'?1:0);
  assert.equal(calls.filter(c=>c.path==='/test/email').length,1);assert.equal(calls.filter(c=>c.path==='/test/push').length,1);assert.equal(calls.some(c=>c.path.endsWith('/ack_notification_device')),scenario!=='expired');assert.equal(calls.some(c=>c.path.endsWith('/disable_notification_device')),scenario==='expired');
  console.log(`PASS: actual Next dispatcher ${scenario}, actual email/Web Push adapter payloads through isolated provider transports, correct RPC acknowledgment/retry/expiry`);
 }
 browser=await chromium.launch({executablePath:chromiumExecutable,headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu']});
 for(const width of [390,1280]){
  const context=await browser.newContext({viewport:{width,height:844},locale:'pt-BR',serviceWorkers:'block'});
  await context.addInitScript(({token,user,expires})=>localStorage.setItem('sb-127-auth-token',JSON.stringify({access_token:token,refresh_token:'fixture',expires_in:3600,expires_at:expires,token_type:'bearer',user})),{token,user,expires});
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base,{waitUntil:'networkidle'});await page.locator('.appHeader').waitFor();
  await page.locator(width<851?'.mobileNav':'.sidebar nav').getByRole('button',{name:'Clientes',exact:true}).click();
  const tools=page.locator('.quotePdfTools');await tools.getByRole('button',{name:'Visualizar PDF'}).click();await tools.locator('iframe').waitFor();
  await tools.getByLabel('Somente totais').check();await assert.rejects(tools.locator('iframe').waitFor({state:'visible',timeout:500}),undefined,'switching detail invalidates old unit preview');
  await tools.getByRole('button',{name:'Visualizar PDF'}).click();await tools.locator('iframe').waitFor();
  const downloadEvent=page.waitForEvent('download');await tools.getByRole('button',{name:'Baixar PDF'}).click();const download=await downloadEvent;const file=path.join(output,`browser-${width}-totals.pdf`);await download.saveAs(file);assert.doesNotMatch(text(file),/R\$ 280,00/);
  await page.getByRole('button',{name:'Editar rascunho'}).click();const editor=page.locator('form').filter({has:page.getByRole('heading',{name:'Editar rascunho',exact:true})});await editor.locator('[name=title]').fill('Orçamento revisado');await editor.getByRole('button',{name:'Salvar rascunho'}).click();await page.getByText('Rascunho salvo.',{exact:true}).waitFor();assert.equal(await tools.locator('iframe').count(),0,'new quote revision cannot keep old preview');
  await tools.getByRole('button',{name:'Visualizar PDF'}).click();await tools.locator('iframe').waitFor();
  delayPdf=true;await tools.getByRole('button',{name:'Visualizar PDF'}).click();for(let n=0;!pendingPdf&&n<50;n++)await new Promise(r=>setTimeout(r,20));assert.ok(pendingPdf);
  await tools.getByLabel('Totais e unitários').check();pendingPdf();pendingPdf=null;await tools.getByRole('button',{name:'Visualizar PDF'}).waitFor();assert.equal(await tools.locator('iframe').count(),0,'old in-flight PDF cannot reappear after switching details');
  await tools.getByRole('button',{name:'Visualizar PDF'}).click();await tools.locator('iframe').waitFor();await page.screenshot({path:path.join(output,`quote-${width}.png`),fullPage:true});
  const g=await page.evaluate(()=>({width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth}));assert.ok(g.scroll<=g.width+1,'PDF controls responsive');assert.deepEqual(errors,[]);
  console.log(`PASS: browser ${width} real Next preview/download, totals switch, revision invalidation, stale request rejection, responsive controls`);await context.close();
 }
 activeRole='worker';const context=await browser.newContext({viewport:{width:390,height:844},locale:'pt-BR',serviceWorkers:'block'});
 await context.addInitScript(({token,user,expires})=>{localStorage.setItem('sb-127-auth-token',JSON.stringify({access_token:token,refresh_token:'fixture',expires_in:3600,expires_at:expires,token_type:'bearer',user}));window.pushPermissionRequests=0;Notification.requestPermission=async()=>{window.pushPermissionRequests++;return 'denied'};Object.defineProperty(Notification,'permission',{get:()=> 'default'});},{token,user,expires});
 const page=await context.newPage();await page.goto(base,{waitUntil:'networkidle'});await page.locator('.appHeader').waitFor();await page.locator('.mobileNav').getByRole('button',{name:'Dashboard',exact:true}).click();await page.getByText('conclusão ou presença validada',{exact:true}).waitFor();await page.screenshot({path:path.join(output,'worker-dashboard-390.png'),fullPage:true});
 await page.locator('.accountMenu summary').click();await page.getByRole('button',{name:'Notificações e preferências',exact:true}).click();await page.getByRole('heading',{name:'Suas atualizações'}).waitFor();await page.getByText('Esta preferência controla alertas nos dispositivos já registrados. Para autorizar este aparelho, use “Ativar push neste dispositivo”.',{exact:true}).waitFor();assert.equal(await page.evaluate(()=>window.pushPermissionRequests),0);await page.getByRole('button',{name:'Ativar push neste dispositivo'}).click();await page.getByText('Permissão não concedida. Sua central e e-mail continuam disponíveis.',{exact:true}).waitFor();assert.equal(await page.evaluate(()=>window.pushPermissionRequests),1);await page.screenshot({path:path.join(output,'worker-push-declined-390.png'),fullPage:true});await context.close();console.log('PASS: worker dashboard evidence wording and explicit device authorization, no automatic push prompt, decline keeps center available');
}finally{
 if(pendingPdf)pendingPdf();await browser?.close();if(server.exitCode===null&&server.signalCode===null){const exited=once(server,'exit');server.kill('SIGTERM');await exited;}boundary.closeAllConnections();await new Promise(r=>boundary.close(r));
 assert.equal((logs.match(/profile_photo_cleanup_deferred/g)||[]).length,0,'complete shell cleanup boundary emits no deferred warning');
 await fs.writeFile(path.join(output,'next-pdf-server.log'),logs);
}
