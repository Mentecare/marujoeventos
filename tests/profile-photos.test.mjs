import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { boundedPhotoForm, normalizeProfilePhoto, validatePhotoFields, PHOTO_MAX_BYTES } from '../lib/profile-photo-input.ts';

// Tiny solid pixels are file-format fixtures only; they are never shown as work photos.
const jpeg = await sharp({create:{width:8,height:6,channels:3,background:'#556677'}}).jpeg().toBuffer();
const png = await sharp({create:{width:8,height:6,channels:4,background:'#556677'}}).png().toBuffer();
const webp = await sharp(png).webp().toBuffer();

test('real image decoding normalizes accepted formats and preserves orientation without metadata', async () => {
  for (const [bytes,type] of [[jpeg,'image/jpeg'],[png,'image/png'],[webp,'image/webp']]) {
    const result=await normalizeProfilePhoto(bytes,type);
    const meta=await sharp(result).metadata();
    assert.equal(meta.format,'webp');assert.equal(meta.width,8);assert.equal(meta.height,6);
    assert.equal(meta.exif,undefined);assert.ok(result.length<=PHOTO_MAX_BYTES);
  }
  const rotated=await sharp(jpeg).withMetadata({orientation:6}).jpeg().toBuffer();
  const meta=await sharp(await normalizeProfilePhoto(rotated,'image/jpeg')).metadata();
  assert.equal(meta.width,6);assert.equal(meta.height,8);assert.equal(meta.orientation,undefined);
});

test('uploaded photos are bounded and MIME labels cannot substitute for valid bytes', async () => {
  for(const [bytes,type] of [[Buffer.from('not a photo'),'image/jpeg'],[png,'image/jpeg'],[Buffer.from('<svg/>'),'image/svg+xml'],[Buffer.alloc(PHOTO_MAX_BYTES+1),'image/jpeg'],[Buffer.alloc(0),'image/png']]) {
    await assert.rejects(normalizeProfilePhoto(bytes,type));
  }
  const huge=await sharp({create:{width:7000,height:7000,channels:3,background:'#112233'}}).png().toBuffer();
  await assert.rejects(normalizeProfilePhoto(huge,'image/png'));
  const resized=await sharp({create:{width:2000,height:1000,channels:3,background:'#112233'}}).jpeg().toBuffer();
  const meta=await sharp(await normalizeProfilePhoto(resized,'image/jpeg')).metadata();
  assert.equal(meta.width,1600);assert.equal(meta.height,800);
  const animatedGif=Buffer.from('R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQBCgABACwAAAAAAgACAIEAAP8AAAAAAAAAAAAIBgABCAQQEAA7','base64');
  const animatedWebp=await sharp(animatedGif,{animated:true}).webp().toBuffer();
  assert.equal((await sharp(animatedWebp).metadata()).pages,2);
  await assert.rejects(normalizeProfilePhoto(animatedWebp,'image/webp'));
  // A valid two-frame APNG, even when libvips decodes only its first frame.
  const apng=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAABAAAAAQAAAAAAAAAAAAEACgAAWn8w0AAAAA1JREFUeJxj+M/A8B8ABQAB/4mZPR0AAAAaZmNUTAAAAAEAAAABAAAAAQAAAAAAAAAAAAEACgAAwQzaBAAAABFmZEFUAAAAAnicY2Bg+P8fAAMCAf/1e6XXAAAAAElFTkSuQmCC','base64');
  assert.equal((await sharp(apng).metadata()).format,'png');
  await assert.rejects(normalizeProfilePhoto(apng,'image/png'));
});

test('a real-photo declaration is required for avatar and portfolio, with bounded captions', () => {
  assert.deepEqual(validatePhotoFields('portfolio','  Montagem no Rio  ','true'),{kind:'portfolio',caption:'Montagem no Rio'});
  assert.deepEqual(validatePhotoFields('avatar','','true'),{kind:'avatar',caption:null});
  for (const args of [['portfolio','','false'],['avatar','',''],['other','','true'],['portfolio','x'.repeat(161),'true']]) {
    assert.throws(()=>validatePhotoFields(...args));
  }
});

test('actual multipart stream is capped before parsing, even without Content-Length', async () => {
  const fields=new FormData();fields.set('photo',new File([jpeg],'fixture.jpg',{type:'image/jpeg'}));
  const form=await boundedPhotoForm(new Request('http://localhost/photos',{method:'POST',body:fields}));
  assert.equal(form.get('photo').size,jpeg.length);
  let reads=0;
  const body=new ReadableStream({pull(controller){reads++;controller.enqueue(new Uint8Array(80_000));if(reads===100)controller.close();}});
  const request=new Request('http://localhost/photos',{method:'POST',body,duplex:'half',headers:{'Content-Type':'multipart/form-data; boundary=test'}});
  await assert.rejects(boundedPhotoForm(request),error=>error.status===413);
  assert.ok(reads<45,'Oversized stream must be canceled instead of fully buffered');
});
