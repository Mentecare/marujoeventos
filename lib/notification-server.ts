import {ActorError,commercialActor} from './actor-server.ts';
import {notificationApi} from './notifications.ts';
const headers={'Cache-Control':'private, no-store'};
export async function notificationActor(request:Request){const actor=await commercialActor(request);return{...actor,api:notificationApi(actor.db)}}
export function notificationFailure(error:unknown){
 if(error instanceof ActorError)return Response.json({error:error.message},{status:error.status,headers});
 const message=error instanceof Error?error.message:'';
 const known=['invalid_subscription','unsafe_push_endpoint','invalid_subscription_keys','invalid_preferences','confirmed_email_required','device_already_owned','device_limit'];
 return Response.json({error:known.includes(message)?message:'notifications_unavailable'},{status:known.includes(message)?400:503,headers});
}
export async function notificationJson(request:Request){
 if(!request.headers.get('content-type')?.includes('application/json'))throw new Error('invalid_preferences');
 const body=await request.text();if(body.length>12000)throw new Error('invalid_preferences');
 try{return JSON.parse(body)}catch{throw new Error('invalid_preferences')}
}
export const notificationHeaders=headers;
