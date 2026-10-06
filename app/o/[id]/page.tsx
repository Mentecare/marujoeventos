import {cache} from 'react';
import type {Metadata} from 'next';
import {notFound} from 'next/navigation';
import {createClient} from '@supabase/supabase-js';
import type {PublicOpportunity} from '@/lib/notifications';
export const dynamic='force-dynamic';
export const revalidate=0;
const publicOpportunity=cache(async(id:string):Promise<PublicOpportunity|null>=>{
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return null;
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)return null;
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>fetch(input,{...init,cache:'no-store'})}});
 const response=await db.rpc('get_public_opportunity',{p_service_id:id});
 if(response.error)return null;
 return response.data as PublicOpportunity|null;
});
export async function generateMetadata({params}:{params:Promise<{id:string}>}):Promise<Metadata>{
 const opportunity=await publicOpportunity((await params).id);
 if(!opportunity)return{title:'Oportunidade indisponível · EventCore',robots:{index:false,follow:false}};
 const description=`${opportunity.role} · ${opportunity.days==null?'Dias a confirmar':opportunity.days+' dias'} · ${opportunity.region} · ${opportunity.date} · ${opportunity.provider}`;
 return{title:`${opportunity.title} · EventCore`,description,openGraph:{title:opportunity.title,description,type:'website',url:`https://eventcore.space/o/${opportunity.id}`},twitter:{card:'summary',title:opportunity.title,description}};
}
export default async function OpportunityPage({params}:{params:Promise<{id:string}>}){
 const opportunity=await publicOpportunity((await params).id);if(!opportunity)notFound();
 const share=`https://wa.me/?text=${encodeURIComponent(opportunity.title+' https://eventcore.space/o/'+opportunity.id)}`;
 return <main className="app"><section className="panel"><p className="eyebrow">EventCore · Oportunidade pública</p><h1>{opportunity.title}</h1><p>{opportunity.provider}</p><p>{opportunity.role} · {opportunity.days==null?'Dias a confirmar':`${opportunity.days} dias`} · {opportunity.region} · {opportunity.date}</p>{opportunity.description&&<p>{opportunity.description}</p>}<div className="actions"><a className="btn" href={`/?opportunity=${opportunity.id}`}>Entrar e ver oportunidade</a><a className="btn secondary" href={share} target="_blank" rel="noopener noreferrer">Compartilhar no WhatsApp</a></div></section></main>;
}
