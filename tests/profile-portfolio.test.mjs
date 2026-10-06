import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import ts from 'typescript';
const require = createRequire(import.meta.url);
class PhotoError extends Error { constructor(code,status=400) {super(code);this.code=code;this.status=status;} }
function load(relative,dependencies) {
  const compiled=ts.transpileModule(readFileSync(new URL(relative,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
  const module={exports:{}};
  new Function('require','module','exports',compiled)(id=>dependencies[id]??require(id),module,module.exports);
  return module.exports;
}
const server=load('../lib/profile-photo-server.ts',{'@/lib/supabase-server':{serviceSupabase(){throw new Error('unused');}},'@/lib/profile-photo-input':{PhotoError}});
const organization='20000000-0000-4000-8000-000000000001';
function fixture(error=null) {
  const calls=[],signed=[];
  return {calls,signed,id:'actor',db:{rpc:async(name,args)=>{calls.push({name,args});return {data:[{id:'photo',kind:'portfolio',caption:'Actual work',object_path:'authorized-owner/photo.webp',created_at:'2026-10-06'}],error};}},admin:{storage:{from:()=>({createSignedUrls:async(paths,seconds)=>{signed.push({paths,seconds});return {data:[{signedUrl:'https://example.invalid/signed'}],error:null};}})}}};
}
test('provider portfolio signs only paths from the caller-authorized provider RPC',async()=>{
  const actor=fixture();
  const result=await server.signedPhotoCollection(actor,null,organization);
  assert.deepEqual(actor.calls,[{name:'get_provider_photo_collection',args:{p_organization_id:organization}}]);
  assert.deepEqual(actor.signed,[{paths:['authorized-owner/photo.webp'],seconds:1200}]);
  assert.equal(result.portfolio[0].url,'https://example.invalid/signed');
});
test('provider portfolio authorization rejection happens before privileged storage signing',async()=>{
  const actor=fixture({message:'forbidden'});
  await assert.rejects(()=>server.signedPhotoCollection(actor,null,organization),error=>error.code==='forbidden'&&error.status===403);
  assert.deepEqual(actor.signed,[]);
});
test('photo GET supports provider organizations and rejects ambiguous or invalid targets',async()=>{
  const actor=fixture();
  const route=load('../app/api/profile/photos/route.ts',{'@/lib/profile-photo-input':{PhotoError},'@/lib/profile-photos':{PHOTO_MAX_BYTES:3000000},'@/lib/profile-photo-server':{...server,photoActor:async()=>actor,drainPhotoCleanup:async()=>{}}});
  const response=await route.GET(new Request(`https://example.invalid/api/profile/photos?organization_id=${organization}`));
  assert.equal(response.status,200);
  assert.deepEqual(actor.calls,[{name:'get_provider_photo_collection',args:{p_organization_id:organization}}]);
  for(const query of [`organization_id=invalid`,`organization_id=${organization}&freelancer_id=60000000-0000-4000-8000-000000000001`]) {
    actor.calls.length=0;
    const rejected=await route.GET(new Request(`https://example.invalid/api/profile/photos?${query}`));
    assert.equal(rejected.status,404);assert.equal(actor.calls.length,0);
  }
});
