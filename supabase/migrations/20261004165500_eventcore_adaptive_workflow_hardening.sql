-- Repair the interrupted adaptive update without changing existing data/projects.
-- Authorization comes from active database profiles, never user-controlled metadata.
create or replace function private.eventcore_is_staff() returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles where id=(select auth.uid()) and active and role in ('admin','coordinator'));
$$;
create or replace function private.eventcore_is_business() returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles where id=(select auth.uid()) and active and onboarding_completed and profile_type in ('team_lead','company','agency'));
$$;
create or replace function private.eventcore_org_member(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.eventcore_is_staff() or exists(
    select 1 from public.organizations o join public.profiles p on p.id=(select auth.uid())
    where o.id=p_org and o.active and p.active and (o.owner_profile_id=p.id or exists(
      select 1 from public.organization_members m where m.organization_id=o.id and m.profile_id=p.id and m.active)));
$$;
create or replace function private.eventcore_org_manager(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.eventcore_is_staff() or (private.eventcore_is_business() and exists(
    select 1 from public.organizations o where o.id=p_org and o.active and (o.owner_profile_id=(select auth.uid()) or exists(
      select 1 from public.organization_members m where m.organization_id=o.id and m.profile_id=(select auth.uid()) and m.active and m.member_role='manager'))));
$$;
create or replace function private.eventcore_org_owner(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.eventcore_is_staff() or (private.eventcore_is_business() and exists(
    select 1 from public.organizations where id=p_org and active and owner_profile_id=(select auth.uid())));
$$;
create or replace function private.eventcore_can_manage_event(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.eventcore_is_staff() or exists(select 1 from public.events e where e.id=p_event and e.organization_id is not null and private.eventcore_org_manager(e.organization_id));
$$;
create or replace function private.eventcore_manages_service(p_service uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.event_services where id=p_service and private.eventcore_can_manage_event(event_id));
$$;
create or replace function private.eventcore_owns_freelancer(p_freelancer uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.freelancers f join public.profiles p on p.id=f.profile_id where f.id=p_freelancer and p.id=(select auth.uid()) and p.active);
$$;
create or replace function private.eventcore_owns_assignment(p_assignment uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.assignments where id=p_assignment and private.eventcore_owns_freelancer(freelancer_id));
$$;
create or replace function private.eventcore_manages_assignment(p_assignment uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.assignments where id=p_assignment and private.eventcore_manages_service(event_service_id));
$$;
create or replace function private.eventcore_assigned_service(p_service uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.assignments where event_service_id=p_service and private.eventcore_owns_freelancer(freelancer_id));
$$;
create or replace function private.eventcore_assigned_event(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id where s.event_id=p_event and private.eventcore_owns_freelancer(a.freelancer_id));
$$;
create or replace function private.eventcore_valid_event_tenant(p_org uuid,p_client uuid,p_creator uuid,p_coordinator uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select private.eventcore_is_staff() or (p_creator=(select auth.uid()) and p_coordinator=(select auth.uid()) and private.eventcore_org_manager(p_org) and exists(select 1 from public.clients where id=p_client and organization_id=p_org and active));
$$;

-- Remove cyclic/raw marketplace policies. Boolean definer helpers inspect only ownership.
do $$ declare p record; begin
  for p in select tablename,policyname from pg_policies where schemaname='public' and tablename in
    ('clients','events','event_services','assignments','attendance','payments','freelancers','job_applications','ratings','organizations','organization_members','organization_specialties','profile_specialties','profile_private_identity')
  loop execute format('drop policy %I on public.%I',p.policyname,p.tablename); end loop;
end $$;
create policy clients_read on public.clients for select to authenticated using(private.eventcore_org_manager(organization_id));
create policy clients_write on public.clients for all to authenticated using(private.eventcore_org_manager(organization_id)) with check(private.eventcore_org_manager(organization_id));
create policy events_read on public.events for select to authenticated using(private.eventcore_can_manage_event(id) or private.eventcore_assigned_event(id));
create policy events_insert on public.events for insert to authenticated with check(private.eventcore_valid_event_tenant(organization_id,client_id,created_by_profile_id,coordinator_id));
create policy events_update on public.events for update to authenticated using(private.eventcore_can_manage_event(id)) with check(private.eventcore_can_manage_event(id));
create policy events_delete_staff on public.events for delete to authenticated using(private.eventcore_is_staff());
create policy services_read on public.event_services for select to authenticated using(private.eventcore_can_manage_event(event_id) or private.eventcore_assigned_service(id));
create policy services_write on public.event_services for all to authenticated using(private.eventcore_can_manage_event(event_id)) with check(private.eventcore_can_manage_event(event_id));
create policy freelancers_read on public.freelancers for select to authenticated using(private.eventcore_is_staff() or private.eventcore_owns_freelancer(id));
create policy freelancers_staff_write on public.freelancers for all to authenticated using(private.eventcore_is_staff()) with check(private.eventcore_is_staff());
create policy assignments_read on public.assignments for select to authenticated using(private.eventcore_manages_service(event_service_id) or private.eventcore_owns_freelancer(freelancer_id));
create policy assignments_staff_write on public.assignments for all to authenticated using(private.eventcore_is_staff()) with check(private.eventcore_is_staff());
create policy assignments_own_response on public.assignments for update to authenticated using(private.eventcore_owns_freelancer(freelancer_id)) with check(private.eventcore_owns_freelancer(freelancer_id));
create policy attendance_read on public.attendance for select to authenticated using(private.eventcore_manages_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy attendance_staff_write on public.attendance for all to authenticated using(private.eventcore_is_staff()) with check(private.eventcore_is_staff());
create policy payments_read on public.payments for select to authenticated using(private.eventcore_manages_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy payments_staff_write on public.payments for all to authenticated using(private.eventcore_is_staff()) with check(private.eventcore_is_staff());
create policy applications_read on public.job_applications for select to authenticated using(private.eventcore_manages_service(event_service_id) or private.eventcore_owns_freelancer(freelancer_id));
create policy applications_own_withdraw on public.job_applications for update to authenticated using(private.eventcore_owns_freelancer(freelancer_id)) with check(private.eventcore_owns_freelancer(freelancer_id));
create policy ratings_read on public.ratings for select to authenticated using(private.eventcore_owns_freelancer(freelancer_id) or private.eventcore_can_manage_event(event_id));
create policy org_read on public.organizations for select to authenticated using(private.eventcore_org_member(id));
create policy org_staff_write on public.organizations for all to authenticated using(private.eventcore_is_staff()) with check(private.eventcore_is_staff());
create policy members_read on public.organization_members for select to authenticated using(private.eventcore_org_member(organization_id));
create policy members_owner_write on public.organization_members for all to authenticated using(private.eventcore_org_owner(organization_id)) with check(private.eventcore_org_owner(organization_id) and member_role<>'owner');
create policy org_specialties_read on public.organization_specialties for select to authenticated using(private.eventcore_org_member(organization_id));
create policy profile_specialties_read on public.profile_specialties for select to authenticated using(profile_id=(select auth.uid()) or private.eventcore_is_staff());
create policy identity_read on public.profile_private_identity for select to authenticated using(profile_id=(select auth.uid()) or private.eventcore_is_staff());
revoke update(profile_type,onboarding_completed) on public.profiles from authenticated;
revoke insert,update,delete on public.profile_private_identity,public.profile_specialties,public.organization_specialties from authenticated;

-- Tenant linkage and immutable identity fields stay protected on direct REST writes.
create or replace function private.eventcore_guard_tenant() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if private.eventcore_is_staff() then return new; end if;
  if tg_table_name='clients' then
    if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then raise exception 'tenant_is_immutable'; end if;
  end if;
  if tg_table_name='events' then
    if tg_op='UPDATE' and (new.organization_id is distinct from old.organization_id or new.created_by_profile_id is distinct from old.created_by_profile_id or new.coordinator_id is distinct from old.coordinator_id or new.client_id is distinct from old.client_id or new.proposal_id is distinct from old.proposal_id) then raise exception 'event_ownership_is_immutable'; end if;
    if tg_op='INSERT' and (new.proposal_id is not null or not private.eventcore_valid_event_tenant(new.organization_id,new.client_id,new.created_by_profile_id,new.coordinator_id)) then raise exception 'invalid_event_tenant'; end if;
    if new.status='completed' and (new.end_at is null or new.end_at>now()) then raise exception 'event_has_not_ended'; end if;
  end if;
  if tg_table_name='event_services' then
    if tg_op='UPDATE' and new.event_id is distinct from old.event_id then raise exception 'service_event_is_immutable'; end if;
    if new.quantity_needed<(select count(*) from public.assignments where event_service_id=old.id and status in ('invited','confirmed','checked_in','checked_out')) then raise exception 'capacity_below_assignments'; end if;
  end if;
  return new;
end $$;
create trigger trg_adaptive_client_tenant before update on public.clients for each row execute function private.eventcore_guard_tenant();
create trigger trg_adaptive_event_tenant before insert or update on public.events for each row execute function private.eventcore_guard_tenant();
create trigger trg_adaptive_service_tenant before update on public.event_services for each row execute function private.eventcore_guard_tenant();

create or replace function private.eventcore_document_valid(p_type text,p_value text) returns boolean
language plpgsql immutable set search_path='' as $$
declare i int; j int; n int; total int; r int; digit int; base text; weights int[];
begin
 if p_type='cpf' then
   if p_value !~ '^[0-9]{11}$' or p_value ~ '^([0-9])\1{10}$' then return false; end if;
   for j in 9..10 loop total:=0; for i in 1..j loop total:=total+substring(p_value,i,1)::int*(j+2-i); end loop; digit:=(total*10)%11; if digit=10 then digit:=0; end if; if digit<>substring(p_value,j+1,1)::int then return false; end if; end loop;
   return true;
 elsif p_type='cnpj' then
   if p_value !~ '^[A-Z0-9]{12}[0-9]{2}$' or p_value ~ '^([0-9])\1{13}$' then return false; end if;
   for j in 12..13 loop weights:=case when j=12 then array[5,4,3,2,9,8,7,6,5,4,3,2] else array[6,5,4,3,2,9,8,7,6,5,4,3,2] end; total:=0;
     for i in 1..j loop total:=total+(ascii(substring(p_value,i,1))-48)*weights[i]; end loop; r:=total%11; digit:=case when r<2 then 0 else 11-r end;
     if digit<>substring(p_value,j+1,1)::int then return false; end if;
   end loop; return true;
 end if; return false;
end $$;
alter table public.profile_private_identity drop constraint profile_private_identity_document_format;
alter table public.profile_private_identity add constraint profile_private_identity_document_format check((document_type='cpf' and document_number ~ '^[0-9]{11}$') or (document_type='cnpj' and document_number ~ '^[A-Z0-9]{12}[0-9]{2}$'));

create or replace function public.complete_profile(p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=(select auth.uid()); p public.profiles; kind text:=p_payload->>'profile_type'; doc_type text:=p_payload->>'document_type'; doc text:=upper(regexp_replace(p_payload->>'document_number','[./\s-]','','g')); ids uuid[]; org uuid; org_kind text;
begin
 select * into p from public.profiles where id=uid and active for update;
 if not found then raise exception 'unauthorized'; end if;
 if kind not in ('freelancer','team_lead','company','agency') or kind is null then raise exception 'invalid_profile_type'; end if;
 if p.onboarding_completed and p.profile_type is not null and p.profile_type<>kind then raise exception 'profile_type_locked'; end if;
 if length(trim(coalesce(p_payload->>'full_name','')))<2 or length(p_payload->>'full_name')>150 then raise exception 'invalid_full_name'; end if;
 if coalesce(doc,'')='' then select document_number,document_type into doc,doc_type from public.profile_private_identity where profile_id=uid; end if;
 if doc is null or doc_type is null or not private.eventcore_document_valid(doc_type,doc) or (kind='freelancer' and doc_type<>'cpf') or (kind in ('company','agency') and doc_type<>'cnpj') then raise exception 'invalid_private_document'; end if;
 select coalesce(array_agg(distinct value::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(coalesce(p_payload->'specialty_ids','[]'));
 if cardinality(ids)=0 or exists(select 1 from unnest(ids) x where not exists(select 1 from public.specialties where id=x and active)) then raise exception 'select_active_specialties'; end if;
 if kind<>'freelancer' and length(trim(coalesce(p_payload->>'organization_name','')))<2 then raise exception 'organization_name_required'; end if;
 insert into public.profile_private_identity(profile_id,document_type,document_number) values(uid,doc_type,doc) on conflict(profile_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,updated_at=now();
 update public.profiles set full_name=trim(p_payload->>'full_name'),phone=nullif(trim(p_payload->>'phone'),''),profile_type=kind,onboarding_completed=true,bio=left(p_payload->>'bio',1000),professional_status=case when p_payload->>'professional_status' in ('available','busy','unavailable') then p_payload->>'professional_status' else 'available' end,updated_at=now() where id=uid;
 delete from public.profile_specialties where profile_id=uid;
 insert into public.profile_specialties(profile_id,specialty_id) select uid,unnest(ids);
 if kind='freelancer' then
   insert into public.freelancers(profile_id,full_name,phone,city,active,rating,completed_jobs) values(uid,trim(p_payload->>'full_name'),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'city'),''),true,0,0)
   on conflict(profile_id) do update set full_name=excluded.full_name,phone=excluded.phone,city=coalesce(excluded.city,public.freelancers.city),updated_at=now();
 else
   org_kind:=case when kind='team_lead' then 'team' else kind end;
   select id into org from public.organizations where owner_profile_id=uid and active order by created_at limit 1 for update;
   if org is null then insert into public.organizations(owner_profile_id,organization_type,display_name,business_type) values(uid,org_kind,trim(p_payload->>'organization_name'),nullif(p_payload->>'business_type','')) returning id into org;
   else update public.organizations set display_name=trim(p_payload->>'organization_name'),business_type=nullif(p_payload->>'business_type',''),updated_at=now() where id=org; end if;
   insert into public.organization_members(organization_id,profile_id,member_role,active) values(org,uid,'owner',true) on conflict(organization_id,profile_id) do nothing;
   delete from public.organization_specialties where organization_id=org;
   insert into public.organization_specialties(organization_id,specialty_id) select org,unnest(ids);
 end if;
 return jsonb_build_object('completed',true,'organization_id',org);
exception when unique_violation then raise exception 'private_document_conflict';
end $$;

create or replace function public.get_event_opportunities() returns table(service_id uuid,event_id uuid,event_name text,start_at timestamptz,end_at timestamptz,venue text,function_name text,specialty_id uuid,vacancies integer,amount numeric,contractor_name text,requirements text,event_status text,compatible boolean)
language sql stable security definer set search_path='' as $$
 select s.id,e.id,e.name,e.start_at,e.end_at,e.venue,s.label,s.specialty_id,
 greatest(0,s.quantity_needed-(select count(*)::int from public.assignments a where a.event_service_id=s.id and a.status in ('invited','confirmed','checked_in','checked_out'))),s.freelancer_unit_cost,coalesce(o.display_name,p.full_name,'EventCore'),s.requirements,e.status,
 (s.specialty_id is null or exists(select 1 from public.profile_specialties ps where ps.profile_id=(select auth.uid()) and ps.specialty_id=s.specialty_id))
 from public.event_services s join public.events e on e.id=s.event_id left join public.organizations o on o.id=e.organization_id left join public.profiles p on p.id=coalesce(e.created_by_profile_id,e.coordinator_id)
 where s.visibility='open' and s.application_enabled and e.status in ('planning','staffing','confirmed','in_progress') and coalesce(e.end_at,e.start_at)>now()
 and exists(select 1 from public.profiles where id=(select auth.uid()) and active and onboarding_completed)
 and (e.organization_id is null or o.active) order by e.start_at,s.label;
$$;
create or replace function public.apply_for_opportunity(p_service_id uuid,p_message text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare f uuid; app uuid; s public.event_services; ev public.events; existing public.job_applications;
begin
 select fr.id into f from public.freelancers fr join public.profiles p on p.id=fr.profile_id where p.id=(select auth.uid()) and fr.active and p.active and p.onboarding_completed and p.profile_type='freelancer';
 if f is null then raise exception 'complete_freelancer_profile'; end if;
 select * into s from public.event_services where id=p_service_id for update; select * into ev from public.events where id=s.event_id for update;
 if s.id is null or s.visibility<>'open' or not s.application_enabled or ev.status not in ('planning','staffing','confirmed','in_progress') or coalesce(ev.end_at,ev.start_at)<=now() then raise exception 'opportunity_unavailable'; end if;
 if s.specialty_id is not null and not exists(select 1 from public.profile_specialties where profile_id=(select auth.uid()) and specialty_id=s.specialty_id) then raise exception 'specialty_not_compatible'; end if;
 if private.eventcore_can_manage_event(ev.id) then raise exception 'cannot_apply_to_own_event'; end if;
 select * into existing from public.job_applications where event_service_id=s.id and freelancer_id=f for update;
 if existing.id is not null and existing.status<>'withdrawn' then return existing.id; end if;
 if (select count(*) from public.assignments where event_service_id=s.id and status in ('invited','confirmed','checked_in','checked_out'))>=s.quantity_needed then raise exception 'vacancies_filled'; end if;
 if existing.id is not null then update public.job_applications set status='interested',message=left(p_message,1000),updated_at=now() where id=existing.id returning id into app;
 else insert into public.job_applications(event_service_id,freelancer_id,status,message) values(s.id,f,'interested',left(p_message,1000)) returning id into app; end if;
 return app;
end $$;

-- Triggers permit only valid identities/transitions, including direct legacy staff writes.
create or replace function private.guard_job_application_update() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.id is distinct from old.id or new.event_service_id is distinct from old.event_service_id or new.freelancer_id is distinct from old.freelancer_id or new.created_at is distinct from old.created_at then raise exception 'application_identity_is_immutable'; end if;
 if new.status is distinct from old.status then
   if new.status='accepted' then
     if not private.eventcore_manages_service(old.event_service_id) or not exists(select 1 from public.assignments where application_id=old.id and freelancer_id=old.freelancer_id and event_service_id=old.event_service_id and status in ('invited','confirmed','checked_in','checked_out')) then raise exception 'accepted_application_requires_assignment'; end if;
   elsif private.eventcore_manages_service(old.event_service_id) then
     if old.status='accepted' or new.status not in ('shortlisted','rejected') then raise exception 'invalid_application_transition'; end if;
   elsif not private.eventcore_owns_freelancer(old.freelancer_id) or not ((old.status in ('interested','shortlisted') and new.status='withdrawn') or (old.status='withdrawn' and new.status='interested')) then raise exception 'freelancer_may_only_withdraw_application'; end if;
 end if;
 new.updated_at:=now(); return new;
end $$;
create or replace function private.guard_freelancer_assignment_update() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.event_services; f public.freelancers; n int;
begin
 select * into s from public.event_services where id=new.event_service_id for update;
 select * into f from public.freelancers where id=new.freelancer_id;
 if tg_op='INSERT' then
   if not private.eventcore_can_manage_event(s.event_id) then raise exception 'forbidden'; end if;
   if f.profile_id=(select auth.uid()) then raise exception 'self_hiring_not_allowed'; end if;
   if new.status not in ('invited','confirmed','reserve') then raise exception 'invalid_initial_assignment_status'; end if;
   new.contractor_profile_id:=(select auth.uid()); new.hired_at:=now();
 else
   if new.id is distinct from old.id or new.freelancer_id is distinct from old.freelancer_id or new.event_service_id is distinct from old.event_service_id or new.contractor_profile_id is distinct from old.contractor_profile_id or new.application_id is distinct from old.application_id or new.created_at is distinct from old.created_at or new.hired_at is distinct from old.hired_at then raise exception 'assignment_identity_is_immutable'; end if;
   if not private.eventcore_manages_service(s.id) and (not private.eventcore_owns_freelancer(f.id) or new.agreed_amount is distinct from old.agreed_amount or new.invited_at is distinct from old.invited_at or new.confirmed_at is distinct from old.confirmed_at) then raise exception 'freelancer_may_only_change_status'; end if;
   if new.status is distinct from old.status and not private.eventcore_is_staff() and not (
      (old.status in ('invited','reserve') and new.status in ('confirmed','cancelled')) or (old.status='confirmed' and new.status in ('checked_in','cancelled')) or (old.status='checked_in' and new.status='checked_out')) then raise exception 'invalid_assignment_status_transition'; end if;
   if new.status='checked_in' and old.status<>'checked_in' and not private.eventcore_is_staff() and not exists(select 1 from public.attendance where assignment_id=old.id and check_in_at is not null) then raise exception 'attendance_required'; end if;
   if new.status='checked_out' and old.status<>'checked_out' and not private.eventcore_is_staff() and not exists(select 1 from public.attendance where assignment_id=old.id and check_out_at is not null) then raise exception 'attendance_required'; end if;
 end if;
 if new.application_id is not null and not exists(select 1 from public.job_applications where id=new.application_id and event_service_id=s.id and freelancer_id=f.id) then raise exception 'invalid_application_link'; end if;
 if new.status in ('invited','confirmed','checked_in','checked_out') and (tg_op='INSERT' or old.status not in ('invited','confirmed','checked_in','checked_out')) then
   select count(*) into n from public.assignments where event_service_id=s.id and id<>new.id and status in ('invited','confirmed','checked_in','checked_out');
   if n>=s.quantity_needed then raise exception 'vacancies_filled'; end if;
 end if;
 if new.status='confirmed' then new.confirmed_at:=coalesce(new.confirmed_at,now()); end if;
 new.updated_at:=now(); return new;
end $$;
drop trigger if exists guard_freelancer_assignment_update on public.assignments;
drop trigger if exists trg_guard_freelancer_assignment_update on public.assignments;
create trigger trg_guard_freelancer_assignment_update before insert or update on public.assignments for each row execute function private.guard_freelancer_assignment_update();

create or replace function public.create_event_assignment(p_service_id uuid,p_freelancer_id uuid,p_status text default 'invited',p_amount numeric default null,p_application_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.event_services; ev public.events; a uuid; amount numeric; app public.job_applications;
begin
 select * into s from public.event_services where id=p_service_id for update; select * into ev from public.events where id=s.event_id for update;
 if s.id is null or not private.eventcore_can_manage_event(s.event_id) then raise exception 'forbidden'; end if;
 if ev.status in ('completed','cancelled') then raise exception 'event_closed'; end if;
 if not exists(select 1 from public.freelancers f where f.id=p_freelancer_id and f.active and (f.profile_id is null or exists(select 1 from public.profiles where id=f.profile_id and active and (profile_type='freelancer' or (profile_type is null and private.eventcore_is_staff()))))) then raise exception 'professional_unavailable'; end if;
 if p_status not in ('invited','confirmed','reserve') or p_status is null or p_amount<0 then raise exception 'invalid_assignment'; end if;
 amount:=coalesce(p_amount,s.freelancer_unit_cost);
 if p_application_id is not null then
   select * into app from public.job_applications where id=p_application_id for update;
   if app.id is null or app.event_service_id<>s.id or app.freelancer_id<>p_freelancer_id or app.status not in ('interested','shortlisted') or p_status='reserve' then raise exception 'application_unavailable'; end if;
 end if;
 insert into public.assignments(event_service_id,freelancer_id,status,agreed_amount,application_id) values(s.id,p_freelancer_id,p_status,amount,p_application_id) returning id into a;
 if amount is not null then insert into public.payments(assignment_id,amount,status) values(a,amount,'pending'); end if;
 if p_application_id is not null then update public.job_applications set status='accepted',updated_at=now() where id=p_application_id; end if;
 update public.events set calendar_sync_status=case when google_event_id is null then 'pending' else 'out_of_sync' end,updated_at=now() where id=ev.id;
 return a;
end $$;
create or replace function public.hire_application(p_application_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare app public.job_applications; a uuid; service uuid;
begin
 select event_service_id into service from public.job_applications where id=p_application_id;
 perform 1 from public.event_services where id=service for update;
 select * into app from public.job_applications where id=p_application_id for update;
 if not found or not private.eventcore_manages_service(app.event_service_id) then raise exception 'forbidden'; end if;
 if app.status='accepted' then select id into a from public.assignments where application_id=app.id; return a; end if;
 if app.status not in ('interested','shortlisted') then raise exception 'application_unavailable'; end if;
 a:=public.create_event_assignment(app.event_service_id,app.freelancer_id,'invited',null,app.id);
 return a;
end $$;

create or replace function public.record_assignment_attendance(p_assignment_id uuid,p_kind text,p_lat numeric,p_lng numeric) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; ev public.events; att public.attendance; manager boolean;
begin
 select * into a from public.assignments where id=p_assignment_id for update;
 manager:=private.eventcore_manages_assignment(a.id);
 if a.id is null or not (manager or private.eventcore_owns_assignment(a.id)) then raise exception 'forbidden'; end if;
 select e.* into ev from public.events e join public.event_services s on s.event_id=e.id where s.id=a.event_service_id;
 if ev.status='cancelled' or now()<ev.start_at-interval '24 hours' then raise exception 'attendance_outside_event_window'; end if;
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'invalid_coordinates'; end if;
 select * into att from public.attendance where assignment_id=a.id for update;
 if p_kind='in' and a.status='confirmed' and att.check_in_at is null then
   insert into public.attendance(assignment_id,check_in_at,check_in_lat,check_in_lng,validated_by,validated_at) values(a.id,now(),p_lat,p_lng,case when manager then auth.uid() end,case when manager then now() end)
   on conflict(assignment_id) do update set check_in_at=excluded.check_in_at,check_in_lat=excluded.check_in_lat,check_in_lng=excluded.check_in_lng,validated_by=excluded.validated_by,validated_at=excluded.validated_at;
   update public.assignments set status='checked_in' where id=a.id;
 elsif p_kind='out' and a.status='checked_in' and att.check_in_at is not null and att.check_out_at is null then
   update public.attendance set check_out_at=now(),check_out_lat=p_lat,check_out_lng=p_lng,validated_by=case when manager then auth.uid() else validated_by end,validated_at=case when manager then now() else validated_at end where id=att.id;
   update public.assignments set status='checked_out' where id=a.id;
 else raise exception 'invalid_attendance_transition'; end if;
end $$;
create or replace function public.validate_assignment_attendance(p_assignment_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.eventcore_manages_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
 update public.attendance set validated_by=(select auth.uid()),validated_at=now() where assignment_id=p_assignment_id and check_in_at is not null and check_out_at is not null;
 if not found then raise exception 'completed_attendance_required'; end if;
end $$;
create or replace function public.mark_assignment_paid(p_assignment_id uuid,p_method text) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; amount numeric;
begin
 select * into a from public.assignments where id=p_assignment_id for update;
 if not private.eventcore_manages_assignment(a.id) then raise exception 'forbidden'; end if;
 if a.status in ('cancelled','reserve','no_show') or p_method is null or p_method not in ('pix','transfer','cash','other') then raise exception 'invalid_payment'; end if;
 select p.amount into amount from public.payments p where p.assignment_id=a.id;
 amount:=coalesce(amount,a.agreed_amount);
 if amount is null or amount<=0 then raise exception 'payment_amount_required'; end if;
 insert into public.payments(assignment_id,amount,status,method,paid_at) values(a.id,amount,'paid',p_method,now()) on conflict(assignment_id) do update set status='paid',method=excluded.method,paid_at=coalesce(public.payments.paid_at,excluded.paid_at),updated_at=now();
end $$;
create or replace function public.submit_assignment_rating(p_assignment_id uuid,p_rating integer,p_comment text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assignments; ev public.events; f public.freelancers; result uuid;
begin
 select * into a from public.assignments where id=p_assignment_id for update;
 select e.* into ev from public.events e join public.event_services s on s.event_id=e.id where s.id=a.event_service_id for update of e;
 select * into f from public.freelancers where id=a.freelancer_id;
 if a.id is null or not private.eventcore_can_manage_event(ev.id) or (a.contractor_profile_id is not null and a.contractor_profile_id<>(select auth.uid()) and not private.eventcore_is_staff()) then raise exception 'actual_contractor_required'; end if;
 if f.profile_id=(select auth.uid()) then raise exception 'self_review_not_allowed'; end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>1000 then raise exception 'invalid_rating'; end if;
 if a.status<>'checked_out' or ev.status<>'completed' or coalesce(ev.end_at,ev.start_at)>now() or not exists(select 1 from public.attendance where assignment_id=a.id and check_in_at is not null and check_out_at is not null and validated_by is not null) then raise exception 'completed_validated_event_required'; end if;
 insert into public.ratings(assignment_id,event_id,freelancer_id,reviewer_profile_id,rating,comment) values(a.id,ev.id,f.id,auth.uid(),p_rating,nullif(trim(p_comment),'')) returning id into result;
 return result;
exception when unique_violation then raise exception 'assignment_already_rated';
end $$;

-- Authoritative reputation is calculated from actual ratings and completed events.
create or replace function public.get_professional_directory() returns table(freelancer_id uuid,profile_id uuid,full_name text,city text,rating numeric,completed_jobs integer,review_count bigint,specialties text[])
language sql stable security definer set search_path='' as $$
 select f.id,f.profile_id,f.full_name,f.city,coalesce((select round(avg(r.rating),2) from public.ratings r where r.freelancer_id=f.id),0),
 (select count(*)::int from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where a.freelancer_id=f.id and a.status='checked_out' and e.status='completed'),
 (select count(*) from public.ratings where freelancer_id=f.id),coalesce((select array_agg(s.name order by s.sort_order) from public.profile_specialties ps join public.specialties s on s.id=ps.specialty_id where ps.profile_id=f.profile_id and s.active),'{}'::text[])
 from public.freelancers f left join public.profiles p on p.id=f.profile_id where f.active and (f.profile_id is null or (p.active and (p.profile_type='freelancer' or private.eventcore_is_staff()))) and (private.eventcore_is_staff() or private.eventcore_is_business() or f.profile_id=(select auth.uid()));
$$;
create or replace function public.get_professional_reputation(p_freelancer_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not (private.eventcore_is_staff() or private.eventcore_is_business() or private.eventcore_owns_freelancer(p_freelancer_id)) then raise exception 'forbidden'; end if;
 select jsonb_build_object('name',f.full_name,'availability',p.professional_status,'bio',p.bio,'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'date',r.created_at,'event_name',e.name) order by r.created_at desc) from public.ratings r join public.events e on e.id=r.event_id where r.freelancer_id=f.id),'[]'::jsonb)) into result from public.freelancers f left join public.profiles p on p.id=f.profile_id where f.id=p_freelancer_id and f.active;
 return result;
end $$;
create or replace function public.get_organization_roster(p_organization_id uuid) returns table(profile_id uuid,full_name text,phone text,member_role text,active boolean)
language sql stable security definer set search_path='' as $$
 select p.id,p.full_name,p.phone,m.member_role,m.active from public.organization_members m join public.profiles p on p.id=m.profile_id where m.organization_id=p_organization_id and private.eventcore_org_manager(p_organization_id);
$$;
create or replace function public.set_organization_member(p_organization_id uuid,p_profile_id uuid,p_active boolean default true) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.eventcore_org_manager(p_organization_id) then raise exception 'forbidden'; end if;
 if exists(select 1 from public.organizations where id=p_organization_id and owner_profile_id=p_profile_id) then raise exception 'owner_membership_is_immutable'; end if;
 if exists(select 1 from public.organization_members where organization_id=p_organization_id and profile_id=p_profile_id and member_role='manager') and not private.eventcore_org_owner(p_organization_id) then raise exception 'owner_required_for_manager_changes'; end if;
 if not exists(select 1 from public.profiles where id=p_profile_id and active) then raise exception 'profile_unavailable'; end if;
 insert into public.organization_members(organization_id,profile_id,member_role,active) values(p_organization_id,p_profile_id,'member',p_active) on conflict(organization_id,profile_id) do update set active=excluded.active;
end $$;

-- Private helpers are never callable anonymously; mutations remain RPC-only.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'eventcore_%' or p.proname like 'guard_%' or p.proname='handle_new_user') loop
   execute format('revoke all on function %s from public,anon,authenticated',f.signature);
   if f.proname in ('eventcore_is_staff','eventcore_is_business','eventcore_profile_type','eventcore_org_member','eventcore_org_manager','eventcore_org_owner','eventcore_can_manage_event','eventcore_manages_service','eventcore_owns_freelancer','eventcore_owns_assignment','eventcore_manages_assignment','eventcore_assigned_service','eventcore_assigned_event','eventcore_valid_event_tenant') then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('complete_profile','get_event_opportunities','apply_for_opportunity','create_event_assignment','hire_application','record_assignment_attendance','validate_assignment_attendance','mark_assignment_paid','submit_assignment_rating','get_professional_directory','get_professional_reputation','get_organization_roster','set_organization_member') loop
   execute format('revoke all on function %s from public,anon',f.signature); execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
notify pgrst,'reload schema';

-- The public signup form needs only this non-personal specialty catalog.
grant select(id,slug,name,active,sort_order) on public.specialties to anon;
create policy specialties_public_catalog on public.specialties for select to anon using(active);
