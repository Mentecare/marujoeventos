import {notificationActor,notificationFailure,notificationHeaders,notificationJson} from '@/lib/notification-server';
import {deliveryConfiguration} from '@/lib/notification-delivery';
export const dynamic='force-dynamic';
export async function GET(request:Request){try{const actor=await notificationActor(request);return Response.json({...await actor.api.center(),delivery:deliveryConfiguration()},{headers:notificationHeaders})}catch(error){return notificationFailure(error)}}
export async function PATCH(request:Request){try{const actor=await notificationActor(request),body=await notificationJson(request);if(typeof body.id!=='string')throw new Error('invalid_preferences');await actor.api.markRead(body.id);return Response.json({updated:true},{headers:notificationHeaders})}catch(error){return notificationFailure(error)}}
