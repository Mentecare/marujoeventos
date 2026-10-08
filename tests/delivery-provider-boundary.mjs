// Test-only preload: provider HTTP transports are isolated; actual adapter,
// Web Push encryption/VAPID, Auth, DB and application routes remain real.
import https from 'node:https';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
const boundary=process.env.EVENTCORE_TEST_DELIVERY_BOUNDARY;
if(!boundary||!/^http:\/\/127\.0\.0\.1:\d+$/.test(boundary))throw Error('isolated delivery boundary required');
const realFetch=globalThis.fetch;
globalThis.fetch=async(url,init)=>String(url)==='https://api.resend.com/emails'
 ?realFetch(boundary+'/test/email',init):realFetch(url,init);
https.request=function(options,callback){
 if(options.hostname!=='fcm.googleapis.com')throw Error('external HTTPS transport forbidden in isolated Next delivery test');
 const request=new EventEmitter(),chunks=[];
 request.write=chunk=>{chunks.push(Buffer.from(chunk));return true};
 request.destroy=error=>{if(error)request.emit('error',error);return request};
 request.end=()=>{
  realFetch(boundary+'/test/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({hostname:options.hostname,path:options.path,headers:options.headers,body:Buffer.concat(chunks).toString('base64')})}).then(async response=>{
   const stream=Readable.from([Buffer.from(await response.text())]);stream.statusCode=response.status;stream.headers={};callback(stream);
  }).catch(error=>request.emit('error',error));return request;
 };
 return request;
};
