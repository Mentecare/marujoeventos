import { parseDocument, type DocumentType } from "./identity.ts";

export type SignupProfile = {
  profile_type:"freelancer"|"team_lead"|"company"|"agency";
  full_name:string;phone:string;document_type:DocumentType;document_number:string;
  market_role?:"provider"|"buyer";buyer_subtype?:"agency"|"scenography"|null;
  specialty_ids:string[];organization_name:string;business_type:string;
  city:string;bio:string;professional_status:"available"|"busy"|"unavailable";
};
export type SignupInput={email:string;password:string;payload:SignupProfile};

const isObj=(v:unknown):v is Record<string,unknown>=>v!==null&&typeof v==="object"&&!Array.isArray(v);
const value=(v:unknown,max:number)=>typeof v==="string"&&v.length<=max?v.trim():null;
const uuid=/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
export function validateSignup(valueInput:unknown):SignupInput|null{
  if(!isObj(valueInput)||!isObj(valueInput.payload))return null;
  const email=value(valueInput.email,254)?.toLowerCase(),password=valueInput.password;
  const p=valueInput.payload;
  const profileType=p.profile_type;
  const name=value(p.full_name,150),phone=value(p.phone,40),org=value(p.organization_name,150),
    business=value(p.business_type,150),city=value(p.city,120),bio=value(p.bio,1000);
  const documentInput=value(p.document_number,24),doc=documentInput?parseDocument(documentInput):null;
  if(!email||!/^\S+@\S+\.\S+$/.test(email)||typeof password!=="string"||password.length<8||password.length>72||
     !["freelancer","team_lead","company","agency"].includes(String(profileType))||
     !name||name.length<2||phone===null||org===null||business===null||city===null||bio===null||!doc||
     (profileType==="freelancer"&&doc.type!=="cpf")||
     (["company","agency"].includes(String(profileType))&&doc.type!=="cnpj")||
     !["available","busy","unavailable"].includes(String(p.professional_status)))return null;
  if(!Array.isArray(p.specialty_ids)||p.specialty_ids.length===0||p.specialty_ids.length>40||
     !p.specialty_ids.every((x:unknown)=>typeof x==="string"&&uuid.test(x)))return null;
  if(profileType!=="freelancer"&&org.length<2)return null;
  const marketRole=p.market_role;
  if(marketRole!==undefined&&marketRole!=="provider"&&marketRole!=="buyer")return null;
  const subtype=p.buyer_subtype;
  if(marketRole==="buyer"&&subtype!=="agency"&&subtype!=="scenography")return null;
  if(marketRole==="provider"&&subtype!=null)return null;
  if(marketRole===undefined&&subtype!=null)return null;
  if(profileType==="freelancer"&&marketRole!==undefined)return null;
  const specialties=[...new Set(p.specialty_ids as string[])];
  if(specialties.length!==p.specialty_ids.length)return null;
  return {email,password,payload:{
    profile_type:profileType as SignupProfile["profile_type"],full_name:name,phone,
    document_type:doc.type,document_number:doc.number,
    ...(marketRole?{market_role:marketRole,buyer_subtype:marketRole==="buyer"?subtype as "agency"|"scenography":null}:{}),
    specialty_ids:specialties,organization_name:org,business_type:business,city,bio,
    professional_status:p.professional_status as SignupProfile["professional_status"]
  }};
}
