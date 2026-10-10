"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { AppIcon, type IconName } from "@/app/components/ui-icons";
import { freelancerDashboard, businessDashboard } from "@/lib/dashboard";
import { EventCreationForm } from "@/app/components/event-creation";
import { ProfileAvatar, ProfilePhotoEditor, ProfessionalPhotos, requestProfilePhotos } from "@/app/components/profile-photos";
import { EMPTY_PHOTOS, type ProfilePhotoCollection } from "@/lib/profile-photos";
import type { EventCreationInput } from "@/lib/event-creation";
import {commercialApi,workflowApi,getEventOperations,type CommercialContext,type EventOperations,type WorkerWorkAssignment,type WorkFinance,type WorkFinanceIndex,type CommercialContract} from "@/lib/commercial";
import {BusinessSetup,DocumentField} from "@/app/components/business-setup";
import {CommercialWorkspace} from "@/app/components/commercial-workspace";
import {RelationshipHistory} from "@/app/components/relationship-history";
import {ProviderPeoplePanel} from "@/app/components/provider-people";
import {WorkDetail} from "@/app/components/work-detail";
import {WorkerWork} from "@/app/components/worker-work";
import {Notifications,OpportunityShare,useNotificationCenter} from '@/app/components/notifications';
import {safeNotificationLink} from '@/lib/notifications';
import {WorkFinancePanel,TeamPayments} from "@/app/components/work-finance";
import {calendarDate,money} from "@/app/components/workflow-ui";
import {acceptedAmount,workerDashboardMetrics} from "@/lib/work-presentation";
import { parseDocument, validateDocument } from "@/lib/identity";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase-browser";
import { emailAuthError } from "@/lib/auth-email";
import { AppTab, capabilitiesFor, canOpenTab, isStaff, navigationFor, profileOrganizationFor, profileTypeLabel, type ProfileType } from "@/lib/capabilities";

type Profile = {
  id:string; full_name:string|null; phone:string|null; role:string; active:boolean;
  profile_type:ProfileType; onboarding_completed:boolean; professional_status:string; bio?:string|null;
};
type Client = { id:string; trade_name:string; legal_name?:string|null; contact_name?:string|null; phone?:string|null; email?:string|null; active:boolean; organization_id?:string|null };
type Freelancer = { id:string; profile_id?:string|null; full_name:string; phone?:string|null; city?:string|null; active:boolean; rating:number; completed_jobs:number; no_show_count?:number };
type DirectoryProfessional = { freelancer_id:string; profile_id?:string|null; full_name:string; city?:string|null; rating:number; completed_jobs:number; review_count:number; specialties:string[] };
type Specialty = { id:string; slug:string; name:string; active:boolean; sort_order:number };
type Organization = { id:string; owner_profile_id:string; organization_type:"team"|"company"|"agency"; legal_name?:string|null; trade_name?:string|null; display_name:string; business_type?:string|null; market_role?:'provider'|'buyer'|'unclassified';buyer_subtype?:'agency'|'scenography'|null; active:boolean; created_at:string };
type EventRow = { id:string; proposal_id?:string|null; client_id:string; name:string; venue:string; start_at:string; end_at?:string|null; status:string; arrival_tolerance_minutes:number; notes?:string|null; calendar_sync_status:string; google_event_id?:string|null; calendar_last_error?:string|null; created_by_profile_id?:string|null; organization_id?:string|null };
type EventService = { id:string; event_id:string; service_type:string; label:string; quantity_needed:number; reserve_target:number; contract_days?:number|null; freelancer_unit_cost?:number|null; briefing?:string|null; specialty_id?:string|null; visibility:string; application_enabled:boolean; requirements?:string|null };
type JobApplication = { id:string; event_service_id:string; freelancer_id:string; status:string; message?:string|null; created_at:string; updated_at:string };
type Assignment = { id:string; event_service_id:string; freelancer_id:string; status:string; agreed_amount?:number|null; contractor_profile_id?:string|null; application_id?:string|null; hired_at?:string|null; created_at?:string };
type Attendance = { id:string; assignment_id:string; check_in_at?:string|null; check_out_at?:string|null };
type Payment = { id:string; assignment_id:string; amount:number; status:string; method?:string|null; paid_at?:string|null; created_at?:string };
type Rating = { id:string; assignment_id:string; event_id:string; freelancer_id:string; reviewer_profile_id:string; rating:number; comment?:string|null; created_at:string };
type Integration = { id:string; kind:string; account_email?:string|null; status:string };
type EventPane = "equipe"|"candidaturas"|"escala"|"presenca"|"financeiro"|"avaliacoes";
type EventsMode = "mine"|"opportunities";

type Opportunity = {service_id:string;event_id:string;event_name:string;start_at:string;end_at:string|null;venue:string;function_name:string;specialty_id:string|null;vacancies:number;amount:number|null;contractor_name:string;requirements:string|null;event_status:string;compatible:boolean;contract_days?:number|null};
type RosterMember = {profile_id:string;full_name:string;phone:string|null;member_role:string;active:boolean};
type Reputation = {freelancer_id:string;name:string;availability:string|null;bio:string|null;reviews:{id:string;rating:number;comment:string|null;date:string;event_name:string}[]};
type ProfilePayload = {profile_type:Exclude<ProfileType,null>;full_name:string;phone:string;document_type:"cpf"|"cnpj";document_number:string;market_role?:'buyer'|'provider';buyer_subtype?:'agency'|'scenography'|null;specialty_ids:string[];organization_name:string;business_type:string;city:string;bio:string;professional_status:string};
function profilePayload(form:HTMLFormElement):ProfilePayload {
 const f=new FormData(form);const document=String(f.get('document_number')||'');const kind=parseDocument(document)?.type||'cpf';return {...(f.get('market_role')?{market_role:String(f.get('market_role')) as 'buyer'|'provider',buyer_subtype:f.get('market_role')==='buyer'?String(f.get('buyer_subtype')) as 'agency'|'scenography':null}:{}),profile_type:String(f.get("profile_type")) as Exclude<ProfileType,null>,full_name:String(f.get("full_name")||""),phone:String(f.get("phone")||""),document_type:kind,document_number:String(f.get("document_number")||""),specialty_ids:f.getAll("specialty_ids").map(String),organization_name:String(f.get("organization_name")||""),business_type:String(f.get("business_type")||""),city:String(f.get("city")||""),bio:String(f.get("bio")||""),professional_status:String(f.get("professional_status")||"available")};
}
const eventStatus:Record<string,string>={planning:"Planejamento",staffing:"Montando equipe",confirmed:"Confirmado",in_progress:"Em andamento",completed:"Concluído",cancelled:"Cancelado"};
const assignmentStatus:Record<string,string>={invited:"Convidado",confirmed:"Confirmado",reserve:"Reserva",cancelled:"Cancelado",checked_in:"Em serviço",checked_out:"Concluído",no_show:"Ausente"};
const applicationStatus:Record<string,string>={interested:"Interesse enviado",shortlisted:"Pré-selecionado",accepted:"Contratado",rejected:"Não selecionado",withdrawn:"Retirado"};
const calendarStatus:Record<string,string>={not_linked:"Não sincronizado",pending:"Aguardando sincronização",synced:"Sincronizado",out_of_sync:"Atualização pendente",error:"Erro de sincronização"};
const paymentMethod:Record<string,string>={pix:"Pix",transfer:"Transferência",cash:"Dinheiro",other:"Outro"};
const paymentStatus:Record<string,string>={pending:"Pendente",approved:"Aprovado",paid:"Pago",held:"Em análise",cancelled:"Cancelado"};
const businessTypes=["Cenografia","Equipe de carregadores","Agência de eventos","Equipe técnica","Produção","Montagem","Logística","Segurança","Limpeza","Prestadora de serviços","Outro"];

function msg(e:unknown){ return e && typeof e==="object" && "message" in e ? String(e.message) : String(e); }
function friendlyError(e:unknown){const authMessage=emailAuthError(e);if(authMessage)return authMessage;const m=msg(e);const messages:Record<string,string>={invalid_event_data:"Confira os dados e os horários do novo evento.",invalid_event_function:"Confira as vagas, reservas e valores das funções.",invalid_contract_days:"Informe uma quantidade inteira de dias, maior que zero, para cada função.",contract_days_creation_only:"Os dias de contratação são definidos somente na criação do evento.",invalid_event_specialty:"Selecione uma especialidade ativa para cada função.",functions_creation_only:"As funções só podem ser incluídas na criação do evento.",invalid_payment_amount:"Informe um valor contratado válido.",payment_already_paid:"Este pagamento já foi registrado. O valor pago é preservado.",payment_cancelled:"Este pagamento foi cancelado.",payment_amount_required:"Informe o valor contratado antes de registrar o pagamento.",private_document_conflict:"Confira os dados de identificação ou entre na sua conta existente.",invalid_private_document:"Confira o CPF/CNPJ e seus dígitos verificadores.",vacancies_filled:"As vagas desta função já foram preenchidas.",completed_validated_event_required:"Conclua o evento e valide a presença antes de avaliar.",assignment_already_rated:"Esta contratação já foi avaliada.",event_has_not_ended:"O horário de término do evento ainda não passou.",forbidden:"Seu perfil não tem permissão para esta ação.",profile_type_locked:"O tipo de um perfil concluído é mantido para preservar sua operação.",attendance_required:"Registre a presença antes de concluir a contratação.",invalid_attendance_transition:"Esta ação não está disponível para o status atual.",select_active_specialties:"Selecione ao menos uma especialidade.",self_hiring_not_allowed:"Não é possível contratar a própria conta.",specialty_not_compatible:"Esta vaga pede uma especialidade diferente do seu perfil.",application_unavailable:"Esta candidatura não está disponível para contratação.",invalid_application_transition:"A candidatura já foi encerrada ou contratada.",application_requires_reapply:"O profissional precisa se candidatar novamente antes da recontratação.",professional_already_assigned:"Este profissional já está nesta função da escala.",professional_unavailable:"Este profissional não está disponível para contratação.",historical_assignment_cannot_reopen:"Este trabalho já possui presença ou pagamento registrado. Crie um novo evento para uma nova contratação.",invalid_assignment_response:"Esta convocação não aceita essa alteração.",invalid_assignment_status_transition:"Essa alteração não está disponível para o status atual."};return messages[m]||m;}
function brl(n:number){ return Number(n||0).toLocaleString("pt-BR",{style:"currency",currency:"BRL"}); }
export default function Page(){
  const [session,setSession]=useState<Session|null>(null);
  const [profile,setProfile]=useState<Profile|null>(null);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [notificationsOpen,setNotificationsOpen]=useState(false);
  const deepLinkHandled=useRef(false);
  const authFormRef=useRef<HTMLFormElement|null>(null);
  const [resendCooldown,setResendCooldown]=useState(0);
  useEffect(()=>{if(resendCooldown<=0)return;const timer=window.setTimeout(()=>setResendCooldown(current=>Math.max(0,current-1)),1000);return()=>window.clearTimeout(timer)},[resendCooldown]);
  const [deepTarget,setDeepTarget]=useState<string|null>(null);
  const [signup,setSignup]=useState(false);
  const [tab,setTab]=useState<AppTab>("home");
  const [eventsMode,setEventsMode]=useState<EventsMode>("mine");
  const [eventPane,setEventPane]=useState<EventPane>("equipe");
  const [clients,setClients]=useState<Client[]>([]);
  const [directory,setDirectory]=useState<DirectoryProfessional[]>([]);
  const [ownFreelancer,setOwnFreelancer]=useState<Freelancer|null>(null);
  const [specialties,setSpecialties]=useState<Specialty[]>([]);
  const [mySpecialtyIds,setMySpecialtyIds]=useState<string[]>([]);
  const [commercialContext,setCommercialContext]=useState<CommercialContext|null>(null);
  const [operations,setOperations]=useState<EventOperations[]>([]);
  const [workAssignments,setWorkAssignments]=useState<WorkerWorkAssignment[]>([]);
  const [remunerations,setRemunerations]=useState<WorkerWorkAssignment[]>([]);
  const [workFinances,setWorkFinances]=useState<WorkFinance[]>([]);
  const [financeIndex,setFinanceIndex]=useState<WorkFinanceIndex[]>([]);
  const [commercialContracts,setCommercialContracts]=useState<CommercialContract[]>([]);
  const [organizations,setOrganizations]=useState<Organization[]>([]);
  const [events,setEvents]=useState<EventRow[]>([]);
  const [services,setServices]=useState<EventService[]>([]);
  const [applications,setApplications]=useState<JobApplication[]>([]);
  const [assignments,setAssignments]=useState<Assignment[]>([]);
  const [attendance,setAttendance]=useState<Attendance[]>([]);
  const [payments,setPayments]=useState<Payment[]>([]);
  const [ratings,setRatings]=useState<Rating[]>([]);
  const [profiles,setProfiles]=useState<Profile[]>([]);
  const [integration,setIntegration]=useState<Integration|null>(null);
  const [selectedEventId,setSelectedEventId]=useState<string|null>(null);
  const [opportunities,setOpportunities]=useState<Opportunity[]>([]);
  const [activeOrgId,setActiveOrgId]=useState("");
  const [roster,setRoster]=useState<RosterMember[]>([]);
  const [reputation,setReputation]=useState<Reputation|null>(null);
  const [editProfile,setEditProfile]=useState(false);
  const [ownPhotos,setOwnPhotos]=useState<ProfilePhotoCollection>(EMPTY_PHOTOS);
  const [photosLoading,setPhotosLoading]=useState(false);
  const [photosError,setPhotosError]=useState("");
  const [profileFocus,setProfileFocus]=useState<{target:string;sequence:number}|null>(null);
  const photoRequest=useRef(0), reputationRequest=useRef(0), mutationLock=useRef(false);
  const eventHeading=useRef<HTMLHeadingElement>(null);

  async function refreshOwnPhotos(){
    const sequence=++photoRequest.current;
    setPhotosLoading(true);setPhotosError("");
    try{const photos=await requestProfilePhotos();if(sequence===photoRequest.current)setOwnPhotos(photos)}
    catch(error){if(sequence===photoRequest.current)setPhotosError(error instanceof Error?error.message:"Não foi possível carregar suas fotos.");throw error}
    finally{if(sequence===photoRequest.current)setPhotosLoading(false)}
  }
  useEffect(()=>{if(profile?.id)void refreshOwnPhotos().catch(()=>{});else setOwnPhotos(EMPTY_PHOTOS)},[profile?.id,tab==='profile']);
  useEffect(()=>{if(tab==='profile'&&profileFocus){const frame=requestAnimationFrame(()=>{const section=document.getElementById(profileFocus.target);section?.scrollIntoView({block:'start'});section?.focus({preventScroll:true})});return()=>cancelAnimationFrame(frame)}},[tab,profileFocus]);
  function openProfileSection(target:string){setTab('profile');setEditProfile(target==='profile-data');setProfileFocus(previous=>({target,sequence:(previous?.sequence||0)+1}))}
  function closeProfessionalProfile(){reputationRequest.current++;setReputation(null)}
  const [authSpecialties,setAuthSpecialties]=useState<Specialty[]>([]);
  const [installPrompt,setInstallPrompt]=useState<any>(null);

  useEffect(()=>{
    if("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(()=>{});
    const handler=(e:any)=>{e.preventDefault();setInstallPrompt(e)};
    window.addEventListener("beforeinstallprompt",handler);
    const params=new URLSearchParams(location.search);
    if(params.get("google")==="connected"){setNotice("Google Calendar conectado com sucesso.");history.replaceState({},"","/")}
    if(params.get("google")==="error"){setError(params.get("message")||"Falha ao conectar o Google Calendar.");history.replaceState({},"","/")}
    fetch("/api/specialties").then(r=>r.json()).then(data=>{if(Array.isArray(data))setAuthSpecialties(data)}).catch(()=>{});
    supabase.auth.getSession().then(async({data})=>{if(data.session)await boot(data.session);else setLoading(false)});
    return()=>window.removeEventListener("beforeinstallprompt",handler);
  },[]);

  const notificationState=useNotificationCenter(profile?.id);
  const unreadCount=notificationState.center?.notifications.filter(n=>!n.read_at).length||0;
  const selectedCommercialOrg=commercialContext?.organizations.find(o=>o.id===activeOrgId)||commercialContext?.organizations[0];
  const caps=profile?capabilitiesFor(profile,commercialContext,selectedCommercialOrg?.id):null;
  const nav=profile?navigationFor(profile):[];
  if((selectedCommercialOrg?.can_finance||workFinances.length>0)&&!nav.some(n=>n.id==='finance'))nav.splice(nav.length-1,0,{id:'finance',label:'Financeiro'});
  const mobileNavigation=nav.filter(n=>["home","dashboard","clients","team","events"].includes(n.id));
  const extraNavigation=nav;
  const currentOrg=organizations.find(o=>o.id===(selectedCommercialOrg?.id||activeOrgId))||organizations.find(o=>o.owner_profile_id===profile?.id)||organizations[0]||null;
  const profileOrganization=profile?profileOrganizationFor(organizations,profile.id):null;
  useEffect(()=>{if(currentOrg&&caps?.manageTeam)supabase.rpc("get_organization_roster",{p_organization_id:currentOrg.id}).then(({data,error})=>{if(error)setError(error.message);else setRoster(data||[])});else setRoster([])},[currentOrg?.id,profile?.id]);

  async function boot(s:Session){
    try{
      // Finish verified registrations using the private, one-time server-side draft.
      // The RPC itself checks auth.uid(), confirmed email, and current onboarding state.
      const completion=await supabase.rpc("complete_pending_signup");
      if(completion.error){
        setError("Seus dados de cadastro estão preservados, mas não foi possível finalizar o perfil automaticamente. Entre novamente ou procure o suporte: "+friendlyError(completion.error));
      }else if(completion.data?.status==="completed"){
        setNotice("Seu cadastro foi confirmado e o perfil já está pronto para usar o EventCore!");
      }else if(completion.data?.status==="expired"){
        setError("Sua confirmação demorou mais que o prazo de armazenamento dos dados. Procure o suporte para concluir o cadastro.");
      }
      const {data:p,error:pe}=await supabase.from("profiles").select("id,full_name,phone,role,active,profile_type,onboarding_completed,professional_status,bio").eq("id",s.user.id).single();
      if(pe||!p||!p.active) throw new Error("Conta inativa ou sem perfil no EventCore.");
      const next=p as Profile; setSession(s);setProfile(next);
      if(!canOpenTab(next,tab))setTab("home");
      try{await loadAll(next)}catch(e){setError(friendlyError(e))}
    }catch(e){setError(msg(e));await supabase.auth.signOut()}finally{setLoading(false)}
  }

  async function loadAll(p:Profile=profile as Profile){
    if(!p)return;
    const context=await commercialApi(supabase).context();setCommercialContext(context);
    const selected=context.organizations.find(o=>o.id===activeOrgId)||context.organizations[0];
    const c=capabilitiesFor(p,context,selected?.id),api=workflowApi(supabase);
    const base=await Promise.all([
      supabase.from("specialties").select("id,slug,name,active,sort_order").eq("active",true).order("sort_order"),
      supabase.from("profile_specialties").select("specialty_id").eq("profile_id",p.id),
      supabase.from("organizations").select("id,owner_profile_id,organization_type,display_name,business_type,market_role,buyer_subtype,active,created_at").eq("active",true).order("created_at"),
      c.professional?Promise.resolve({data:[],error:null}):supabase.from("events").select("id,client_id,name,venue,start_at,end_at,status,arrival_tolerance_minutes,calendar_sync_status,google_event_id,calendar_last_error,created_by_profile_id,organization_id").order("start_at"),
      supabase.from("job_applications").select("id,event_service_id,freelancer_id,status,message,created_at,updated_at").order("created_at",{ascending:false}),
      supabase.from("ratings").select("id,assignment_id,event_id,freelancer_id,reviewer_profile_id,rating,comment,created_at").order("created_at",{ascending:false}),
    ]);
    for(const r of base){if(r.error)throw r.error}
    setSpecialties((base[0].data||[]) as Specialty[]);setMySpecialtyIds((base[1].data||[]).map(x=>x.specialty_id));
    setOrganizations((base[2].data||[]) as Organization[]);setApplications((base[4].data||[]) as JobApplication[]);setRatings((base[5].data||[]) as Rating[]);
    if(c.professional){
      const own=await api.workerAssignments();setWorkAssignments(own);setOperations([]);setRemunerations([]);setWorkFinances([]);setFinanceIndex([]);
      const schedule=await supabase.rpc('get_my_schedule');if(schedule.error)throw schedule.error;
      setEvents(schedule.data?.events||[]);setServices(schedule.data?.services||[]);
      setAssignments(own.map(a=>({id:a.id,event_service_id:a.event_service_id,freelancer_id:a.freelancer_id,status:a.status,agreed_amount:acceptedAmount(a)})));
      setPayments(own.flatMap(a=>a.payments.map(p=>({...p,assignment_id:a.id}))));
    }else{
      const index=(base[3].data||[]) as EventRow[];
      const ops=await Promise.all(index.map(e=>getEventOperations(supabase,e.id)));setOperations(ops);setWorkAssignments([]);
      const allowedIds=new Set(ops.map(o=>o.event.id));setEvents(index.filter(e=>allowedIds.has(e.id)));setServices(ops.flatMap(o=>o.services));setAssignments(ops.flatMap(o=>o.assignments));

      const financialWork=await api.financeIndex();
      const [finance,terms]=await Promise.all([Promise.all(financialWork.map(e=>api.finance(e.event_id))),Promise.all(financialWork.map(e=>api.eventRemunerations(e.event_id)))]);
      setFinanceIndex(financialWork);setWorkFinances(finance);setRemunerations(terms.flat());setPayments([]);
    }
    setAttendance([]);
    if(c.viewClients&&selected?.market_role!=='buyer'){const r=await supabase.from("clients").select("id,trade_name,legal_name,contact_name,phone,email,active,organization_id").eq("active",true).order("trade_name");if(r.error)throw r.error;setClients((r.data||[]) as Client[])}else setClients([]);
    if(c.manageTeam||c.professional){const r=await supabase.rpc("get_professional_directory");if(r.error)throw r.error;setDirectory((r.data||[]) as DirectoryProfessional[])}else setDirectory([]);
    if(p.profile_type==='freelancer'){const r=await supabase.from('freelancers').select('id,profile_id,full_name,phone,city,active,rating,completed_jobs,no_show_count').eq('profile_id',p.id).maybeSingle();if(r.error)throw r.error;setOwnFreelancer(r.data as Freelancer|null)}else setOwnFreelancer(null);
    setOpportunities(await api.opportunities());
    if(selected?.can_finance){const workspace=await commercialApi(supabase).workspace(selected.id);setCommercialContracts(workspace.contracts)}else setCommercialContracts([]);
    if(c.manageCalendar){const r=await supabase.from('integrations').select('*').eq('kind','google_calendar').maybeSingle();if(r.error)throw r.error;setIntegration(r.data as Integration|null)}else setIntegration(null);
    setProfiles([]);
  }


  useEffect(()=>{
    if(loading||!profile||!commercialContext||deepLinkHandled.current)return;
    const link=location.pathname+location.search;
    if(!safeNotificationLink(link))return;
    const params=new URLSearchParams(location.search),opportunity=params.get('opportunity'),assignment=params.get('assignment'),contract=params.get('contract');
    deepLinkHandled.current=true;
    if(opportunity){const allowed=opportunities.find(o=>o.service_id===opportunity);if(!allowed||!allowed.compatible){setNotice('Esta oportunidade está indisponível ou exige outra especialidade.');return}setTab('events');setEventsMode('opportunities');setSelectedEventId(null);setDeepTarget('opportunity-'+opportunity)}
    if(assignment){if(!workAssignments.some(a=>a.id===assignment)){setNotice('Esta atualização não está disponível para sua conta.');return}setTab('schedule');setDeepTarget('assignment-'+assignment)}
    if(contract){void(async()=>{try{for(const organization of commercialContext.organizations.filter(o=>o.can_finance)){const workspace=await commercialApi(supabase).workspace(organization.id);if(workspace.contracts.some(c=>c.id===contract)){setActiveOrgId(organization.id);setTab('clients');setDeepTarget('contract-'+contract);return}}setNotice('Este contrato não está disponível para sua conta.')}catch{setError('Não foi possível abrir seu contrato.')}})()}
  },[loading,profile?.id,commercialContext,opportunities,workAssignments]);
  useEffect(()=>{
    if(!deepTarget)return;
    function focusTarget(){const target=document.getElementById(deepTarget!);if(!target)return false;target.scrollIntoView({block:'start'});target.focus({preventScroll:true});return true}
    if(focusTarget())return;
    const observer=new MutationObserver(()=>{if(focusTarget())observer.disconnect()});observer.observe(document.body,{childList:true,subtree:true});const timeout=setTimeout(()=>observer.disconnect(),10000);return()=>{clearTimeout(timeout);observer.disconnect()};
  },[deepTarget,tab]);

  async function login(e:FormEvent<HTMLFormElement>){
    e.preventDefault();const form=e.currentTarget;setBusy(true);setError("");setNotice("");
    const f=new FormData(form);const email=String(f.get("email")||"").trim();const password=String(f.get("password")||"");
    try{
      if(signup){
        const payload=profilePayload(form);
        if(!validateDocument(payload.document_type,payload.document_number))throw new Error("Confira o CPF/CNPJ informado.");
        if(!payload.specialty_ids.length)throw new Error("Selecione ao menos uma especialidade.");
        const response=await fetch("/api/auth/register",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email,password,payload}),cache:"no-store"});
        const result=await response.json().catch(()=>({}));
        if(!response.ok)throw new Error(typeof result.error==="string"?result.error:"Não foi possível concluir o cadastro. Tente novamente.");
        const passwordField=form.elements.namedItem("password") as HTMLInputElement|null;if(passwordField)passwordField.value="";
        setSignup(false);
        setNotice("Cadastro recebido! Confirme seu e-mail. Seus dados foram guardados de forma privada e serão ativados automaticamente após a confirmação. Se não receber, use Reenviar e-mail de confirmação.");
      }else{const {data,error}=await supabase.auth.signInWithPassword({email,password});if(error||!data.session)throw error||new Error("Falha no login");await boot(data.session)}
    }catch(e){setError(friendlyError(e))}finally{setBusy(false)}
  }

  async function resendConfirmation(){
    if(busy||resendCooldown>0)return;
    const emailField=authFormRef.current?.elements.namedItem("email") as HTMLInputElement|null;
    if(!emailField||!emailField.checkValidity()||!emailField.value.trim()){setNotice("");setError("Informe um e-mail válido no campo acima para reenviar a confirmação.");emailField?.focus();return}
    setBusy(true);setError("");setNotice("");
    try{
      const {error}=await supabase.auth.resend({type:"signup",email:emailField.value.trim(),options:{emailRedirectTo:location.origin}});
      if(error)throw error;
      setResendCooldown(60);
      setNotice("Se existir um cadastro aguardando confirmação neste e-mail, um novo link será enviado. Verifique também o spam.");
    }catch(e){setError(friendlyError(e))}finally{setBusy(false)}
  }

  useEffect(()=>{if(profile&&activeOrgId)void refresh()},[activeOrgId]);

  async function logout(){setProfile(null);setCommercialContext(null);setNotificationsOpen(false);await supabase.auth.signOut();location.reload()}
  async function refresh(){if(!profile)return;setBusy(true);setError("");try{await loadAll(profile)}catch(e){setError(friendlyError(e))}finally{setBusy(false)}}

  async function completeOnboarding(payload:ProfilePayload){
    if(!profile)return;setBusy(true);setError("");
    try{const r=await supabase.rpc("complete_profile",{p_payload:payload});if(r.error)throw r.error;setEditProfile(false);await boot(session!);setNotice("Perfil atualizado. O EventCore foi personalizado para você.")}
    catch(e){setError(friendlyError(e))}finally{setBusy(false)}
  }
  async function action(work:()=>PromiseLike<{error:any}>,success:string){if(mutationLock.current)return;mutationLock.current=true;setBusy(true);setError("");try{const r=await work();if(r.error)throw r.error;setNotice(success);await loadAll()}catch(e){setError(friendlyError(e))}finally{mutationLock.current=false;setBusy(false)}}
  async function createClient(e:FormEvent<HTMLFormElement>){e.preventDefault();const form=e.currentTarget;const f=new FormData(form);setBusy(true);try{const payload:any={trade_name:String(f.get("trade_name")),contact_name:String(f.get("contact_name")||"")||null,phone:String(f.get("phone")||"")||null,email:String(f.get("email")||"")||null};if(currentOrg)payload.organization_id=currentOrg.id;if(!selectedCommercialOrg||selectedCommercialOrg.market_role!=="provider")throw new Error("Configure sua atividade como fornecedor.");await workflowApi(supabase).createExternalClient(selectedCommercialOrg.id,payload.trade_name);form.reset();setNotice("Cliente cadastrado.");await loadAll()}catch(e){setError(friendlyError(e))}finally{setBusy(false)}}
  async function createEvent(input:EventCreationInput):Promise<boolean>{
    if(!profile)return false;
    setBusy(true);setError("");setNotice("");
    try{
      const created=await workflowApi(supabase).createWork({...input.event,organization_id:selectedCommercialOrg?.id},input.services);
      setEvents(rows=>[...rows,{...created.event,calendar_sync_status:"pending"}]);setServices(rows=>[...rows,...created.services]);
      setSelectedEventId(created.event.id);setEventPane("equipe");
      setNotice(input.services.length?"Evento e funções criados.":"Evento criado.");
      // A committed event stays successful even if the subsequent refresh fails.
      try{await loadAll()}catch(error){setError(friendlyError(error))}
      return true;
    }catch(error){setError(friendlyError(error));return false}finally{setBusy(false)}
  }
  async function applyToService(o:Opportunity){await action(()=>supabase.rpc("apply_for_opportunity",{p_service_id:o.service_id}),"Interesse enviado ao contratante.");}
  async function withdrawApplication(app:JobApplication){setBusy(true);try{const r=await supabase.from("job_applications").update({status:"withdrawn",updated_at:new Date().toISOString()}).eq("id",app.id);if(r.error)throw r.error;setNotice("Candidatura retirada.");await loadAll()}catch(e){setError(friendlyError(e))}finally{setBusy(false)}}
  async function hireApplication(app:JobApplication){await action(()=>supabase.rpc("hire_application",{p_application_id:app.id}),"Contratação registrada. O profissional recebeu uma convocação.");}
  async function reviewApplication(app:JobApplication,status:"shortlisted"|"rejected"){await action(()=>supabase.rpc("review_application",{p_application_id:app.id,p_status:status}),status==="shortlisted"?"Candidatura pré-selecionada.":"Candidatura não selecionada.");}
  function position(){return new Promise<{lat:number;lng:number}>((resolve,reject)=>{if(!navigator.geolocation)return reject(new Error("Geolocalização indisponível."));navigator.geolocation.getCurrentPosition(p=>resolve({lat:p.coords.latitude,lng:p.coords.longitude}),()=>reject(new Error("Permita acesso à localização.")),{enableHighAccuracy:true,timeout:12000,maximumAge:30000})})}
  async function presence(a:Assignment,kind:"in"|"out"){setBusy(true);setError("");try{const pos=await position();const r=await supabase.rpc("record_assignment_attendance",{p_assignment_id:a.id,p_kind:kind,p_lat:pos.lat,p_lng:pos.lng});if(r.error)throw r.error;setNotice(kind==="in"?"Check-in registrado.":"Check-out registrado.");await loadAll()}catch(e){setError(friendlyError(e))}finally{setBusy(false)}}
  async function respondAssignment(a:Assignment,status:"confirmed"|"cancelled"){await action(()=>supabase.rpc("respond_to_assignment",{p_assignment_id:a.id,p_status:status}),status==="confirmed"?"Presença confirmada.":"Convocação cancelada. Os valores ainda não pagos também foram cancelados.");}
  async function pay(a:Assignment,method:string){await action(()=>supabase.rpc("mark_assignment_paid",{p_assignment_id:a.id,p_method:method}),"Pagamento registrado.");}
  async function rateAssignment(e:FormEvent<HTMLFormElement>,a:Assignment,eventId:string){e.preventDefault();const f=new FormData(e.currentTarget);await action(()=>supabase.rpc("submit_assignment_rating",{p_assignment_id:a.id,p_rating:Number(f.get("rating")),p_comment:String(f.get("comment")||"")}),"Avaliação registrada.");}
  async function viewReputation(id:string){const sequence=++reputationRequest.current;const r=await supabase.rpc("get_professional_reputation",{p_freelancer_id:id});if(sequence!==reputationRequest.current)return;if(r.error)setError(friendlyError(r.error));else if(r.data)setReputation({...r.data,freelancer_id:id} as Reputation);}
  async function connectGoogle(){if(!session)return;setBusy(true);setError("");try{const r=await fetch("/api/google/connect",{method:"POST",headers:{Authorization:`Bearer ${session.access_token}`}});const data=await r.json();if(!r.ok)throw new Error(data.error||"Falha ao iniciar Google OAuth");location.href=data.authorizeUrl}catch(e){setError(msg(e));setBusy(false)}}
  async function syncEvent(id:string){if(!session)return false;setBusy(true);setError("");try{const r=await fetch("/api/google/sync",{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${session.access_token}`},body:JSON.stringify({eventId:id})});const data=await r.json();if(!r.ok)throw new Error(data.error||"Falha ao sincronizar");setNotice("Evento sincronizado com o Google Calendar.");await loadAll();return true}catch(e){setError(msg(e));await supabase.from("events").update({calendar_sync_status:"error",calendar_last_error:msg(e),updated_at:new Date().toISOString()}).eq("id",id);await loadAll();return false}finally{setBusy(false)}}
  async function syncPending(){for(const ev of events.filter(e=>e.status!=="cancelled"&&e.end_at&&e.calendar_sync_status!=="synced")){await syncEvent(ev.id)}}

  const managedEvents=events.filter(e=>operations.some(o=>o.event.id===e.id)&&(!e.organization_id||!currentOrg||e.organization_id===currentOrg.id));
  const managedIds=new Set(managedEvents.map(e=>e.id));
  const scopedFinanceIds=new Set(financeIndex.filter(e=>!e.organization_id||!currentOrg||e.organization_id===currentOrg.id).map(e=>e.event_id));
  const scopedWorkFinances=workFinances.filter(f=>scopedFinanceIds.has(f.event_id));
  const workerMetrics=workerDashboardMetrics(workAssignments);
  const managedServices=services.filter(s=>managedIds.has(s.event_id));
  const serviceIds=new Set(managedServices.map(s=>s.id));
  const managedAssignments=assignments.filter(a=>serviceIds.has(a.event_service_id));
  const assignmentIds=new Set(managedAssignments.map(a=>a.id));
  const scopedClients=clients.filter(c=>caps?.staff||c.organization_id===currentOrg?.id);
  const myAssignments=ownFreelancer?assignments.filter(a=>a.freelancer_id===ownFreelancer.id):[];
  const myIds=new Set(myAssignments.map(a=>a.id));
  const myPayments=payments.filter(p=>myIds.has(p.assignment_id));
  const myRatings=ratings.filter(r=>r.freelancer_id===ownFreelancer?.id);
  const myApplications=applications.filter(a=>a.freelancer_id===ownFreelancer?.id);
  const freelancerStats=freelancerDashboard({events,services,assignments:myAssignments,payments:myPayments,applications:myApplications,ratings:myRatings});
  const managedPayments=payments.filter(p=>assignmentIds.has(p.assignment_id));
  const businessStats=businessDashboard({events:managedEvents,services:managedServices,assignments:managedAssignments,payments:managedPayments,clients:scopedClients});
  const selectedOperations=operations.find(o=>o.event.id===selectedEventId);
  const selectedEvent=managedEvents.find(e=>e.id===selectedEventId)||null;
  const selectedServices=services.filter(s=>s.event_id===selectedEventId);
  const selectedServiceIds=new Set(selectedServices.map(s=>s.id));
  const selectedAssignments=assignments.filter(a=>selectedServiceIds.has(a.event_service_id));
  const selectedApplications=applications.filter(a=>selectedServiceIds.has(a.event_service_id));
  const filteredOpportunities=opportunities;
  const activeEvents=managedEvents.filter(e=>!['completed','cancelled'].includes(e.status));
  const nameFor=(id:string)=>directory.find(f=>f.freelancer_id===id)?.full_name||ownFreelancer?.full_name||'Profissional';
  const openEvent=(id:string)=>{setTab('events');setEventsMode('mine');setSelectedEventId(id);setEventPane('equipe')};
  useEffect(()=>{if(tab==='events'&&selectedEvent){window.scrollTo({top:0,behavior:'auto'});eventHeading.current?.focus({preventScroll:true})}},[tab,selectedEvent?.id]);

  if(loading)return <div className="loading">Abrindo EventCore…</div>;
  if(!session||!profile)return <main className="loginShell"><section className={`loginCard ${signup?'signupCard':''}`}>
    <Brand/><p className="eyebrow">SUA OPERAÇÃO DE EVENTOS</p><h1>{signup?'Criar conta':'Entrar no EventCore'}</h1><p className="subtle">Conecte oportunidades, equipes e eventos.</p>
    <div className="switch"><button type="button" className={!signup?'active':''} onClick={()=>{setSignup(false);setError('')}}>Entrar</button><button type="button" className={signup?'active':''} onClick={()=>{setSignup(true);setError('')}}>Criar conta</button></div>
    <form className="form" onSubmit={login} ref={authFormRef}>
      {signup&&<ProfileFields specialties={authSpecialties}/>}
      <label>E-mail<input className="input" type="email" name="email" autoComplete="email" required/></label>
      <label>Senha<input className="input" type="password" name="password" autoComplete={signup?'new-password':'current-password'} minLength={8} required/></label>
      {error&&<div className="error" role="alert">{error}</div>}{notice&&<div className="notice" role="status">{notice}</div>}
      <button className="btn" disabled={busy||signup&&!authSpecialties.length}>{busy?'Aguarde…':signup?'Criar minha conta':'Entrar'}</button>
      {!signup&&<button className="btn ghost" type="button" disabled={busy||resendCooldown>0} onClick={resendConfirmation}>{resendCooldown>0?`Reenviar em ${resendCooldown}s`:"Reenviar e-mail de confirmação"}</button>}
      {signup&&<small className="subtle">Seu CPF/CNPJ fica na área privada de identificação e não aparece no perfil profissional.</small>}
    </form>
  </section></main>;

  const profileLabel=isStaff(profile)?profile.role==='admin'?'Administrador':'Coordenador':profile.profile_type?profileTypeLabel[profile.profile_type]:'Complete seu perfil';
  const needsOnboarding=!isStaff(profile)&&(!profile.onboarding_completed||!profile.profile_type);

  return <div className="app"><aside className="sidebar"><Brand/><nav aria-label="Navegação principal">{nav.map(n=><button key={n.id} title={n.label} aria-current={tab===n.id?'page':undefined} className={tab===n.id?'active':''} onClick={()=>{setTab(n.id);setEditProfile(false);if(n.id==='events')setSelectedEventId(null)}}><AppIcon name={n.id}/><span>{n.label}</span></button>)}</nav><div className="userbox"><strong>{profile.full_name}</strong><small>{profileLabel}</small></div><button className="btn ghost" onClick={logout}>Sair</button></aside>
    <main className="main"><header className="appHeader"><Brand/><div className="headerActions">
<button className="iconButton" type="button" aria-label="Atualizar dados" title="Atualizar dados" disabled={busy} onClick={refresh}><AppIcon name="refresh"/></button>
<details className="accountMenu"><summary aria-label="Mais opções e conta" title="Mais opções e conta"><ProfileAvatar url={ownPhotos.avatar?.url} name={profile.full_name}/>{unreadCount>0&&<span className="notificationBadge" role="status" aria-label={`${unreadCount} ${unreadCount===1?"atualização não lida":"atualizações não lidas"}`}>{unreadCount}</span>}</summary><div className="accountDropdown"><div className="accountIdentity"><strong>{profile.full_name}</strong><small>{profileLabel}</small></div><nav aria-label="Meu perfil e fotos"><button type="button" onClick={e=>{setNotificationsOpen(true);e.currentTarget.closest("details")?.removeAttribute("open")}}>Notificações e preferências</button><button type="button" onClick={e=>{openProfileSection('profile-photo');e.currentTarget.closest("details")?.removeAttribute("open")}}><AppIcon name="camera"/><span>Alterar foto de perfil</span></button><button type="button" onClick={e=>{openProfileSection('profile-portfolio');e.currentTarget.closest("details")?.removeAttribute("open")}}><AppIcon name="gallery"/><span>Meu portfólio</span></button><button type="button" onClick={e=>{openProfileSection('profile-data');e.currentTarget.closest("details")?.removeAttribute("open")}}><AppIcon name="edit"/><span>Editar meus dados</span></button></nav><nav aria-label="Mais páginas">{extraNavigation.map(n=><button key={n.id} type="button" aria-current={tab===n.id?'page':undefined} className={tab===n.id?'active':''} onClick={e=>{setTab(n.id);setEditProfile(false);if(n.id==='events')setSelectedEventId(null);e.currentTarget.closest("details")?.removeAttribute("open")}}><AppIcon name={n.id}/><span>{n.label}</span></button>)}</nav><button className="accountLogout" type="button" onClick={logout}><AppIcon name="logout"/><span>Sair da conta</span></button></div></details>
</div></header><header className="topbar"><div><p className="eyebrow">{profileLabel}</p><h1>{nav.find(n=>n.id===tab)?.label||'EventCore'}</h1><p className="subtle">{currentOrg?.display_name||'EventCore · Marujo Eventos'}</p></div><div className="topActions">{organizations.length>1&&<label className="orgSelect">Organização<select className="select" value={currentOrg?.id||''} onChange={e=>{setActiveOrgId(e.target.value);setSelectedEventId(null)}}>{organizations.map(o=><option key={o.id} value={o.id}>{o.display_name}</option>)}</select></label>}{installPrompt&&<button className="btn secondary" onClick={async()=>{await installPrompt.prompt();setInstallPrompt(null)}}>Instalar app</button>}</div></header>
    {error&&<div className="error" role="alert">{error}</div>}{notice&&<div className="notice" role="status">{notice}</div>}
    {(!commercialContext?.identity_complete||!selectedCommercialOrg||selectedCommercialOrg.market_role==='unclassified')&&!caps?.professional&&<section className="panel"><p>Seu histórico continua disponível. Complete a identificação e escolha sua atividade para novas operações.</p><button className="btn secondary" onClick={()=>openProfileSection('business-setup')}>Configurar identificação e atividade</button></section>}
    {needsOnboarding?<section className="panel onboarding"><p className="eyebrow">PERSONALIZE SUA EXPERIÊNCIA</p><h2>Complete seu perfil para personalizar o EventCore.</h2><p className="subtle">Sua conta e seus dados anteriores continuam vinculados.</p><ProfileForm profile={profile} specialties={specialties} ids={mySpecialtyIds} organization={profileOrganization} busy={busy} submit={completeOnboarding}/></section>:<>

    {notificationsOpen&&<Notifications key={profile.id} accountId={profile.id} specialties={specialties} onClose={()=>setNotificationsOpen(false)}/>}
    {tab==='home'&&<><section className="welcome panel"><div><p className="eyebrow">{caps?.professional?'SEU PRÓXIMO TRABALHO':'SUA PRÓXIMA OPERAÇÃO'}</p><h2>Olá, {profile.full_name?.split(' ')[0]||'bem-vindo'}.</h2><p className="subtle">{caps?.professional?'Veja vagas compatíveis, responda às convocações e acompanhe seus recebimentos.':profile.profile_type==='team_lead'?'Organize sua equipe, acompanhe a escala e encontre novas oportunidades.':profile.profile_type==='agency'?'Conecte seus clientes às equipes e acompanhe cada evento.':'Acompanhe seus eventos, clientes e profissionais em um só lugar.'}</p></div><button className="btn" onClick={()=>{setTab('events');setEventsMode(caps?.professional?'opportunities':'mine')}}>{caps?.professional?'Explorar oportunidades':'Abrir meus eventos'}</button></section>
      <section className="metrics">{caps?.professional?<><Metric label="Próximas convocações" value={myAssignments.filter(a=>a.status==='invited').length} detail="aguardando sua resposta"/><Metric label="Vagas compatíveis" value={filteredOpportunities.filter(o=>o.vacancies>0).length} detail="com vagas disponíveis"/><Metric label="A receber de contratos futuros" value={brl(freelancerStats.upcomingIncome)} detail="convocações confirmadas"/></>:<><Metric label="Eventos ativos" value={activeEvents.length} detail="na sua operação"/><Metric label="Vagas preenchidas" value={businessStats.filledVacancies} detail={`${businessStats.vacancies} vagas criadas`}/><Metric label="Clientes" value={businessStats.clients} detail="base comercial"/></>}</section>
      <section className="panel eventsPanel"><h2>{caps?.professional?'Minha próxima escala':'Próximos eventos'}</h2>{caps?.professional?<WorkerWork rows={workAssignments.filter(a=>!['cancelled','checked_out','no_show'].includes(a.status)).slice(0,4)} refresh={refresh}/>:activeEvents.length?activeEvents.slice(0,5).map(ev=><EventCard key={ev.id} ev={ev} services={services} assignments={assignments} open={()=>openEvent(ev.id)}/>):<Empty text="Crie seu primeiro evento para começar a montar a equipe."/>}</section>
      {caps?.manageCalendar&&<section className="panel integrationPanel"><div><h3>Google Calendar</h3><p className="subtle">{integration?.status==='connected'?`Conectado a ${integration.account_email||'sua conta Google'}`:'Conecte a agenda que você já usa.'}</p></div><div className="rowActions">{integration?.status!=='connected'?<button className="btn secondary" disabled={busy} onClick={connectGoogle}>Conectar Google Calendar</button>:<><button className="btn secondary" disabled={busy} onClick={syncPending}>Sincronizar pendentes</button><button className="btn ghost" disabled={busy} onClick={()=>action(async()=>{const r=await fetch('/api/google/disconnect',{method:'POST',headers:{Authorization:`Bearer ${session.access_token}`}});const d=await r.json();return {error:r.ok?null:new Error(d.error||'Falha ao desconectar')}} ,'Google Calendar desconectado.')}>Desconectar</button></>}</div></section>}
    </>}

    {tab==='dashboard'&&<><p className="subtle">Indicadores de suas relações e operações autorizadas. Valores desconhecidos permanecem não informados.</p><section className="metrics">{caps?.professional?<><Metric label="Trabalhos ativos" value={workerMetrics.activeWork} detail="suas convocações e escala"/><Metric label="Trabalhos concluídos confirmados" value={workerMetrics.completedWork} detail="conclusão ou presença validada"/><Metric label="Recebido" value={money(workerMetrics.paidTotal)} detail="pagamentos registrados para você"/></>:<><Metric label="Eventos ativos" value={activeEvents.length} detail="operações autorizadas"/><Metric label="Eventos concluídos" value={managedEvents.filter(e=>e.status==='completed').length} detail="histórico preservado"/></>}</section>{caps?.professional?<WorkerWork rows={workAssignments} refresh={refresh}/>:scopedWorkFinances.map(f=><section key={f.event_id}><h2>{financeIndex.find(e=>e.event_id===f.event_id)?.event_name}</h2><WorkFinancePanel finance={f} identityComplete={!!commercialContext?.identity_complete&&selectedCommercialOrg?.market_role!=='buyer'} refresh={refresh} contracts={commercialContracts}/><TeamPayments rows={remunerations.filter(a=>a.event_id===f.event_id)} identityComplete={!!commercialContext?.identity_complete&&selectedCommercialOrg?.market_role!=='buyer'} refresh={refresh}/></section>)}{selectedCommercialOrg?.can_finance&&selectedCommercialOrg.market_role==='buyer'&&<CommercialWorkspace organization={selectedCommercialOrg} identityComplete={!!commercialContext?.identity_complete}/>}</>}

    {tab==='clients'&&selectedCommercialOrg?.can_finance&&selectedCommercialOrg.market_role!=='unclassified'&&<CommercialWorkspace organization={selectedCommercialOrg} identityComplete={!!commercialContext?.identity_complete} clients={scopedClients}/>}
    {tab==='clients'&&selectedCommercialOrg?.market_role==='provider'&&selectedCommercialOrg.can_operate&&<section className="twoCol"><div className="panel"><h2>Seus clientes</h2>{scopedClients.length?<div className="simpleList">{scopedClients.map(c=><article key={c.id}><strong>{c.trade_name}</strong><span>{[c.contact_name,c.phone,c.email].filter(Boolean).join(' · ')||'Sem contato informado'}</span></article>)}</div>:<Empty text="Nenhum cliente cadastrado."/>}</div><form className="panel form" onSubmit={createClient}><h2>Novo cliente</h2><label>Nome do cliente<input className="input" name="trade_name" required maxLength={150}/></label><button className="btn" disabled={busy}>Cadastrar cliente</button></form></section>}

    {tab==='team'&&<>{selectedCommercialOrg&&selectedCommercialOrg.market_role!=='unclassified'&&<RelationshipHistory organization={selectedCommercialOrg}/>} {selectedCommercialOrg?.market_role==='provider'&&<ProviderPeoplePanel organization={selectedCommercialOrg} directory={directory}/>}<section className="panel"><h2>Diretório de profissionais</h2><p className="subtle">Descoberta de profissionais. Cadastro não representa trabalho realizado com sua organização.</p><div className="cardGrid">{directory.map(f=><article className="professionalCard" key={f.freelancer_id}><h3>{f.full_name}</h3><p>{f.city} · {f.specialties.join(' · ')}</p><p>{f.rating==null?'Sem avaliações':`★ ${Number(f.rating).toFixed(1)}`} · {f.review_count} avaliações</p></article>)}</div>{!directory.length&&<Empty text="Nenhum profissional disponível."/>}</section></>}

    {tab==='events'&&selectedCommercialOrg?.market_role==='buyer'&&<>{selectedCommercialOrg.can_finance?<CommercialWorkspace organization={selectedCommercialOrg} identityComplete={!!commercialContext?.identity_complete}/>:<p className='notice'>Acompanhamento comercial requer autorização financeira do responsável.</p>}</>}
    {tab==='events'&&<>
      {(caps?.manageEvents||managedEvents.length>0)&&!selectedEvent&&<div className="switch eventsSwitch"><button className={eventsMode==='mine'?'active':''} onClick={()=>{setEventsMode('mine');setSelectedEventId(null)}}>Meus eventos</button><button className={eventsMode==='opportunities'?'active':''} onClick={()=>{setEventsMode('opportunities');setSelectedEventId(null)}}>Oportunidades</button></div>}
      {((!caps?.manageEvents&&managedEvents.length===0)||eventsMode==='opportunities')?<><section className="panel"><div className="sectionHead"><div><h2>{caps?.professional?'Oportunidades para suas especialidades':'Oportunidades'}</h2><p className="subtle">{caps?.professional?'Demonstre interesse e acompanhe a resposta do contratante.':'Vagas abertas no EventCore. As candidaturas são enviadas pelas contas dos profissionais.'}</p></div></div><div className="cardGrid">{filteredOpportunities.map(o=>{const app=myApplications.find(a=>a.event_service_id===o.service_id);return <article className="opportunityCard" id={"opportunity-"+o.service_id} tabIndex={-1} key={o.service_id}><div className="cardTop"><span className="status">{o.vacancies} vagas</span><small>{eventStatus[o.event_status]}</small></div><h3>{o.event_name}</h3><strong>{o.function_name}</strong><p className="subtle">{calendarDate(o.start_at)} · {o.venue}</p><p className="subtle">{contractDaysLabel(o.contract_days)}</p><p>{o.amount!=null?brl(Number(o.amount)):'Valor a combinar'} · {o.contractor_name}</p>{o.requirements&&<p className="subtle">Requisitos: {o.requirements}</p>}<OpportunityShare id={o.service_id}/>{caps?.applyForJobs&&(app&&app.status!=='withdrawn'?<div className="actions"><span className="done">{applicationStatus[app.status]}</span>{['interested','shortlisted'].includes(app.status)&&<button className="btn ghost" disabled={busy} onClick={()=>withdrawApplication(app)}>Retirar candidatura</button>}</div>:<button className="btn" disabled={busy||o.vacancies===0||!o.compatible} onClick={()=>applyToService(o)}>{!o.compatible?'Especialidade incompatível':o.vacancies?'Tenho interesse':'Vagas preenchidas'}</button>)}</article>})}</div>{!filteredOpportunities.length&&<Empty text="Não há vagas abertas para este perfil no momento."/>}</section>
      {caps?.professional&&<section className="panel integrationPanel"><div><h3>Minhas candidaturas</h3>{myApplications.length?myApplications.map(a=><div className="operationRow" key={a.id}><div><strong>{opportunities.find(o=>o.service_id===a.event_service_id)?.event_name||services.find(s=>s.id===a.event_service_id)?.label||'Oportunidade'}</strong><span>{applicationStatus[a.status]} · {date(a.created_at)}</span></div>{['interested','shortlisted'].includes(a.status)&&<button className="btn secondary" disabled={busy} onClick={()=>withdrawApplication(a)}>Retirar</button>}</div>):<Empty text="Você ainda não enviou candidaturas."/>}</div></section>}
      </>:<>{!selectedEvent&&<div className="eventsGrid"><section className="panel"><h2>Meus eventos</h2>{managedEvents.length?managedEvents.map(ev=><EventCard key={ev.id} ev={ev} services={services} assignments={assignments} open={()=>openEvent(ev.id)}/>):<Empty text="Nenhum evento cadastrado."/>}</section>{commercialContext?.identity_complete&&selectedCommercialOrg?.market_role==='provider'&&selectedCommercialOrg.can_operate&&selectedCommercialOrg.can_finance?<EventCreationForm clients={scopedClients} contracts={commercialContracts.filter(c=>c.provider_organization_id===selectedCommercialOrg.id)} organizationId={selectedCommercialOrg.id} specialties={specialties} busy={busy} onCreate={createEvent}/>:<section className="panel"><p>Novos trabalhos exigem identificação e atividade de fornecedor com autorização financeira. O histórico existente permanece acessível.</p><button className="btn secondary" onClick={()=>openProfileSection('business-setup')}>Configurar atividade comercial</button></section>}</div>}
      {selectedEvent&&<section className="operator eventDetail"><button className="btn secondary eventBack" type="button" aria-label="Voltar para meus eventos" onClick={()=>{setSelectedEventId(null);window.scrollTo({top:0,behavior:'auto'})}}>← Voltar para meus eventos</button><div className="operatorHead"><div><p className="eyebrow">OPERAÇÃO DO EVENTO</p><h2 ref={eventHeading} tabIndex={-1}>{selectedEvent.name}</h2><p className="subtle">{date(selectedEvent.start_at)} · {selectedEvent.venue}</p></div><div className="rowActions">{caps?.manageCalendar&&selectedCommercialOrg?.market_role!=='buyer'&&<button className="btn secondary" disabled={busy||!selectedEvent.end_at} onClick={()=>syncEvent(selectedEvent.id)}>Sincronizar Google</button>}<label>Status<select className="select" aria-label="Status do evento" value={selectedEvent.status} disabled={busy||selectedCommercialOrg?.market_role==='buyer'||['completed','cancelled'].includes(selectedEvent.status)} onChange={e=>action(()=>supabase.from('events').update({status:e.target.value,updated_at:new Date().toISOString()}).eq('id',selectedEvent.id),'Status atualizado.')}>{Object.entries(eventStatus).filter(([k])=>k!=='completed'||selectedEvent.status==='completed').map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label></div></div>
        {selectedOperations&&<WorkDetail key={selectedEvent.id} operations={selectedOperations} organization={selectedCommercialOrg} identityComplete={!!commercialContext?.identity_complete&&selectedCommercialOrg?.market_role!=='buyer'} remunerations={remunerations.filter(a=>a.event_id===selectedEvent.id)} finance={workFinances.find(f=>f.event_id===selectedEvent.id)} applications={selectedApplications} directory={directory} refresh={refresh} onProfile={id=>void viewReputation(id)}/>}

      </section>}</>}
    </>}

    {tab==='schedule'&&caps?.professional&&<WorkerWork rows={workAssignments} refresh={refresh}/>}
    {tab==='finance'&&<>{selectedCommercialOrg?.market_role==='buyer'&&selectedCommercialOrg.can_finance&&<CommercialWorkspace organization={selectedCommercialOrg} identityComplete={!!commercialContext?.identity_complete}/>} {caps?.professional?<WorkerWork rows={workAssignments} refresh={refresh}/>:scopedWorkFinances.length?scopedWorkFinances.map(f=><section key={f.event_id}><h2>{financeIndex.find(e=>e.event_id===f.event_id)?.event_name}</h2><WorkFinancePanel finance={f} identityComplete={!!commercialContext?.identity_complete&&selectedCommercialOrg?.market_role!=='buyer'} refresh={refresh} contracts={commercialContracts}/><TeamPayments rows={remunerations.filter(a=>a.event_id===f.event_id)} identityComplete={!!commercialContext?.identity_complete&&selectedCommercialOrg?.market_role!=='buyer'} refresh={refresh}/></section>):<p className="notice">Nenhum financeiro autorizado disponível.</p>}</>}

    {tab==='reputation'&&caps?.professional&&<section className="panel"><h2>Minha reputação profissional</h2><p>{freelancerStats.reviewCount?`★ ${freelancerStats.reviewAverage?.toFixed(1)}/5 · ${freelancerStats.reviewCount} avaliações`:'Você ainda não recebeu avaliações.'}</p><p className="subtle">{mySpecialtyIds.map(id=>specialties.find(s=>s.id===id)?.name).filter(Boolean).join(' · ')}</p>{myRatings.map(r=><article className="ratingRow" key={r.id}><strong>★ {r.rating}/5 · {events.find(e=>e.id===r.event_id)?.name||'Evento concluído'}</strong><p className="subtle">{date(r.created_at)}</p>{r.comment&&<p>{r.comment}</p>}</article>)}</section>}
    {tab==='profile'&&<><BusinessSetup key={selectedCommercialOrg?.id||'new'} context={commercialContext} organization={selectedCommercialOrg} refresh={refresh}/><section id="profile-data" tabIndex={-1} className="panel onboarding"><div className="sectionHead"><h2>Meu perfil</h2>{!editProfile&&<button className="btn secondary" onClick={()=>setEditProfile(true)}>Editar perfil</button>}</div>{editProfile?<ProfileForm profile={profile} specialties={specialties} ids={mySpecialtyIds} organization={profileOrganization} busy={busy} submit={completeOnboarding}/>:<div className="simpleList"><article><strong>{profile.full_name}</strong><span>{profileLabel} · {session.user.email}</span></article><article><strong>Especialidades</strong><span>{mySpecialtyIds.map(id=>specialties.find(s=>s.id===id)?.name).filter(Boolean).join(' · ')||'Ainda não informadas'}</span></article>{profileOrganization&&<article><strong>{profileOrganization.display_name}</strong><span>{profileOrganization.business_type}</span></article>}<article><strong>Disponibilidade</strong><span>{availability(profile.professional_status)}</span></article>{profile.bio&&<article><strong>Apresentação</strong><span>{profile.bio}</span></article>}<p className="subtle">Sua identificação CPF/CNPJ é privada.</p></div>}</section><ProfilePhotoEditor name={profile.full_name} photos={ownPhotos} loading={photosLoading} loadError={photosError} onRefresh={refreshOwnPhotos}/></>}
    </>}
    {reputation&&<div className="modalBackdrop" onClick={closeProfessionalProfile}><section className="panel reputationModal" role="dialog" aria-modal="true" aria-labelledby="reputation-name" onClick={e=>e.stopPropagation()}><div className="sectionHead"><h2 id="reputation-name">{reputation.name}</h2><button className="btn ghost" onClick={closeProfessionalProfile}>Fechar</button></div><p className="subtle">{availability(reputation.availability||'')}</p>{reputation.bio&&<p>{reputation.bio}</p>}<ProfessionalPhotos key={reputation.freelancer_id} freelancerId={reputation.freelancer_id} name={reputation.name}/><h3>Avaliações de trabalhos</h3>{reputation.reviews.length?reputation.reviews.map(r=><article className="ratingRow" key={r.id}><strong>★ {r.rating}/5 · {r.event_name}</strong><small className="subtle"> {date(r.date)}</small>{r.comment&&<p>{r.comment}</p>}</article>):<Empty text="Este profissional ainda não recebeu avaliações."/>}</section></div>}
    </main><nav className="mobileNav" aria-label="Navegação móvel">{mobileNavigation.map(n=><button key={n.id} aria-current={tab===n.id?'page':undefined} className={tab===n.id?'active':''} onClick={()=>{setTab(n.id);setEditProfile(false);if(n.id==='events')setSelectedEventId(null)}}><AppIcon name={n.id}/><span>{n.label}</span></button>)}</nav>
  </div>;
}

function contractDaysLabel(days?:number|null){return days==null?"Dias de contratação não informados":`${days} ${days===1?'dia':'dias'} de contratação`}
function date(value:string){return new Date(value).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'})}
function availability(value:string){return ({available:'Disponível para trabalhos',busy:'Em trabalho',unavailable:'Indisponível no momento'} as Record<string,string>)[value]||'Disponibilidade não informada'}
function Brand(){return <div className="brand"><div className="logo" aria-hidden="true"><svg width="36" height="32" viewBox="0 0 36 32" fill="none"><path d="M4 6h26M4 15h18M4 24h22" stroke="#3fc79b" strokeWidth="5.5" strokeLinecap="round"/><circle cx="32" cy="24" r="3" fill="#e5ba73"/></svg></div><div><strong>EventCore</strong><small>Marujo Eventos</small></div></div>}
function Metric({label,value,detail}:{label:string;value:number|string;detail:string}){
  const icon:IconName=/receb|pago|custo|contrato/i.test(label)?'finance':/avalia/i.test(label)?'reputation':/cliente/i.test(label)?'clients':/vaga|convoca/i.test(label)?'team':'events';
  return <article className="metric"><div className="metricSymbol"><AppIcon name={icon}/></div><span>{label}</span><strong className={typeof value==='string'&&value.includes('R$')?'currencyValue':undefined}>{value}</strong><small>{detail}</small></article>
}
function Empty({text}:{text:string}){return <div className="empty"><span>{text}</span></div>}
function EventCard({ev,services,assignments,open}:{ev:EventRow;services:EventService[];assignments:Assignment[];open:()=>void}){
  const sv=services.filter(s=>s.event_id===ev.id);const ids=new Set(sv.map(s=>s.id));const need=sv.reduce((n,s)=>n+s.quantity_needed,0);const filled=assignments.filter(a=>ids.has(a.event_service_id)&&['invited','confirmed','checked_in','checked_out'].includes(a.status)).length;
  const progress=need?Math.min(100,Math.round(filled/need*100)):0;
  return <button className="eventCard" onClick={open} aria-label={`Abrir ${ev.name}, ${ev.venue}, ${date(ev.start_at)}, ${eventStatus[ev.status]}, ${filled} de ${need} vagas preenchidas, ${calendarStatus[ev.calendar_sync_status]||'Agenda'}`}>
    <div className="eventCardHeading"><span className="eyebrow">OPERAÇÃO EM EVENTO</span><strong>{ev.name}</strong></div>
    <div className="eventCardDetails"><span><AppIcon name="location"/>{ev.venue}</span><span><AppIcon name="schedule"/>{date(ev.start_at)} · {eventStatus[ev.status]}</span></div>
    <div className="eventProgress"><div className="progressRing"><svg viewBox="0 0 56 56" aria-hidden="true"><circle className="progressTrack" cx="28" cy="28" r="24"/><circle className="progressValue" cx="28" cy="28" r="24" strokeDasharray="150.8" strokeDashoffset={150.8*(1-progress/100)}/></svg><strong>{progress}%</strong></div><div><strong>{filled} de {need}</strong><span>vagas preenchidas</span></div></div>
    <span className="status eventCalendarStatus">{calendarStatus[ev.calendar_sync_status]||'Agenda'}</span><AppIcon name="arrow" className="eventOpenArrow"/>
  </button>
}
function BarChart({title,months,field,currency=false}:{title:string;months:{key:string;label:string;paid:number;jobs:number;cost:number;events:number}[];field:'paid'|'jobs'|'cost'|'events';currency?:boolean}){
 const max=Math.max(1,...months.map(m=>m[field]));const empty=months.every(m=>m[field]===0);
 return <section className="panel"><h3>{title}</h3>{empty&&<p className="subtle">Sem registros nos últimos seis meses.</p>}<div className="barChart" role="img" aria-label={`${title}: ${months.map(m=>`${m.label} ${currency?brl(m[field]):m[field]}`).join(', ')}`}>{months.map(m=><div className="barColumn" key={m.key}><span className="barValue">{currency?brl(m[field]):m[field]}</span><div className="barTrack"><div className="bar" style={{height:`${m[field]/max*100}%`}}/></div><small>{m.label}</small></div>)}</div></section>
}
function ProfileFields({specialties,profile,ids=[],organization}:{specialties:Specialty[];profile?:Profile;ids?:string[];organization?:Organization|null}){
 const [kind,setKind]=useState<Exclude<ProfileType,null>>(profile?.profile_type||'freelancer');const [marketRole,setMarketRole]=useState(organization?.market_role==='buyer'?'buyer':'provider');const locked=!!profile?.onboarding_completed&&!!profile?.profile_type;
 return <><label>Como você usa o EventCore?<select className="select" name="profile_type" value={kind} onChange={e=>{const k=e.target.value as Exclude<ProfileType,null>;setKind(k)}}>{Object.entries(profileTypeLabel).map(([k,v])=><option key={k} value={k} disabled={locked&&k!==kind}>{v}</option>)}</select></label><label>{kind==='freelancer'?'Nome completo':'Nome do responsável'}<input className="input" name="full_name" defaultValue={profile?.full_name||''} autoComplete="name" required minLength={2} maxLength={150}/></label><label>Telefone<input className="input" name="phone" defaultValue={profile?.phone||''} type="tel" autoComplete="tel" maxLength={30}/></label>
 {kind!=='freelancer'&&<><label>{kind==='team_lead'?'Nome da equipe':kind==='agency'?'Nome da agência':'Nome da empresa'}<input className="input" name="organization_name" defaultValue={organization?.display_name||''} required minLength={2} maxLength={150}/></label><label>Área de atuação<select className="select" name="business_type" defaultValue={organization?.business_type||''} required><option value="">Selecione</option>{businessTypes.map(b=><option key={b}>{b}</option>)}</select></label></>}
 <fieldset className="specialtyField"><legend>{kind==='freelancer'?'Suas especialidades':'Especialidades da operação'}</legend><div className="specialtyGrid">{specialties.map(s=><label className="checkLabel" key={s.id}><input type="checkbox" name="specialty_ids" value={s.id} defaultChecked={ids.includes(s.id)}/>{s.name}</label>)}</div>{!specialties.length&&<small className="subtle">Carregando especialidades…</small>}</fieldset>
 <DocumentField required={!profile?.onboarding_completed}/>
 {kind!=='freelancer'&&<>{organization?.market_role&&organization.market_role!=='unclassified'&&<input type='hidden' name='market_role' value={organization.market_role}/>}<label>Atividade comercial<select className="select" name="market_role" disabled={!!organization?.market_role&&organization.market_role!=='unclassified'} value={marketRole} onChange={e=>setMarketRole(e.target.value)}><option value="provider">Fornecedor de equipes e serviços</option><option value="buyer">Contratante de empresas</option></select></label>{marketRole==='buyer'&&<label>Perfil contratante<select className="select" name="buyer_subtype" defaultValue={organization?.buyer_subtype||'agency'}><option value="agency">Agência</option><option value="scenography">Cenografia</option></select></label>}</>}

 {kind==='freelancer'&&<><label>Cidade<input className="input" name="city" autoComplete="address-level2"/></label><label>Disponibilidade<select className="select" name="professional_status" defaultValue={profile?.professional_status||'available'}><option value="available">Disponível</option><option value="busy">Em trabalho</option><option value="unavailable">Indisponível</option></select></label><label>Apresentação profissional<textarea className="textarea" name="bio" defaultValue={profile?.bio||''} maxLength={1000}/></label></>}
 </>;
}
function ProfileForm({profile,specialties,ids,organization,busy,submit}:{profile:Profile;specialties:Specialty[];ids:string[];organization:Organization|null;busy:boolean;submit:(p:ProfilePayload)=>Promise<void>}){
 return <form className="form" onSubmit={e=>{e.preventDefault();submit(profilePayload(e.currentTarget))}}><ProfileFields profile={profile} specialties={specialties} ids={ids} organization={organization}/><p className="subtle">Sua identificação fica privada. Nome, especialidades e apresentação compõem seu perfil profissional.</p><button className="btn" disabled={busy||!specialties.length}>{busy?'Salvando…':'Salvar meu perfil'}</button></form>
}
