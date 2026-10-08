import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import sharp from 'sharp';
import { startPhotoBoundary, photoToken, PHOTO_OTHER, PHOTO_FREELANCER, PHOTO_SERVER_KEY } from './profile-photo-boundary.mjs';

// Run after a build with NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765
const boundary=await startPhotoBoundary();
const port=20000+Math.floor(Math.random()*30000),base=`http://127.0.0.1:${port}/api/profile/photos`;
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','--hostname','127.0.0.1','--port',String(port)],{env:{...process.env,SUPABASE_SERVICE_ROLE_KEY:PHOTO_SERVER_KEY},stdio:['ignore','ignore','pipe']});
let diagnostics='';server.stderr.on('data',chunk=>{diagnostics+=chunk;process.stderr.write(chunk)});
const bytes=await sharp({create:{width:16,height:12,channels:3,background:'#445566'}}).jpeg().toBuffer();
const auth={Authorization:`Bearer ${photoToken()}`};
async function upload({kind='portfolio',declaration='true',file=bytes,type='image/jpeg'}={}) {
  const data=new FormData();data.set('kind',kind);data.set('caption','Trabalho de teste');data.set('real_declaration',declaration);data.set('photo',new File([file],'fixture.jpg',{type}));
  return fetch(base,{method:'POST',headers:auth,body:data});
}
try {
  let ready=false;for(let i=0;i<60;i++){try{await fetch(base);ready=true;break}catch{await new Promise(resolve=>setTimeout(resolve,200))}}
  assert.ok(ready);
  assert.equal((await fetch(base)).status,401);
  assert.equal((await fetch(base,{headers:{Authorization:'Bearer invalid'}})).status,401);
  assert.equal((await upload({declaration:'false'})).status,400);
  assert.equal((await upload({file:Buffer.from('fake JPEG')})).status,400);
  assert.equal((await upload({file:Buffer.alloc(3_000_001)})).status,413);
  const oversized=new FormData();oversized.set('kind','portfolio');oversized.set('caption','');oversized.set('real_declaration','true');oversized.set('photo',new File([bytes],'fixture.jpg',{type:'image/jpeg'}));oversized.set('ignored','x'.repeat(4_000_000));
  const encoded=new Request('http://localhost',{method:'POST',body:oversized});
  let rejected=false;
  try {rejected=(await fetch(base,{method:'POST',headers:{...auth,'Content-Type':encoded.headers.get('content-type'),'Connection':'close'},body:encoded.body,duplex:'half'})).status===413;}
  catch(error){rejected=error.cause?.code==='ECONNRESET';} // Next may close the oversized chunked upload while the client is still writing.
  assert.ok(rejected,'Oversized chunked multipart must be rejected before saving');
  assert.equal(boundary.objects.size,0);
  let avatar=await upload({kind:'avatar'});assert.equal(avatar.status,201);const old=(await avatar.json()).id;
  avatar=await upload({kind:'avatar'});assert.equal(avatar.status,201);
  assert.equal(boundary.photos.size,1);assert.equal(boundary.objects.size,1);
  assert.ok(![...boundary.objects.keys()].some(path=>path.includes(old)));
  for(let i=0;i<10;i++)assert.equal((await upload()).status,201);
  assert.equal((await upload()).status,409);assert.equal(boundary.objects.size,11);
  const ownResponse=await fetch(base,{headers:auth});assert.match(ownResponse.headers.get('cache-control'),/no-store/);
  const own=await ownResponse.json();assert.equal(own.portfolio.length,10);assert.ok(own.avatar.url.includes('/object/sign/'));
  const image=await fetch(own.portfolio[0].url);assert.equal((await sharp(Buffer.from(await image.arrayBuffer())).metadata()).format,'webp');
  const id=own.portfolio[0].id;
  boundary.state.loseSaveResponse=true;
  assert.equal((await upload({kind:'avatar'})).status,201,'A committed photo survives a lost RPC response');
  boundary.state.loseSaveResponse=false;assert.equal(boundary.objects.size,11);
  assert.equal((await fetch(base+`?photo_id=${id}`,{method:'DELETE',headers:{Authorization:`Bearer ${photoToken(PHOTO_OTHER)}`}})).status,200);
  assert.equal(boundary.photos.size,11,'Another account must not remove the owner photo');
  boundary.state.failDelete=true;
  assert.equal((await fetch(base+`?photo_id=${id}`,{method:'DELETE',headers:auth})).status,503);
  assert.equal(boundary.photos.size,11);assert.equal(boundary.objects.size,11);
  assert.equal((await fetch(base,{headers:auth})).status,200);
  boundary.state.failDelete=false;
  boundary.state.failRemove=true;
  assert.equal((await fetch(base+`?photo_id=${id}`,{method:'DELETE',headers:auth})).status,200);assert.equal(boundary.photos.size,10);
  assert.equal(boundary.objects.size,11,'A failed storage cleanup is retained for retry');
  assert.equal((await fetch(base,{headers:auth})).status,200,'A storage outage must not block the remaining gallery');
  boundary.state.failRemove=false;
  assert.equal((await fetch(base,{headers:auth})).status,200);
  assert.equal((await fetch(base+`?photo_id=${id}`,{method:'DELETE',headers:auth})).status,200);
  assert.equal((await fetch(base+`?photo_id=${id}`,{method:'DELETE',headers:auth})).status,200);
  assert.equal(boundary.photos.size,10);assert.equal(boundary.objects.size,10);
  assert.equal(boundary.cleanup.size,0);
  boundary.state.failSave=true;
  assert.equal((await upload()).status,503);assert.equal(boundary.objects.size,10,'Failed metadata save cleans the staged upload');
  boundary.state.failSave=false;
  assert.equal((await upload()).status,201);
  const contractor=await fetch(base+`?freelancer_id=${PHOTO_FREELANCER}`,{headers:{Authorization:`Bearer ${photoToken(PHOTO_OTHER)}`}});
  assert.equal(contractor.status,200);assert.equal((await contractor.json()).portfolio.length,10);
  assert.equal((await fetch(base+`?freelancer_id=${PHOTO_OTHER}`,{headers:auth})).status,403);
  const missing=[...boundary.photos.values()].find(photo=>photo.kind==='portfolio');
  boundary.objects.delete(missing.object_path);
  const recoverable=await fetch(base,{headers:auth});assert.equal(recoverable.status,200);
  const collection=await recoverable.json();assert.equal(collection.portfolio.length,10);
  assert.equal(collection.portfolio.find(photo=>photo.id===missing.id).url,'');
  assert.equal((await fetch(base+`?photo_id=${missing.id}`,{method:'DELETE',headers:auth})).status,200);
  assert.ok(!boundary.photos.has(missing.id),'A missing object can still be removed by its owner');
  boundary.state.failSign=true;
  assert.equal((await fetch(base,{headers:auth})).status,503);
  assert.equal((diagnostics.match(/profile_photo_cleanup_deferred/g)||[]).length,2,'exact fault-injected cleanup diagnostics; unexpected extra warnings fail');
  console.log('PASS: real Next API and Sharp; auth, declaration, invalid/large files, normalization, avatar replacement, quota/cleanup, deletion retry/idempotency, owner isolation, contractor gallery and private signing');
} finally {server.kill();await boundary.close();}
