export type ProfileType = 'freelancer' | 'team_lead' | 'company' | 'agency' | null;
export type AppTab = 'home' | 'dashboard' | 'clients' | 'team' | 'events' | 'schedule' | 'finance' | 'reputation' | 'profile';
export type CapabilityProfile = {role:string; profile_type:ProfileType; active:boolean; onboarding_completed:boolean};
export const profileTypeLabel: Record<Exclude<ProfileType,null>,string> = {freelancer:'Freelancer',team_lead:'Responsável por equipe',company:'Empresa',agency:'Agência'};
export function isStaff(p:CapabilityProfile){return p.active && ['admin','coordinator'].includes(p.role)}
export function capabilitiesFor(p:CapabilityProfile){
  const staff=isStaff(p);
  const business=p.active && p.onboarding_completed && ['team_lead','company','agency'].includes(p.profile_type ?? '');
  const professional=p.active && p.onboarding_completed && p.profile_type==='freelancer' && !staff;
  return {staff,business,professional,viewClients:staff||business,manageTeam:staff||business,manageEvents:staff||business,manageCalendar:staff,viewOpportunities:p.active&&p.onboarding_completed,applyForJobs:professional,managePayments:staff||business};
}
const labels:Record<AppTab,string>={home:'Início',dashboard:'Dashboard',clients:'Clientes',team:'Equipe',events:'Eventos',schedule:'Minha escala',finance:'Financeiro',reputation:'Reputação',profile:'Meu perfil'};
export function navigationFor(p:CapabilityProfile){
  const c=capabilitiesFor(p);
  const tabs:AppTab[]=['home','dashboard'];
  if(c.viewClients)tabs.push('clients');
  if(c.manageTeam)tabs.push('team');
  tabs.push('events');
  if(c.professional)tabs.push('schedule');
  tabs.push('finance');
  if(c.professional)tabs.push('reputation');
  tabs.push('profile');
  return tabs.map(id=>({id,label:labels[id]}));
}
export function canOpenTab(p:CapabilityProfile,tab:AppTab){return navigationFor(p).some(x=>x.id===tab)}
export function profileOrganizationFor<T extends {owner_profile_id:string;active:boolean;created_at?:string}>(organizations:T[],profileId:string){
  return organizations.filter(o=>o.active&&o.owner_profile_id===profileId).sort((a,b)=>(a.created_at||'').localeCompare(b.created_at||''))[0]||null;
}
