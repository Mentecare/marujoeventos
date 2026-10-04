-- Final-review regressions: sanitized schedules, selection and coherent cancellation.
drop policy events_read on public.events;
create policy events_read on public.events for select to authenticated
using(private.eventcore_org_manager(organization_id));
drop policy services_read on public.event_services;
create policy services_read on public.event_services for select to authenticated
using(private.eventcore_can_manage_event(event_id));

create or replace function public.get_my_schedule() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare professional uuid; result jsonb;
begin
 select f.id into professional from public.freelancers f join public.profiles p on p.id=f.profile_id
 where p.id=(select auth.uid()) and p.active and p.onboarding_completed and p.profile_type='freelancer' and f.active;
 if professional is null then raise exception 'complete_freelancer_profile'; end if;
 select jsonb_build_object(
  'events',coalesce((select jsonb_agg(jsonb_build_object(
   'id',e.id,'name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,
   'status',e.status,'arrival_tolerance_minutes',e.arrival_tolerance_minutes) order by e.start_at)
   from public.events e where exists(select 1 from public.event_services s join public.assignments a on a.event_service_id=s.id where s.event_id=e.id and a.freelancer_id=professional)),'[]'::jsonb),
  'services',coalesce((select jsonb_agg(jsonb_build_object(
   'id',s.id,'event_id',s.event_id,'label',s.label,'service_type',s.service_type,'specialty_id',s.specialty_id,
   'quantity_needed',s.quantity_needed,'reserve_target',s.reserve_target,'briefing',s.briefing,
   'visibility',s.visibility,'application_enabled',s.application_enabled))
   from public.event_services s where exists(select 1 from public.assignments a where a.event_service_id=s.id and a.freelancer_id=professional)),'[]'::jsonb)
 ) into result;
 return result;
end $$;

create or replace function private.guard_job_application_update() returns trigger
language plpgsql security definer set search_path='' as $$
declare cancelled boolean;
begin
 if new.id is distinct from old.id or new.event_service_id is distinct from old.event_service_id or new.freelancer_id is distinct from old.freelancer_id or new.created_at is distinct from old.created_at then raise exception 'application_identity_is_immutable'; end if;
 if new.status is distinct from old.status then
  cancelled:=exists(select 1 from public.assignments where application_id=old.id and freelancer_id=old.freelancer_id and event_service_id=old.event_service_id and status='cancelled');
  if new.status='accepted' then
   if old.status not in ('interested','shortlisted') or not private.eventcore_manages_service(old.event_service_id) or not exists(select 1 from public.assignments where application_id=old.id and freelancer_id=old.freelancer_id and event_service_id=old.event_service_id and status in ('invited','confirmed','checked_in','checked_out')) then raise exception 'accepted_application_requires_assignment'; end if;
  elsif private.eventcore_manages_service(old.event_service_id) then
   if not ((old.status in ('interested','shortlisted') and new.status in ('shortlisted','rejected')) or (old.status='accepted' and cancelled and new.status='rejected')) then raise exception 'invalid_application_transition'; end if;
  elsif not private.eventcore_owns_freelancer(old.freelancer_id) or not (
   (old.status in ('interested','shortlisted') and new.status='withdrawn') or
   (old.status='withdrawn' and new.status='interested') or
   (old.status='accepted' and cancelled and new.status='withdrawn')) then raise exception 'freelancer_may_only_withdraw_application'; end if;
 end if;
 new.updated_at:=now(); return new;
end $$;

create or replace function private.guard_freelancer_assignment_update() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.event_services; f public.freelancers; n int; reopening boolean:=false; manager boolean;
begin
 select * into s from public.event_services where id=new.event_service_id for update;
 select * into f from public.freelancers where id=new.freelancer_id;
 manager:=private.eventcore_can_manage_event(s.event_id);
 if tg_op='INSERT' then
  if not manager then raise exception 'forbidden'; end if;
  if f.profile_id=(select auth.uid()) then raise exception 'self_hiring_not_allowed'; end if;
  if new.status not in ('invited','confirmed','reserve') then raise exception 'invalid_initial_assignment_status'; end if;
  new.contractor_profile_id:=(select auth.uid()); new.hired_at:=now();
 else
  reopening:=old.status='cancelled' and new.status in ('invited','confirmed','reserve') and manager;
  if new.id is distinct from old.id or new.freelancer_id is distinct from old.freelancer_id or new.event_service_id is distinct from old.event_service_id or new.created_at is distinct from old.created_at then raise exception 'assignment_identity_is_immutable'; end if;
  if not reopening and (new.contractor_profile_id is distinct from old.contractor_profile_id or new.application_id is distinct from old.application_id or new.hired_at is distinct from old.hired_at) then raise exception 'assignment_identity_is_immutable'; end if;
  if reopening then
   if f.profile_id=(select auth.uid()) then raise exception 'self_hiring_not_allowed'; end if;
   if (old.application_id is not null and new.application_id is distinct from old.application_id) then raise exception 'assignment_identity_is_immutable'; end if;
   if exists(select 1 from public.attendance where assignment_id=old.id and check_in_at is not null) or exists(select 1 from public.ratings where assignment_id=old.id) or exists(select 1 from public.payments where assignment_id=old.id and status='paid') then raise exception 'historical_assignment_cannot_reopen'; end if;
   new.contractor_profile_id:=(select auth.uid()); new.hired_at:=now();
  end if;
  if not manager and (not private.eventcore_owns_freelancer(f.id) or new.agreed_amount is distinct from old.agreed_amount or new.invited_at is distinct from old.invited_at or new.confirmed_at is distinct from old.confirmed_at) then raise exception 'freelancer_may_only_change_status'; end if;
  if new.status is distinct from old.status and not private.eventcore_is_staff() and not (reopening or
   (old.status in ('invited','reserve') and new.status in ('confirmed','cancelled')) or
   (old.status='confirmed' and new.status in ('checked_in','cancelled')) or
   (old.status='checked_in' and new.status='checked_out')) then raise exception 'invalid_assignment_status_transition'; end if;
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

create or replace function private.eventcore_assignment_cancelled() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='cancelled' and old.status<>'cancelled' then
  update public.job_applications set status=case when private.eventcore_owns_freelancer(new.freelancer_id) then 'withdrawn' else 'rejected' end,updated_at=now()
  where id=new.application_id and status='accepted';
  update public.payments set status='cancelled',updated_at=now()
  where assignment_id=new.id and status in ('pending','approved','held');
 end if;
 return new;
end $$;
create trigger trg_eventcore_assignment_cancelled after update on public.assignments
for each row execute function private.eventcore_assignment_cancelled();

create or replace function public.respond_to_assignment(p_assignment_id uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
declare a public.assignments; service uuid; manager boolean;
begin
 select event_service_id into service from public.assignments where id=p_assignment_id;
 perform 1 from public.event_services where id=service for update;
 select * into a from public.assignments where id=p_assignment_id for update;
 manager:=private.eventcore_manages_service(a.event_service_id);
 if a.id is null or not (manager or private.eventcore_owns_freelancer(a.freelancer_id)) then raise exception 'forbidden'; end if;
 if p_status is null or p_status not in ('confirmed','cancelled') or (manager and p_status<>'cancelled') then raise exception 'invalid_assignment_response'; end if;
 update public.assignments set status=p_status,updated_at=now() where id=a.id;
end $$;

create or replace function public.create_event_assignment(p_service_id uuid,p_freelancer_id uuid,p_status text default 'invited',p_amount numeric default null,p_application_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.event_services; ev public.events; a uuid; amount numeric; app public.job_applications; existing public.assignments;
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
 select * into existing from public.assignments where event_service_id=s.id and freelancer_id=p_freelancer_id for update;
 if existing.id is not null then
  if existing.status<>'cancelled' then raise exception 'professional_already_assigned'; end if;
  if existing.application_id is not null and p_application_id is distinct from existing.application_id then raise exception 'application_requires_reapply'; end if;
  update public.assignments set status=p_status,agreed_amount=amount,application_id=p_application_id,invited_at=now(),confirmed_at=null where id=existing.id returning id into a;
 else
  insert into public.assignments(event_service_id,freelancer_id,status,agreed_amount,application_id) values(s.id,p_freelancer_id,p_status,amount,p_application_id) returning id into a;
 end if;
 if amount is not null then
  insert into public.payments(assignment_id,amount,status) values(a,amount,'pending')
  on conflict(assignment_id) do update set amount=excluded.amount,status='pending',method=null,paid_at=null,updated_at=now() where public.payments.status='cancelled';
 end if;
 if p_application_id is not null then update public.job_applications set status='accepted',updated_at=now() where id=p_application_id; end if;
 update public.events set calendar_sync_status=case when google_event_id is null then 'pending' else 'out_of_sync' end,updated_at=now() where id=ev.id;
 return a;
end $$;

create or replace function public.hire_application(p_application_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare app public.job_applications; a uuid; service uuid;
begin
 select event_service_id into service from public.job_applications where id=p_application_id;
 perform 1 from public.event_services where id=service for update;
 select * into app from public.job_applications where id=p_application_id for update;
 if not found or not private.eventcore_manages_service(app.event_service_id) then raise exception 'forbidden'; end if;
 if app.status='accepted' then
  select id into a from public.assignments where application_id=app.id and status in ('invited','confirmed','checked_in','checked_out');
  if a is null then raise exception 'application_unavailable'; end if;
  return a;
 end if;
 if app.status not in ('interested','shortlisted') then raise exception 'application_unavailable'; end if;
 return public.create_event_assignment(app.event_service_id,app.freelancer_id,'invited',null,app.id);
end $$;

create or replace function public.review_application(p_application_id uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
declare app public.job_applications; service uuid;
begin
 select event_service_id into service from public.job_applications where id=p_application_id;
 perform 1 from public.event_services where id=service for update;
 select * into app from public.job_applications where id=p_application_id for update;
 if app.id is null or not private.eventcore_manages_service(app.event_service_id) then raise exception 'forbidden'; end if;
 if p_status is null or p_status not in ('shortlisted','rejected') or app.status not in ('interested','shortlisted') then raise exception 'invalid_application_transition'; end if;
 update public.job_applications set status=p_status,updated_at=now() where id=app.id;
end $$;

revoke all on function private.eventcore_assignment_cancelled() from public,anon,authenticated;
revoke all on function public.get_my_schedule(),public.respond_to_assignment(uuid,text),public.review_application(uuid,text) from public,anon;
grant execute on function public.get_my_schedule(),public.respond_to_assignment(uuid,text),public.review_application(uuid,text) to authenticated;
