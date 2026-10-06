// Server-only dependency boundary: imported by the Node dispatcher route, never a client component.
import { timingSafeEqual } from 'node:crypto';
import webPush from 'web-push';
import {safeNotificationLink,validatePushSubscription,type PushDeviceSubscription,type NotificationRpcClient} from './notifications.ts';
type Env=Record<string,string|undefined>;
type Message={title:string;link:string};
export type AdapterResult={status:'acknowledged'|'retry'|'disabled'|'expired'|'suppressed';reason?:string};
type EmailBatch={id:string;to:string;notifications:Message[]};
export type DeliveryAdapters={email:(batch:EmailBatch)=>Promise<AdapterResult>;push:(subscription:PushDeviceSubscription,message:Message)=>Promise<AdapterResult>};
type Batch={id:string;lease_token:string;channel:'email'|'push';to:string|null;notifications:Message[];delivered_device_count?:number;devices:{id:string;subscription:PushDeviceSubscription}[]};
export function authorizedDispatcher(header:string|null,secret:string|undefined){
 if(!secret||secret.length<32||!header?.startsWith('Bearer '))return false;
 const a=Buffer.from(header.slice(7)),b=Buffer.from(secret);return a.length===b.length&&timingSafeEqual(a,b);
}
export function deliveryConfiguration(env:Env=process.env){
 const pushMissing=['NOTIFICATION_VAPID_PUBLIC_KEY','NOTIFICATION_VAPID_PRIVATE_KEY','NOTIFICATION_VAPID_SUBJECT'].filter(k=>!env[k]);
 const emailMissing=['RESEND_API_KEY','NOTIFICATION_EMAIL_FROM'].filter(k=>!env[k]);
 return{push:{enabled:pushMissing.length===0,missing:pushMissing},email:{enabled:emailMissing.length===0,missing:emailMissing}};
}
/** Real adapters; injectable transport only replaces the provider boundary in tests. Never follows redirects. */
export function createDeliveryAdapters(env:Env=process.env,transport:{fetch?:typeof fetch;sendNotification?:typeof webPush.sendNotification}={}):DeliveryAdapters {
 const config=deliveryConfiguration(env),send=transport.sendNotification||webPush.sendNotification,fetcher=transport.fetch||fetch;
 return{
  async email(batch){
   if(!config.email.enabled)return{status:'disabled',reason:'email_not_configured'};
   if(!batch.to||!batch.notifications.length||batch.notifications.some(n=>!safeNotificationLink(n.link)))return{status:'suppressed',reason:'invalid_payload'};
   const text=batch.notifications.map(n=>`${n.title.slice(0,180)}\nhttps://eventcore.space${n.link}`).join('\n\n');
   try{
    const response=await fetcher('https://api.resend.com/emails',{method:'POST',redirect:'error',signal:AbortSignal.timeout(12000),headers:{Authorization:`Bearer ${env.RESEND_API_KEY}`,'Content-Type':'application/json','Idempotency-Key':`eventcore-${batch.id}`},body:JSON.stringify({from:env.NOTIFICATION_EMAIL_FROM,to:[batch.to],subject:batch.notifications.length>1?'Seu resumo EventCore':'Atualização EventCore',text})});
    if(!response.ok)return{status:'retry',reason:response.status===429||response.status>=500?'provider_unavailable':'provider_rejected'};
    const payload=await response.json();return typeof payload.id==='string'&&payload.id?{status:'acknowledged'}:{status:'retry',reason:'provider_unavailable'};
   }catch{return{status:'retry',reason:'provider_unavailable'}}
  },
  async push(subscription,message){
   if(!config.push.enabled)return{status:'disabled',reason:'push_not_configured'};
   try{
    validatePushSubscription(subscription);if(!safeNotificationLink(message.link))return{status:'suppressed',reason:'invalid_payload'};
    const response=await send(subscription,JSON.stringify({title:message.title.slice(0,180),link:message.link}),{TTL:300,timeout:12000,vapidDetails:{subject:env.NOTIFICATION_VAPID_SUBJECT!,publicKey:env.NOTIFICATION_VAPID_PUBLIC_KEY!,privateKey:env.NOTIFICATION_VAPID_PRIVATE_KEY!}});
    return response.statusCode>=200&&response.statusCode<300?{status:'acknowledged'}:{status:'retry',reason:'provider_unavailable'};
   }catch(error){const status=(error as {statusCode?:number}).statusCode;return status===404||status===410?{status:'expired',reason:'subscription_expired'}:{status:'retry',reason:'provider_unavailable'}}
  }
 };
}
export async function dispatchNotifications(db:NotificationRpcClient,adapters:DeliveryAdapters=createDeliveryAdapters(),limit=10){
 async function rpc<T>(name:string,args?:Record<string,unknown>):Promise<T>{const r=await db.rpc(name,args);if(r.error)throw new Error('notification_database_unavailable');return r.data as T}
 const batches=await rpc<Batch[]>('claim_notification_batches',{p_limit:Math.min(20,Math.max(1,limit))});
 const deadline=Date.now()+45000;
 const counts={claimed:batches.length,acknowledged:0,retry:0,disabled:0,suppressed:0};
 for(const batch of batches){
  const args={p_batch_id:batch.id,p_lease_token:batch.lease_token};
  let outcome:AdapterResult;
  if(Date.now()>deadline-12000)outcome={status:'retry',reason:'provider_unavailable'};
  else if(!await rpc<boolean>('recheck_notification_batch',args))outcome={status:'suppressed',reason:'eligibility_changed'};
  else if(!batch.notifications?.length||batch.notifications.some(n=>!safeNotificationLink(n.link)))outcome={status:'suppressed',reason:'invalid_payload'};
  else if(batch.channel==='email')outcome=await adapters.email({id:batch.id,to:batch.to!,notifications:batch.notifications});
  else{
   outcome=batch.devices.length||batch.delivered_device_count?{status:'acknowledged'}:{status:'suppressed',reason:'no_devices'};
   let acknowledgments=0;
   for(const device of batch.devices){
    if(Date.now()>deadline-12000){outcome={status:'retry',reason:'provider_unavailable'};break}
    // Recheck between devices as preferences and memberships can change during a batch.
    if(!await rpc<boolean>('recheck_notification_batch',args)){outcome={status:'suppressed',reason:'eligibility_changed'};break}
    const result=await adapters.push(device.subscription,{title:batch.notifications.length>1?'Seu resumo EventCore':batch.notifications[0].title,link:batch.notifications[0].link});
    if(result.status==='acknowledged'){await rpc('ack_notification_device',{...args,p_device_id:device.id});acknowledgments++}
    else if(result.status==='expired')await rpc('disable_notification_device',{...args,p_device_id:device.id});
    else{outcome=result;break}
   }
   if(outcome.status==='acknowledged'&&acknowledgments===0&&!batch.delivered_device_count)outcome={status:'suppressed',reason:'no_devices'};
  }
  const status=outcome.status==='expired'?'suppressed':outcome.status;
  await rpc('finish_notification_batch',{...args,p_outcome:status,p_reason:outcome.reason||null});counts[status]++;
 }
 return counts;
}
