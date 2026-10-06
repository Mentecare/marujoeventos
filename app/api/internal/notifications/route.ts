import {authorizedDispatcher,dispatchNotifications,deliveryConfiguration} from '@/lib/notification-delivery';
import {serviceSupabase} from '@/lib/supabase-server';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export const maxDuration=60;
const headers={'Cache-Control':'private, no-store'};
export async function POST(request:Request){
 if(!authorizedDispatcher(request.headers.get('authorization'),process.env.NOTIFICATION_DISPATCH_SECRET))return Response.json({error:'unauthorized'},{status:401,headers});
 try{return Response.json({...await dispatchNotifications(serviceSupabase(),undefined,5),configuration:deliveryConfiguration()},{headers})}
 catch{return Response.json({error:'notification_dispatch_unavailable'},{status:503,headers})}
}
