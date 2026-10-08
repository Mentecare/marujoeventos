import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
const organizationId = '20000000-0000-4000-8000-000000000001';
const photoId = '30000000-0000-4000-8000-000000000001';
const objectPath = `10000000-0000-4000-8000-000000000001/${photoId}.webp`;
const image = await sharp({ create: { width: 12, height: 10, channels: 3, background: '#156341' } }).webp().toBuffer();

test('issuer logo authorizes metadata as caller and downloads only the stored avatar in the fixed bucket', async () => {
  const { quoteIssuerLogo } = await import('../lib/quote-pdf-logo.ts');
  const calls=[];
  const db={rpc:async(name,args)=>{calls.push({name,args});return {data:[{id:photoId,kind:'avatar',object_path:objectPath}],error:null}}};
  const storage=()=>({storage:{from:bucket=>({download:async path=>{calls.push({bucket,path});return {data:new Blob([image]),error:null}}})}});
  const logo=await quoteIssuerLogo(db, organizationId, storage);
  assert.equal((await sharp(logo).metadata()).format, 'png');
  assert.deepEqual(calls,[{name:'get_provider_photo_collection',args:{p_organization_id:organizationId}},{bucket:'eventcore-profile-photos',path:objectPath}]);
});

test('absent, unauthorized or unsafe avatar never reaches privileged Storage or arbitrary URLs', async () => {
  const { quoteIssuerLogo } = await import('../lib/quote-pdf-logo.ts');
  for(const result of [{data:[],error:null},{data:null,error:{message:'forbidden'}},{data:[{id:photoId,kind:'avatar',object_path:'https://169.254.169.254/private'}],error:null},{data:[{id:photoId,kind:'portfolio',object_path:objectPath}],error:null},{data:[{id:'different',kind:'avatar',object_path:objectPath}],error:null}]) {
    let privileged=0;
    const logo=await quoteIssuerLogo({rpc:async()=>result},organizationId,()=>{privileged++;throw Error('must not reach Storage')});
    assert.equal(logo,null);assert.equal(privileged,0);
  }
});

test('missing, malformed and oversized stored images fall back without breaking the sale document', async () => {
  const { quoteIssuerLogo } = await import('../lib/quote-pdf-logo.ts');
  const db={rpc:async()=>({data:[{id:photoId,kind:'avatar',object_path:objectPath}],error:null})};
  for(const result of [{data:null,error:{message:'missing'}},{data:new Blob([Buffer.from('bad')]),error:null},{data:new Blob([Buffer.alloc(3_000_001)]),error:null}]) {
    const logo=await quoteIssuerLogo(db,organizationId,()=>({storage:{from:()=>({download:async()=>result})}}));
    assert.equal(logo,null);
  }
});
