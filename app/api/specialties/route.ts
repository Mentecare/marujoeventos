import { createClient } from '@supabase/supabase-js';
export const dynamic='force-dynamic';
export async function GET(){
  const db=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false}});
  const {data,error}=await db.from('specialties').select('id,slug,name,active,sort_order').eq('active',true).order('sort_order');
  if(error)return Response.json({error:'Não foi possível carregar as especialidades.'},{status:503});
  return Response.json(data,{headers:{'Cache-Control':'public, max-age=300'}});
}
