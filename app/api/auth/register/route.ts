import { createClient } from "@supabase/supabase-js";
import { serviceSupabase } from "@/lib/supabase-server";
import { validateSignup } from "@/lib/signup-registration";
import { emailAuthError } from "@/lib/auth-email";
export const dynamic="force-dynamic";
export const runtime="nodejs";

function json(error:string,status:number){return Response.json({error},{status,headers:{"Cache-Control":"no-store"}})}
export async function POST(request:Request){
  let input:ReturnType<typeof validateSignup>;
  try{
    const raw=await request.text();
    if(raw.length>12000)return json("O cadastro excedeu o tamanho permitido.",413);
    input=validateSignup(JSON.parse(raw));
  }catch{return json("Confira os dados enviados.",400)}
  if(!input)return json("Confira os campos do cadastro, documento e especialidades.",422);
  const {email,password,payload}=input;
  try{
    const admin=serviceSupabase();
    const catalog=await admin.from("specialties").select("id").in("id",payload.specialty_ids).eq("active",true);
    if(catalog.error)return json("Não foi possível conferir as especialidades. Tente novamente.",503);
    if((catalog.data||[]).length!==payload.specialty_ids.length)return json("Selecione somente especialidades disponíveis.",422);

    // Supabase Auth sends the confirmation email. Only non-sensitive trigger fields go in user_metadata.
    // CPF/CNPJ and all other submitted fields live in a service-role-only private draft table.
    const signupClient=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{
      auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
    });
    const signupNonce=crypto.randomUUID();
    const signup=await signupClient.auth.signUp({
      email,password,options:{
        emailRedirectTo:"https://eventcore.space",
        data:{full_name:payload.full_name,phone:payload.phone,profile_type:payload.profile_type,registration_nonce:signupNonce}
      }
    });
    if(signup.error)return json(emailAuthError(signup.error)||"Não foi possível registrar a conta. Aguarde e tente novamente.",signup.error.status===429?429:400);
    const user=signup.data.user;
    const age=user?.created_at?Date.now()-new Date(user.created_at).getTime():Infinity;
    // Do not attach untrusted data to existing/obfuscated account IDs returned by Auth.
    if(!user||signup.data.session||!Number.isFinite(age)||age< -300000||age>120000||user.identities?.length===0||user.user_metadata?.registration_nonce!==signupNonce)
      return json("Não foi possível iniciar um novo cadastro com este e-mail. Tente entrar ou solicitar uma nova confirmação.",409);

    const pending=await admin.from("pending_signup_profiles").insert({user_id:user.id,payload});
    if(pending.error){
      // Never report success with a lost form. Do not leak document numbers or server diagnostics.
      return json("A conta foi iniciada, mas não foi possível guardar o formulário. Procure o suporte antes de continuar.",503);
    }
    // Best-effort retention maintenance. Never delay a signup for cleanup failures.
    void admin.from("pending_signup_profiles").delete().lt("expires_at",new Date().toISOString()).then(()=>{});
    return Response.json({ok:true,confirmation_required:true},{status:201,headers:{"Cache-Control":"no-store"}});
  }catch{return json("O cadastro está temporariamente indisponível. Tente novamente mais tarde.",503)}
}
