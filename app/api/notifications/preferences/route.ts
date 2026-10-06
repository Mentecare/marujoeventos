import {notificationActor,notificationFailure,notificationHeaders,notificationJson} from '@/lib/notification-server';
export const dynamic='force-dynamic';
export async function PUT(request:Request){try{const actor=await notificationActor(request);await actor.api.savePreferences(await notificationJson(request));return Response.json({updated:true},{headers:notificationHeaders})}catch(error){return notificationFailure(error)}}
