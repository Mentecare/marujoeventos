export type PushDeviceSubscription = {endpoint:string;keys:{p256dh:string;auth:string}};
export type NotificationPreferences = {mode:'relevant'|'all_eligible';specialty_ids:string[];regions:string[];date_from:string|null;date_to:string|null;cadence:'immediate'|'daily';email_enabled:boolean;push_enabled:boolean;paused_until:string|null};
export type PublicOpportunity = {id:string;title:string;provider:string;role:string;days:number|null;region:string;date:string;description:string|null};
export type NotificationItem = {id:string;title:string;link:string;created_at:string;read_at:string|null;opportunity?:PublicOpportunity|null};
export type NotificationCenter = {delivery?:{push:{enabled:boolean;missing:string[]};email:{enabled:boolean;missing:string[]}};preferences:NotificationPreferences;email_confirmed:boolean;notifications:NotificationItem[];devices:{id:string;endpoint?:string;active:boolean;created_at:string}[]};
export type NotificationRpcClient = {rpc:(name:string,args?:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{message:string}|null}>};
const UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const LINK=new RegExp(`^(?:/o/${UUID}|/\\?(?:opportunity|assignment|contract)=${UUID})$`,'i');
export function safeNotificationLink(value:unknown):string|null {
 return typeof value==='string' && LINK.test(value) ? value : null;
}
/** Fixed browser push origins and protocol paths. No arbitrary URLs, IP literals, ports or redirects. */
export function validatePushSubscription(value:unknown):PushDeviceSubscription {
 if(!value||typeof value!=='object')throw new Error('invalid_subscription');
 const v=value as Record<string,unknown>;if(typeof v.endpoint!=='string'||v.endpoint.length>2000)throw new Error('invalid_subscription');
 let url:URL;try{url=new URL(v.endpoint)}catch{throw new Error('unsafe_push_endpoint')}
 const pathAllowed=url.hostname==='fcm.googleapis.com'&&url.pathname.startsWith('/fcm/send/')||url.hostname==='updates.push.services.mozilla.com'&&url.pathname.startsWith('/wpush/v2/')||url.hostname==='web.push.apple.com'&&url.pathname.length>1||/^[a-z0-9-]+\.notify\.windows\.com$/.test(url.hostname)&&url.pathname.startsWith('/w/');
 if(url.protocol!=='https:'||url.username||url.password||url.port||url.hash||!pathAllowed)throw new Error('unsafe_push_endpoint');
 const keys=v.keys as Record<string,unknown>|undefined;
 if(!keys||typeof keys.p256dh!=='string'||typeof keys.auth!=='string'||! /^[A-Za-z0-9_-]{87}=?$/.test(keys.p256dh)||! /^[A-Za-z0-9_-]{22}={0,2}$/.test(keys.auth))throw new Error('invalid_subscription_keys');
 return{endpoint:v.endpoint,keys:{p256dh:keys.p256dh,auth:keys.auth}};
}
export function pushSupport(features:{serviceWorker:boolean;pushManager:boolean;notification:boolean;permission:string}):'unsupported'|'denied'|'available' {
 if(!features.serviceWorker||!features.pushManager||!features.notification)return 'unsupported';
 return features.permission==='denied'?'denied':'available';
}
export function notificationApi(db:NotificationRpcClient){
 async function rpc<T>(name:string,args?:Record<string,unknown>):Promise<T>{const result=await db.rpc(name,args);if(result.error)throw new Error(result.error.message);return result.data as T}
 return{center:()=>rpc<NotificationCenter>('get_notification_center'),savePreferences:(preferences:NotificationPreferences)=>rpc<void>('save_notification_preferences',{p_preferences:preferences}),markRead:(id:string)=>rpc<void>('mark_notification_read',{p_notification_id:id}),registerDevice:(subscription:PushDeviceSubscription)=>rpc<string>('register_notification_device',{p_subscription:validatePushSubscription(subscription)}),removeDevice:(id:string)=>rpc<void>('remove_notification_device',{p_device_id:id})};
}
