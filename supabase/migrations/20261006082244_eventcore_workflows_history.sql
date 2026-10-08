-- Additive workflow evidence. No existing rows, totals, ratings or identities are rewritten.
-- Date-only business fields stay dates; server UTC midnight is not Brazilian midnight.
create function private.eventcore_business_date(p_instant timestamptz) returns date language sql immutable security invoker set search_path='' as $$
 select (p_instant at time zone 'America/Sao_Paulo')::date;
$$;
create function private.eventcore_business_today() returns date language sql stable security definer set search_path='' as $$
 select private.eventcore_business_date(now());
$$;
revoke all on function private.eventcore_business_date(timestamptz),private.eventcore_business_today() from public,anon,authenticated;

alter table public.events add column public_region text check(length(public_region)<=150);
alter table public.events add column origin text check(origin in ('platform','whatsapp','referral','other'));
alter table public.events add column commercial_contract_id uuid unique references public.commercial_contracts(id);
alter table public.event_services add column remuneration_basis text check(remuneration_basis in ('daily','service')),
 add column remuneration_rate numeric(12,2) check(remuneration_rate between 0 and 9999999999.99),
 add column planned_hours numeric(6,2) check(planned_hours between 0 and 9999.99),
 add column public_description text check(length(public_description)<=2000),
 add column benefits text check(length(benefits)<=2000),
 add column additions numeric(12,2) check(additions between 0 and 9999999999.99),
 add column deductions numeric(12,2) check(deductions between 0 and 9999999999.99);
-- Only the canonical creation RPC can open this permission inside its transaction.
create table private.eventcore_creation_sessions(event_id uuid primary key, transaction_id xid8 not null);
revoke all on private.eventcore_creation_sessions from public,anon,authenticated;
create function private.eventcore_workflow_service_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  if not exists(select 1 from private.eventcore_creation_sessions where event_id=new.event_id and transaction_id=pg_current_xact_id()) then raise exception 'functions_creation_only'; end if;
 elsif tg_op='DELETE' then raise exception 'function_conditions_creation_only';
 elsif (to_jsonb(new)-array['visibility','application_enabled','updated_at']) is distinct from (to_jsonb(old)-array['visibility','application_enabled','updated_at']) then raise exception 'function_conditions_creation_only';
 end if;
 if tg_op='UPDATE' and (new.visibility is distinct from old.visibility or new.application_enabled is distinct from old.application_enabled) and exists(select 1 from public.events where id=new.event_id and status in ('completed','cancelled')) then raise exception 'event_closed'; end if;
 return new;
end $$;
create trigger a_workflow_service_conditions before insert or update or delete on public.event_services for each row execute function private.eventcore_workflow_service_guard();
create function private.eventcore_workflow_event_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.commercial_contract_id is not null and not exists(select 1 from public.commercial_contracts c where c.id=new.commercial_contract_id and c.provider_organization_id=new.organization_id and c.client_id=new.client_id) then raise exception 'forbidden'; end if;
  new.origin:=coalesce(new.origin,'other');
  return new;
 end if;
 if new.origin is distinct from old.origin or new.commercial_contract_id is distinct from old.commercial_contract_id or new.public_region is distinct from old.public_region then raise exception 'work_origin_contract_immutable'; end if;
 if old.status='completed' and (new.status is distinct from old.status or new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.arrival_tolerance_minutes is distinct from old.arrival_tolerance_minutes) then raise exception 'completed_event_immutable'; end if;
 if (new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.arrival_tolerance_minutes is distinct from old.arrival_tolerance_minutes) and exists(select 1 from public.attendance t join public.assignments a on a.id=t.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=old.id and t.check_in_at is not null) then raise exception 'recorded_schedule_immutable'; end if;
 return new;
end $$;
create trigger a_workflow_event_conditions before insert or update on public.events for each row execute function private.eventcore_workflow_event_guard();
revoke delete on public.events from authenticated;

create table public.assignment_terms (
 id uuid primary key default gen_random_uuid(), assignment_id uuid not null references public.assignments(id) on delete restrict,
 revision integer not null check(revision>0), basis text not null check(basis in ('daily','service')),
 rate numeric(12,2) check(rate between 0 and 9999999999.99), contract_days integer check(contract_days>0),
 planned_hours numeric(6,2) check(planned_hours between 0 and 9999.99), benefits text check(length(benefits)<=2000),
 additions numeric(12,2) not null default 0 check(additions between 0 and 9999999999.99),
 deductions numeric(12,2) not null default 0 check(deductions between 0 and 9999999999.99),
 total numeric(12,2) check(total between 0 and 9999999999.99),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(assignment_id,revision), check(basis<>'daily' or contract_days is not null)
);
create table public.assignment_term_acceptances (
 term_id uuid primary key references public.assignment_terms(id) on delete restrict,
 accepted_by uuid not null references public.profiles(id), accepted_at timestamptz not null default now()
);
create table public.workforce_payments (
 id uuid primary key default gen_random_uuid(), assignment_id uuid not null unique references public.assignments(id) on delete restrict,
 term_id uuid not null unique references public.assignment_term_acceptances(term_id),
 amount numeric(12,2) not null check(amount between 0.01 and 9999999999.99),
 method text not null check(method in ('pix','transfer','cash','other')), paid_by uuid not null references public.profiles(id), paid_at timestamptz not null default now()
);
create function private.eventcore_assignment_evidence_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.agreed_amount is distinct from old.agreed_amount then raise exception 'historical_agreement_immutable'; end if;
 if new.status is distinct from old.status and exists(select 1 from public.event_services s join public.events e on e.id=s.event_id where s.id=old.event_service_id and e.status='completed') then raise exception 'completed_assignment_immutable'; end if;
 if exists(select 1 from public.assignment_terms where assignment_id=old.id) and new.status='confirmed' and old.status in ('invited','reserve') and not exists(select 1 from public.assignment_terms t join public.assignment_term_acceptances c on c.term_id=t.id where t.assignment_id=old.id) then raise exception 'worker_acceptance_required'; end if;
 return new;
end $$;
create trigger a_workflow_assignment_evidence before update on public.assignments for each row execute function private.eventcore_assignment_evidence_guard();
create function private.eventcore_payment_evidence_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or new.amount is distinct from old.amount or new.assignment_id is distinct from old.assignment_id or new.id is distinct from old.id
 or (old.status='paid' and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at')) then raise exception 'historical_payment_immutable'; end if;
 return new;
end $$;
create trigger a_workflow_payment_evidence before update or delete on public.payments for each row execute function private.eventcore_payment_evidence_guard();

create function private.eventcore_lock_work_assignment(p_assignment uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid; eid uuid;
begin
 select event_service_id into sid from public.assignments where id=p_assignment;
 select event_id into eid from public.event_services where id=sid for update;
 perform 1 from public.events where id=eid for update;
 perform 1 from public.assignments where id=p_assignment for update;
 return eid;
end $$;
create or replace function private.eventcore_set_assignment_amount(p_assignment_id uuid,p_amount numeric) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not private.eventcore_can_pay_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
 if p_amount is null or p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2) then raise exception 'invalid_payment_amount'; end if;
 if exists(select 1 from public.assignment_terms where assignment_id=p_assignment_id) then raise exception 'remuneration_revision_required'; end if;
 raise exception 'historical_agreement_immutable';
end $$;
create function private.eventcore_terms_dto(p_term uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',t.id,'assignment_id',t.assignment_id,'revision',t.revision,'basis',t.basis,'rate',t.rate,'contract_days',t.contract_days,'planned_hours',t.planned_hours,'benefits',t.benefits,'additions',t.additions,'deductions',t.deductions,'total',t.total,'created_at',t.created_at,'accepted_at',c.accepted_at)
 from public.assignment_terms t left join public.assignment_term_acceptances c on c.term_id=t.id where t.id=p_term;
$$;
create function private.eventcore_accepted_term(p_assignment uuid) returns uuid language sql stable security definer set search_path='' as $$
 select t.id from public.assignment_terms t join public.assignment_term_acceptances c on c.term_id=t.id where t.assignment_id=p_assignment order by t.revision desc limit 1;
$$;
create function public.propose_assignment_terms(p_assignment_id uuid,p_terms jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare eid uuid; initial public.assignment_terms; amount numeric; rate numeric; add_amount numeric; deduct numeric; basis text; days integer; hours numeric; result uuid;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 if not private.eventcore_can_pay_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
 select * into initial from public.assignment_terms where assignment_id=p_assignment_id order by revision limit 1;
 if initial.id is null then raise exception 'historical_agreement_immutable'; end if;
 if exists(select 1 from public.events where id=eid and (status in ('completed','cancelled') or end_at<=now())) or exists(select 1 from public.assignments where id=p_assignment_id and status in ('cancelled','checked_out','no_show')) or exists(select 1 from public.workforce_payments where assignment_id=p_assignment_id) then raise exception 'agreement_closed'; end if;
 if jsonb_typeof(p_terms) is distinct from 'object' then raise exception 'invalid_remuneration'; end if;
 basis:=p_terms->>'basis'; rate:=(p_terms->>'rate')::numeric; days:=(p_terms->>'contract_days')::integer;
 hours:=nullif(p_terms->>'planned_hours','')::numeric; add_amount:=coalesce((p_terms->>'additions')::numeric,0); deduct:=coalesce((p_terms->>'deductions')::numeric,0);
 if basis is null or basis not in ('daily','service') or days is distinct from initial.contract_days or hours is distinct from initial.planned_hours or rate is null or rate not between 0 and 9999999999.99 or rate<>round(rate,2) or add_amount not between 0 and 9999999999.99 or add_amount<>round(add_amount,2) or deduct not between 0 and 9999999999.99 or deduct<>round(deduct,2) or length(coalesce(p_terms->>'benefits',''))>2000 then raise exception 'invalid_remuneration'; end if;
 amount:=rate*case when basis='daily' then days else 1 end+add_amount-deduct;
 if amount is null or amount not between 0 and 9999999999.99 then raise exception 'invalid_remuneration'; end if;
 insert into public.assignment_terms(assignment_id,revision,basis,rate,contract_days,planned_hours,benefits,additions,deductions,total,created_by)
 values(p_assignment_id,(select max(revision)+1 from public.assignment_terms where assignment_id=p_assignment_id),basis,rate,days,hours,p_terms->>'benefits',add_amount,deduct,amount,auth.uid()) returning id into result;
 return result;
end $$;
create function public.accept_assignment_terms(p_term_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare t public.assignment_terms; eid uuid;
begin
 select * into t from public.assignment_terms where id=p_term_id;
 eid:=private.eventcore_lock_work_assignment(t.assignment_id);
 if t.id is null or not private.eventcore_owns_assignment(t.assignment_id) or not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if exists(select 1 from public.assignment_term_acceptances where term_id=t.id) then return; end if;
 if exists(select 1 from public.events where id=eid and (status in ('completed','cancelled') or end_at<=now())) or exists(select 1 from public.assignments where id=t.assignment_id and status in ('cancelled','checked_out','no_show')) or exists(select 1 from public.workforce_payments where assignment_id=t.assignment_id) then raise exception 'agreement_closed'; end if;
 if t.revision<>(select max(revision) from public.assignment_terms where assignment_id=t.assignment_id) then raise exception 'stale_terms'; end if;
 insert into public.assignment_term_acceptances(term_id,accepted_by) values(t.id,auth.uid());
 update public.assignments set status='confirmed' where id=t.assignment_id and status in ('invited','reserve');
end $$;
create or replace function public.respond_to_assignment(p_assignment_id uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare eid uuid; a public.assignments; tid uuid;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 if not private.eventcore_owns_assignment(a.id) or not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if p_status is null or p_status not in ('confirmed','cancelled') or a.status not in ('invited','reserve') then raise exception 'invalid_assignment_status_transition'; end if;
 select id into tid from public.assignment_terms where assignment_id=a.id order by revision desc limit 1;
 if p_status='confirmed' and tid is not null then perform public.accept_assignment_terms(tid);
 else update public.assignments set status=p_status where id=a.id; end if;
end $$;
create or replace function public.mark_assignment_paid(p_assignment_id uuid,p_method text) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; amount numeric; tid uuid;
begin
 perform private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 if not private.eventcore_can_pay_assignment(a.id) then raise exception 'forbidden'; end if;
 if a.status in ('cancelled','reserve','no_show') or p_method is null or p_method not in ('pix','transfer','cash','other') then raise exception 'invalid_payment'; end if;
 if exists(select 1 from public.assignment_terms where assignment_id=a.id) then
  tid:=private.eventcore_accepted_term(a.id);
  if tid is null then raise exception 'worker_acceptance_required'; end if;
  select total into amount from public.assignment_terms where id=tid;
  if amount is null or amount<=0 then raise exception 'payment_amount_required'; end if;
  if exists(select 1 from public.workforce_payments where assignment_id=a.id) then return; end if;
  insert into public.workforce_payments(assignment_id,term_id,amount,method,paid_by) values(a.id,tid,amount,p_method,auth.uid());
 else
  select p.amount into amount from public.payments p where p.assignment_id=a.id;
  amount:=coalesce(amount,a.agreed_amount);
  if amount is null or amount not between 0.01 and 9999999999.99 then raise exception 'payment_amount_required'; end if;
  if exists(select 1 from public.payments where assignment_id=a.id and status='paid') then return; end if;
  insert into public.payments(assignment_id,amount,status,method,paid_at) values(a.id,amount,'paid',p_method,now()) on conflict(assignment_id) do update set status='paid',method=excluded.method,paid_at=excluded.paid_at,updated_at=now();
 end if;
end $$;

CREATE OR REPLACE FUNCTION public.create_event_with_services(p_event jsonb, p_services jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  client uuid; organization uuid; starts timestamptz; ends timestamptz; tolerance integer;
  event_name text; venue_name text; event_status text;
  created_event public.events; created_service public.event_services; specialty public.specialties;
  draft jsonb; quantity integer; reserves integer; days integer; cost numeric; publish boolean; basis text; rate numeric; add_amount numeric; deduct numeric; hours numeric; contract_id uuid;
  created_services jsonb := '[]'::jsonb;
begin
  if actor is null or not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_event) is distinct from 'object' then raise exception 'invalid_event_data'; end if;
  if jsonb_typeof(p_services) is distinct from 'array' then raise exception 'invalid_event_function'; end if;
  begin
    client := nullif(p_event->>'client_id','')::uuid;
    organization := nullif(p_event->>'organization_id','')::uuid;
    starts := (p_event->>'start_at')::timestamptz;
    ends := (p_event->>'end_at')::timestamptz;
    tolerance := coalesce(nullif(p_event->>'arrival_tolerance_minutes','')::integer,15);
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_event_data';
  end;
  event_name := btrim(p_event->>'name'); venue_name := btrim(p_event->>'venue');
  event_status := coalesce(p_event->>'status','planning');
  if coalesce(event_name,'')='' or coalesce(venue_name,'')='' or starts is null or ends is null
    or not isfinite(starts) or not isfinite(ends) or ends<=starts or tolerance<0 or tolerance>180
    or event_status not in ('planning','staffing','confirmed') then raise exception 'invalid_event_data'; end if;
  if not private.eventcore_org_finance(organization) then raise exception 'forbidden'; end if;
  if not private.eventcore_valid_event_tenant(organization,client,actor,actor)
    or not exists(select 1 from public.clients c where c.id=client and c.active) then raise exception 'forbidden'; end if;

  if p_event ? 'origin' and coalesce(p_event->>'origin','') not in ('platform','whatsapp','referral','other') then raise exception 'invalid_work_origin'; end if;
  contract_id:=nullif(p_event->>'commercial_contract_id','')::uuid;
  if contract_id is not null and not exists(select 1 from public.commercial_contracts c where c.id=contract_id and c.provider_organization_id=organization and c.client_id=client) then raise exception 'forbidden'; end if;
  insert into public.events(client_id,name,venue,start_at,end_at,status,arrival_tolerance_minutes,
    coordinator_id,created_by_profile_id,organization_id,notes,calendar_sync_status,origin,commercial_contract_id,public_region)
  values(client,event_name,venue_name,starts,ends,event_status,tolerance,actor,actor,organization,
    nullif(btrim(p_event->>'notes'),''),'pending',coalesce(p_event->>'origin','other'),contract_id,nullif(trim(p_event->>'public_region'),'')) returning * into created_event;

  insert into private.eventcore_creation_sessions values(created_event.id,pg_current_xact_id());
  for draft in select value from jsonb_array_elements(p_services) loop
    if jsonb_typeof(draft) is distinct from 'object' then raise exception 'invalid_event_function'; end if;
    -- Old cached clients omit this new field; new creations still default to one day.
    begin
      days := case when draft ? 'contract_days' then (draft->>'contract_days')::integer else 1 end;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'invalid_contract_days';
    end;
    if days is null or days < 1 then raise exception 'invalid_contract_days'; end if;
    begin
      select * into specialty from public.specialties where id=nullif(draft->>'specialty_id','')::uuid and active;
      quantity := (draft->>'quantity_needed')::integer;
      reserves := coalesce(nullif(draft->>'reserve_target','')::integer,0);
      cost := nullif(draft->>'freelancer_unit_cost','')::numeric;
      publish := coalesce((draft->>'open_marketplace')::boolean,false);
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'invalid_event_function'; end;
    if specialty.id is null then raise exception 'invalid_event_specialty'; end if;
    if quantity is null or quantity<1 or reserves<0
      or (cost is not null and (cost::text in ('NaN','Infinity','-Infinity') or cost<0 or cost>9999999999.99 or cost<>round(cost,2)))
      then raise exception 'invalid_event_function'; end if;
    basis:=nullif(draft->>'remuneration_basis',''); rate:=nullif(draft->>'remuneration_rate','')::numeric;
    add_amount:=coalesce((draft->>'additions')::numeric,0); deduct:=coalesce((draft->>'deductions')::numeric,0); hours:=nullif(draft->>'planned_hours','')::numeric;
    if basis is not null then
      if basis not in ('daily','service') or rate is null or rate not between 0 and 9999999999.99 or rate<>round(rate,2) then raise exception 'invalid_remuneration'; end if;
      cost:=rate*case when basis='daily' then days else 1 end+add_amount-deduct;
    elsif rate is not null or add_amount<>0 or deduct<>0 then raise exception 'invalid_remuneration'; end if;
    if add_amount not between 0 and 9999999999.99 or add_amount<>round(add_amount,2) or deduct not between 0 and 9999999999.99 or deduct<>round(deduct,2) or (hours is not null and (hours not between 0 and 9999.99 or hours<>round(hours,2))) or (cost is not null and cost not between 0 and 9999999999.99) or length(coalesce(draft->>'benefits',''))>2000 then raise exception 'invalid_remuneration'; end if;
    insert into public.event_services(event_id,specialty_id,service_type,label,quantity_needed,reserve_target,contract_days,
      freelancer_unit_cost,briefing,requirements,visibility,application_enabled,remuneration_basis,remuneration_rate,planned_hours,benefits,additions,deductions,public_description)
    values(created_event.id,specialty.id,case when specialty.slug in ('loader','security','waiter') then specialty.slug else 'other' end,
      specialty.name,quantity,reserves,days,cost,nullif(btrim(draft->>'briefing'),''),nullif(btrim(draft->>'requirements'),''),
      case when publish then 'open' else 'private' end,publish,basis,rate,hours,nullif(draft->>'benefits',''),add_amount,deduct,nullif(trim(draft->>'public_description'),'')) returning * into created_service;
    created_services := created_services || jsonb_build_array(to_jsonb(created_service));
  end loop;
  delete from private.eventcore_creation_sessions where event_id=created_event.id;
  return jsonb_build_object('event',to_jsonb(created_event),'services',created_services);
end $function$
;


CREATE OR REPLACE FUNCTION public.create_event_assignment(p_service_id uuid, p_freelancer_id uuid, p_status text DEFAULT 'invited'::text, p_amount numeric DEFAULT NULL::numeric, p_application_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.event_services; ev public.events; a uuid; amount numeric; app public.job_applications; existing public.assignments;
begin
 select * into s from public.event_services where id=p_service_id for update; select * into ev from public.events where id=s.event_id for update;
 if s.id is null or not private.eventcore_can_hire_event(s.event_id) then raise exception 'forbidden'; end if;
 if not private.eventcore_can_finance_event(s.event_id) then raise exception 'forbidden'; end if;
 if ev.status in ('completed','cancelled') then raise exception 'event_closed'; end if;
 if not exists(select 1 from public.freelancers f where f.id=p_freelancer_id and f.active and (f.profile_id is null or exists(select 1 from public.profiles where id=f.profile_id and active and (profile_type='freelancer' or (profile_type is null and private.eventcore_is_staff()))))) then raise exception 'professional_unavailable'; end if;
 if p_status='confirmed' then raise exception 'worker_acceptance_required'; end if;
 if p_status not in ('invited','reserve') or p_status is null or (p_amount is not null and (p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2))) then raise exception 'invalid_assignment'; end if;
 if p_amount is not null and p_amount is distinct from s.freelancer_unit_cost then raise exception 'remuneration_revision_required'; end if;
 amount:=s.freelancer_unit_cost;
 if p_application_id is not null then
  select * into app from public.job_applications where id=p_application_id for update;
  if app.id is null or app.event_service_id<>s.id or app.freelancer_id<>p_freelancer_id or app.status not in ('interested','shortlisted') or p_status='reserve' then raise exception 'application_unavailable'; end if;
 end if;
 select * into existing from public.assignments where event_service_id=s.id and freelancer_id=p_freelancer_id for update;
 if existing.id is not null then raise exception 'historical_assignment_cannot_reopen'; end if;
 insert into public.assignments(event_service_id,freelancer_id,status,agreed_amount,application_id) values(s.id,p_freelancer_id,p_status,amount,p_application_id) returning id into a;
 insert into public.assignment_terms(assignment_id,revision,basis,rate,contract_days,planned_hours,benefits,additions,deductions,total,created_by)
 values(a,1,coalesce(s.remuneration_basis,'service'),coalesce(s.remuneration_rate,amount),s.contract_days,s.planned_hours,s.benefits,coalesce(s.additions,0),coalesce(s.deductions,0),amount,auth.uid());
 if p_application_id is not null then update public.job_applications set status='accepted',updated_at=now() where id=p_application_id; end if;
 update public.events set calendar_sync_status=case when google_event_id is null then 'pending' else 'out_of_sync' end,updated_at=now() where id=ev.id;
 return a;
end $function$
;

create function public.create_external_work_client(p_organization_id uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform private.eventcore_require_commercial(p_organization_id,'provider');
 if not private.eventcore_org_manager(p_organization_id) then raise exception 'forbidden'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 150 then raise exception 'invalid_external_client'; end if;
 insert into public.clients(organization_id,trade_name) values(p_organization_id,trim(p_name)) returning id into result;
 return result;
end $$;

-- Private base and reusable teams never create assignments or acceptance.
create table public.provider_freelancer_base (
 organization_id uuid not null references public.organizations(id), freelancer_id uuid not null references public.freelancers(id),
 added_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), primary key(organization_id,freelancer_id)
);
create table public.provider_teams (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 name text not null check(length(trim(name)) between 1 and 150), created_at timestamptz not null default now(), unique(organization_id,name)
);
create table public.provider_team_members (
 team_id uuid not null references public.provider_teams(id) on delete cascade, freelancer_id uuid not null references public.freelancers(id),
 created_at timestamptz not null default now(), primary key(team_id,freelancer_id)
);
create function public.set_provider_base_member(p_organization_id uuid,p_freelancer_id uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.eventcore_org_owner(p_organization_id) or not exists(select 1 from public.organizations where id=p_organization_id and market_role='provider') or p_enabled is null then raise exception 'forbidden'; end if;
 perform 1 from public.organizations where id=p_organization_id for update;
 if p_enabled then
  if not exists(select 1 from public.freelancers f join public.profiles p on p.id=f.profile_id where f.id=p_freelancer_id and f.active and p.active and p.profile_type='freelancer' and p.onboarding_completed) then raise exception 'professional_unavailable'; end if;
  insert into public.provider_freelancer_base(organization_id,freelancer_id,added_by) values(p_organization_id,p_freelancer_id,auth.uid()) on conflict do nothing;
 else
  delete from public.provider_team_members m using public.provider_teams t where m.team_id=t.id and t.organization_id=p_organization_id and m.freelancer_id=p_freelancer_id;
  delete from public.provider_freelancer_base where organization_id=p_organization_id and freelancer_id=p_freelancer_id;
 end if;
end $$;
create function public.save_provider_team(p_organization_id uuid,p_team_id uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not private.eventcore_org_owner(p_organization_id) or not exists(select 1 from public.organizations where id=p_organization_id and market_role='provider') then raise exception 'forbidden'; end if;
 perform 1 from public.organizations where id=p_organization_id for update;
 if length(trim(coalesce(p_name,''))) not between 1 and 150 then raise exception 'invalid_team'; end if;
 if p_team_id is null then insert into public.provider_teams(organization_id,name) values(p_organization_id,trim(p_name)) returning id into result;
 else update public.provider_teams set name=trim(p_name) where id=p_team_id and organization_id=p_organization_id returning id into result;
 if result is null then raise exception 'forbidden'; end if; end if;
 return result;
end $$;
create function public.delete_provider_team(p_team_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare org uuid;
begin
 select organization_id into org from public.provider_teams where id=p_team_id;
 if not private.eventcore_org_owner(org) then raise exception 'forbidden'; end if;
 perform 1 from public.organizations where id=org for update;
 delete from public.provider_teams where id=p_team_id;
end $$;
create function public.set_provider_team_member(p_team_id uuid,p_freelancer_id uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare org uuid;
begin
 select organization_id into org from public.provider_teams where id=p_team_id;
 if not private.eventcore_org_owner(org) or p_enabled is null then raise exception 'forbidden'; end if;
 perform 1 from public.organizations where id=org for update;
 if p_enabled then
  if not exists(select 1 from public.provider_freelancer_base where organization_id=org and freelancer_id=p_freelancer_id) then raise exception 'base_membership_required'; end if;
  insert into public.provider_team_members(team_id,freelancer_id) values(p_team_id,p_freelancer_id) on conflict do nothing;
 else delete from public.provider_team_members where team_id=p_team_id and freelancer_id=p_freelancer_id; end if;
end $$;
create function public.get_provider_people(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_org_manager(p_organization_id) or not exists(select 1 from public.organizations where id=p_organization_id and market_role='provider') then raise exception 'forbidden'; end if;
 return jsonb_build_object('base',coalesce((select jsonb_agg(jsonb_build_object('freelancer_id',f.id,'full_name',f.full_name,'city',f.city,'active',f.active) order by f.full_name,f.id) from public.provider_freelancer_base b join public.freelancers f on f.id=b.freelancer_id where b.organization_id=p_organization_id),'[]'::jsonb),
 'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'freelancer_ids',coalesce((select jsonb_agg(m.freelancer_id order by m.freelancer_id) from public.provider_team_members m where m.team_id=t.id),'[]'::jsonb)) order by t.name,t.id) from public.provider_teams t where t.organization_id=p_organization_id),'[]'::jsonb));
end $$;
create function public.invite_selected_workers(p_service_id uuid,p_freelancer_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare worker uuid; result jsonb:='[]';
begin
 if cardinality(p_freelancer_ids) is null or cardinality(p_freelancer_ids) not between 1 and 200 or array_position(p_freelancer_ids,null) is not null or cardinality(p_freelancer_ids)<>(select count(distinct x) from unnest(p_freelancer_ids) x) then raise exception 'invalid_invitation_recipients'; end if;
 foreach worker in array p_freelancer_ids loop result:=result||jsonb_build_array(public.create_event_assignment(p_service_id,worker,'invited')); end loop;
 return result;
end $$;

-- Financial sources are append-only and distinct from legacy contracted-gross records.
create table public.work_expenses (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete restrict,
 label text not null check(length(trim(label)) between 1 and 300), amount numeric(12,2) check(amount between 0 and 9999999999.99),
 receipt_reference text check(length(receipt_reference)<=500), recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.work_expense_payments (
 id uuid primary key default gen_random_uuid(), expense_id uuid not null references public.work_expenses(id) on delete restrict,
 amount numeric(12,2) not null check(amount between 0.01 and 9999999999.99), method text not null check(method in ('pix','transfer','cash','other')),
 paid_on date not null, idempotency_key text not null, recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(expense_id,idempotency_key)
);
create function private.eventcore_require_work_finance(p_event uuid) returns void language plpgsql stable security definer set search_path='' as $$
declare org uuid;
begin
 if not private.eventcore_can_finance_event(p_event) then raise exception 'forbidden'; end if;
 select organization_id into org from public.events where id=p_event;
 if org is null then
  if not private.eventcore_can_hire_event(p_event) then raise exception 'forbidden'; end if;
 else perform private.eventcore_require_commercial(org,'provider'); end if;
end $$;
create function public.record_work_expense(p_event_id uuid,p_label text,p_amount numeric,p_receipt_reference text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform 1 from public.events where id=p_event_id for update;
 perform private.eventcore_require_work_finance(p_event_id);
 if length(trim(coalesce(p_label,''))) not between 1 and 300 or (p_amount is not null and (p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2))) or length(coalesce(p_receipt_reference,''))>500 then raise exception 'invalid_expense'; end if;
 insert into public.work_expenses(event_id,label,amount,receipt_reference,recorded_by) values(p_event_id,trim(p_label),p_amount,p_receipt_reference,auth.uid()) returning id into result;
 return result;
end $$;
create function public.record_work_expense_payment(p_expense_id uuid,p_amount numeric,p_method text,p_paid_on date,p_idempotency_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare expense public.work_expenses; previous public.work_expense_payments; result uuid;
begin
 select * into expense from public.work_expenses where id=p_expense_id for update;
 if expense.id is null then raise exception 'forbidden'; end if;
 perform private.eventcore_require_work_finance(expense.event_id);
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('pix','transfer','cash','other') or p_paid_on is null or not isfinite(p_paid_on) or p_paid_on>private.eventcore_business_today() or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 then raise exception 'invalid_expense_payment'; end if;
 select * into previous from public.work_expense_payments where expense_id=p_expense_id and idempotency_key=p_idempotency_key;
 if previous.id is not null then
  if previous.amount<>p_amount or previous.method<>p_method or previous.paid_on<>p_paid_on then raise exception 'idempotency_conflict'; end if; return previous.id;
 end if;
 if expense.amount is null then raise exception 'expense_amount_unknown'; end if;
 if p_amount+coalesce((select sum(amount) from public.work_expense_payments where expense_id=expense.id),0)>expense.amount then raise exception 'expense_exceeds_payable'; end if;
 insert into public.work_expense_payments(expense_id,amount,method,paid_on,idempotency_key,recorded_by) values(expense.id,p_amount,p_method,p_paid_on,p_idempotency_key,auth.uid()) returning id into result;
 return result;
end $$;
create function public.get_work_finance(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e public.events; c public.commercial_contracts; f public.event_financials; sale numeric; received numeric; labor numeric; paid numeric; unknown_labor integer; expenses numeric; expense_paid numeric; unknown_expenses integer;
begin
 if not private.eventcore_can_finance_event(p_event_id) then raise exception 'forbidden'; end if;
 select * into e from public.events where id=p_event_id;
 select * into c from public.commercial_contracts where id=e.commercial_contract_id;
 select * into f from public.event_financials where event_id=e.id;
 sale:=coalesce(c.sale_total,f.gross_amount);
 if c.id is not null then select coalesce(sum(amount),0) into received from public.customer_receipts where contract_id=c.id; end if;
 select coalesce(sum(x.amount),0),count(*) filter(where x.amount is null) into labor,unknown_labor from (
 select case when wp.id is not null then wp.amount when exists(select 1 from public.assignment_terms where assignment_id=a.id) then (select total from public.assignment_terms where id=private.eventcore_accepted_term(a.id)) else coalesce(p.amount,a.agreed_amount) end amount
 from public.assignments a join public.event_services s on s.id=a.event_service_id left join public.payments p on p.assignment_id=a.id left join public.workforce_payments wp on wp.assignment_id=a.id
 where s.event_id=e.id and (wp.id is not null or p.status='paid' or (a.status not in ('cancelled','reserve','no_show') and coalesce(p.status,'pending')<>'cancelled'))
 ) x;
 select coalesce((select sum(w.amount) from public.workforce_payments w join public.assignments a on a.id=w.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id),0)+coalesce((select sum(p.amount) from public.payments p join public.assignments a on a.id=p.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id and p.status='paid'),0) into paid;
 select coalesce(sum(amount),0)+coalesce(f.extra_costs_amount,0),count(*) filter(where amount is null) into expenses,unknown_expenses from public.work_expenses where event_id=e.id;
 if coalesce(f.extra_costs_amount,0)=0 then select coalesce(sum(p.amount),0) into expense_paid from public.work_expense_payments p join public.work_expenses x on x.id=p.expense_id where x.event_id=e.id; end if;
 return jsonb_build_object('event_id',e.id,'sale_source',case when c.id is not null then 'accepted_contract' when f.event_id is not null then 'legacy_contracted_gross' else 'unknown' end,
 'sale_contracted',sale,'sale_received',received,'sale_receivable',sale-received,'sale_deductions',coalesce(f.deductions_amount,0),
 'labor_contracted',case when unknown_labor=0 then labor end,'labor_paid',paid,'labor_payable',case when unknown_labor=0 then labor-paid end,'unknown_labor_count',unknown_labor,
 'other_contracted',case when unknown_expenses=0 then expenses end,'other_paid',expense_paid,'other_payable',case when unknown_expenses=0 then expenses-expense_paid end,'unknown_expense_count',unknown_expenses,
 'estimated_result',case when unknown_labor=0 and unknown_expenses=0 then sale-labor-expenses-coalesce(f.deductions_amount,0) end,'result_label','estimated_before_unresolved_expenses_and_taxes',
 'expenses',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'label',x.label,'amount',x.amount,'receipt_reference',x.receipt_reference,'paid',coalesce((select sum(p.amount) from public.work_expense_payments p where p.expense_id=x.id),0)) order by x.created_at,x.id) from public.work_expenses x where x.event_id=e.id),'[]'::jsonb));
end $$;

create table public.assignment_completion_confirmations (
 assignment_id uuid primary key references public.assignments(id) on delete restrict,
 confirmed_by uuid not null references public.profiles(id), confirmed_at timestamptz not null default now()
);
create table public.contract_completion_confirmations (
 contract_id uuid primary key references public.commercial_contracts(id) on delete restrict,
 confirmed_by uuid not null references public.profiles(id), confirmed_at timestamptz not null default now()
);
create table public.provider_ratings (
 id uuid primary key default gen_random_uuid(), contract_id uuid not null unique references public.contract_completion_confirmations(contract_id),
 reviewer_profile_id uuid not null references public.profiles(id), rating smallint not null check(rating between 1 and 5), comment text check(length(comment)<=1000), created_at timestamptz not null default now()
);
create function private.eventcore_actual_completed_assignment(p_assignment uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id
 where a.id=p_assignment and e.status='completed' and a.status in ('confirmed','checked_in','checked_out') and (
 (e.end_at is not null and e.end_at<=now() and
  (exists(select 1 from public.attendance t where t.assignment_id=a.id and t.check_in_at is not null and t.check_out_at is not null and t.check_out_at>=t.check_in_at and t.validated_by is not null and t.validated_at is not null)
  or exists(select 1 from public.assignment_completion_confirmations x join public.freelancers f on f.id=a.freelancer_id where x.assignment_id=a.id and x.confirmed_by=f.profile_id)))
 -- Pre-workflow completed work can have an unknown scheduled end. Preserve its
 -- validated actual attendance; never fabricate the missing date or admit a new offer.
 or (e.end_at is null and e.origin is null and e.start_at<=now() and a.status='checked_out'
  and not exists(select 1 from public.assignment_terms where assignment_id=a.id)
  and exists(select 1 from public.attendance t where t.assignment_id=a.id and t.check_in_at is not null and t.check_out_at>=t.check_in_at and t.check_out_at<=now() and t.validated_by is not null and t.validated_at is not null))
 ));
$$;
create function public.complete_work_event(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.events where id=p_event_id for update;
 if not private.eventcore_can_manage_event(p_event_id) then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.events where id=p_event_id and end_at<=now() and status<>'cancelled') then raise exception 'completed_event_required'; end if;
 update public.events set status='completed',updated_at=now() where id=p_event_id;
end $$;
create function public.confirm_assignment_completion(p_assignment_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare eid uuid;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 if not private.eventcore_owns_assignment(p_assignment_id) or not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.events where id=eid and status='completed' and end_at<=now()) then raise exception 'completed_event_required'; end if;
 if not exists(select 1 from public.assignments where id=p_assignment_id and status in ('confirmed','checked_in','checked_out')) then raise exception 'confirmed_assignment_required'; end if;
 if exists(select 1 from public.assignment_terms where assignment_id=p_assignment_id) and private.eventcore_accepted_term(p_assignment_id) is null then raise exception 'worker_acceptance_required'; end if;
 insert into public.assignment_completion_confirmations(assignment_id,confirmed_by) values(p_assignment_id,auth.uid()) on conflict do nothing;
end $$;
create or replace function public.submit_assignment_rating(p_assignment_id uuid,p_rating integer,p_comment text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare eid uuid; a public.assignments; result uuid;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 if a.id is null or not private.eventcore_can_manage_event(eid) then raise exception 'actual_contractor_required'; end if;
 if private.eventcore_owns_freelancer(a.freelancer_id) then raise exception 'self_review_not_allowed'; end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>1000 then raise exception 'invalid_rating'; end if;
 if not private.eventcore_actual_completed_assignment(a.id) then raise exception 'confirmed_completed_work_required'; end if;
 insert into public.ratings(assignment_id,event_id,freelancer_id,reviewer_profile_id,rating,comment) values(a.id,eid,a.freelancer_id,auth.uid(),p_rating,nullif(trim(p_comment),'')) returning id into result;
 return result;
exception when unique_violation then raise exception 'assignment_already_rated';
end $$;
create function public.confirm_contract_completion(p_contract_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) or private.eventcore_org_member(c.provider_organization_id) then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.events where commercial_contract_id=c.id and status='completed' and end_at<=now()) then raise exception 'completed_event_required'; end if;
 insert into public.contract_completion_confirmations(contract_id,confirmed_by) values(c.id,auth.uid()) on conflict do nothing;
end $$;
create function public.submit_provider_rating(p_contract_id uuid,p_rating integer,p_comment text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts; result uuid;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) or private.eventcore_org_member(c.provider_organization_id) then raise exception 'forbidden'; end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>1000 then raise exception 'invalid_rating'; end if;
 if not exists(select 1 from public.contract_completion_confirmations where contract_id=c.id) then raise exception 'confirmed_completed_work_required'; end if;
 insert into public.provider_ratings(contract_id,reviewer_profile_id,rating,comment) values(c.id,auth.uid(),p_rating,nullif(trim(p_comment),'')) returning id into result;
 return result;
exception when unique_violation then raise exception 'provider_already_rated';
end $$;
create function public.get_provider_worker_history(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not (private.eventcore_org_manager(p_organization_id) or private.eventcore_org_finance(p_organization_id)) then raise exception 'forbidden'; end if;
 return coalesce((with evidence as (
 select a.id,a.freelancer_id,s.event_id from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where e.organization_id=p_organization_id and private.eventcore_actual_completed_assignment(a.id)
 ), metrics as (
 select f.id,f.full_name,f.city,count(distinct x.event_id)::integer job_count,
 (select round(avg(r.rating),2) from public.ratings r join evidence z on z.id=r.assignment_id where z.freelancer_id=f.id) average_stars,
 (select count(*)::integer from public.ratings r join evidence z on z.id=r.assignment_id where z.freelancer_id=f.id) review_count,
 (select count(*)::integer from evidence z join public.attendance t on t.assignment_id=z.id where z.freelancer_id=f.id and t.validated_by is not null and t.validated_at is not null and t.check_in_at is not null and t.check_out_at is not null and t.check_out_at>=t.check_in_at) punctuality_count,
 (select round(100.0*count(*) filter(where t.check_in_at<=e.start_at+e.arrival_tolerance_minutes*interval '1 minute')/nullif(count(*),0),2) from evidence z join public.attendance t on t.assignment_id=z.id join public.events e on e.id=z.event_id where z.freelancer_id=f.id and t.validated_by is not null and t.validated_at is not null and t.check_in_at is not null and t.check_out_at is not null and t.check_out_at>=t.check_in_at) punctuality
 from evidence x join public.freelancers f on f.id=x.freelancer_id group by f.id,f.full_name,f.city)
 select jsonb_agg(jsonb_build_object('freelancer_id',id,'full_name',full_name,'city',city,'job_count',job_count,'average_stars',average_stars,'review_count',review_count,'punctuality',punctuality,'punctuality_count',punctuality_count) order by punctuality desc nulls last,average_stars desc nulls last,job_count desc,full_name,id) from metrics),'[]'::jsonb);
end $$;
create function public.get_buyer_provider_history(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_org_finance(p_organization_id) then raise exception 'forbidden'; end if;
 return coalesce((with evidence as (
 select c.id,c.provider_organization_id from public.commercial_contracts c join public.contract_completion_confirmations x on x.contract_id=c.id where c.buyer_organization_id=p_organization_id
 ), metrics as (
 select o.id,o.display_name,count(*)::integer job_count,
 (select round(avg(r.rating),2) from public.provider_ratings r join evidence z on z.id=r.contract_id where z.provider_organization_id=o.id) average_stars,
 (select count(*)::integer from public.provider_ratings r join evidence z on z.id=r.contract_id where z.provider_organization_id=o.id) review_count
 from evidence c join public.organizations o on o.id=c.provider_organization_id group by o.id,o.display_name)
 select jsonb_agg(jsonb_build_object('organization_id',id,'display_name',display_name,'job_count',job_count,'average_stars',average_stars,'review_count',review_count) order by average_stars desc nulls last,review_count desc,job_count desc,display_name,id) from metrics),'[]'::jsonb);
end $$;

-- Worker finance projection: own conditions only, accepted amount separate from offered amount.
create function private.eventcore_work_assignment_dto(p_assignment uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'freelancer_id',a.freelancer_id,'event_service_id',s.id,'event_id',e.id,'event_name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,'event_status',e.status,'status',a.status,'function_name',s.label,
 'legacy_agreed_amount',a.agreed_amount,'offered_terms',private.eventcore_terms_dto((select id from public.assignment_terms where assignment_id=a.id order by revision desc limit 1)),
 'accepted_terms',private.eventcore_terms_dto(private.eventcore_accepted_term(a.id)),
 'terms_history',coalesce((select jsonb_agg(private.eventcore_terms_dto(t.id) order by t.revision) from public.assignment_terms t where t.assignment_id=a.id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(x.row order by x.paid_at) from (
 select jsonb_build_object('id',p.id,'amount',p.amount,'status',p.status,'method',p.method,'paid_at',p.paid_at,'term_id',null) row,p.paid_at from public.payments p where p.assignment_id=a.id
 union all select jsonb_build_object('id',p.id,'amount',p.amount,'status','paid','method',p.method,'paid_at',p.paid_at,'term_id',p.term_id),p.paid_at from public.workforce_payments p where p.assignment_id=a.id) x),'[]'::jsonb),
 'completion_confirmed',private.eventcore_actual_completed_assignment(a.id))
 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where a.id=p_assignment;
$$;
revoke all on function private.eventcore_work_assignment_dto(uuid) from public,anon,authenticated;
create function public.get_my_work_assignments() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() or private.eventcore_profile_type()<>'freelancer' then raise exception 'complete_freelancer_profile'; end if;
 return coalesce((select jsonb_agg(private.eventcore_work_assignment_dto(a.id) order by e.start_at desc,a.id)
 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where private.eventcore_owns_freelancer(a.freelancer_id)),'[]'::jsonb);
end $$;
create function public.get_event_remunerations(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_can_finance_event(p_event_id) then raise exception 'forbidden'; end if;
 return coalesce((select jsonb_agg(private.eventcore_work_assignment_dto(a.id) order by a.id) from public.assignments a join public.event_services s on s.id=a.event_service_id where s.event_id=p_event_id),'[]'::jsonb);
end $$;
revoke all on function public.get_event_remunerations(uuid) from public,anon;
grant execute on function public.get_event_remunerations(uuid) to authenticated;
create function public.get_buyer_work_status(p_contract_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.commercial_contracts;
begin
 select * into c from public.commercial_contracts where id=p_contract_id;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) then raise exception 'forbidden'; end if;
 return jsonb_build_object('contract_id',c.id,'sale_total',c.sale_total,'quote',c.quote_snapshot,
 'received_total',coalesce((select sum(amount) from public.customer_receipts where contract_id=c.id),0),
 'work',(select jsonb_build_object('event_id',e.id,'name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,'status',e.status,'completion_confirmed',exists(select 1 from public.contract_completion_confirmations where contract_id=c.id)) from public.events e where e.commercial_contract_id=c.id));
end $$;

-- Private portfolio/reputation requires an actual event/request/contract relationship.
create function private.eventcore_can_present_provider(p_organization uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.organizations o where o.id=p_organization and o.active and o.market_role='provider' and
 (private.eventcore_org_member(o.id) or exists(select 1 from public.contract_requests r where r.provider_organization_id=o.id and private.eventcore_org_finance(r.buyer_organization_id)) or exists(select 1 from public.commercial_contracts c where c.provider_organization_id=o.id and private.eventcore_org_finance(c.buyer_organization_id))));
$$;
create or replace function private.eventcore_can_view_photos(p_profile_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.profiles p where p.id=p_profile_id and p.active and
 (p.id=auth.uid() or exists(select 1 from public.freelancers f where f.profile_id=p.id and f.active and private.eventcore_operates_freelancer(f.id))
 or exists(select 1 from public.organizations o where o.owner_profile_id=p.id and private.eventcore_can_present_provider(o.id))));
$$;
create or replace function public.get_profile_photo_collection(p_freelancer_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare target uuid;
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if p_freelancer_id is null then target:=auth.uid();
 else
  if not (private.eventcore_owns_freelancer(p_freelancer_id) or private.eventcore_operates_freelancer(p_freelancer_id)) then raise exception 'forbidden'; end if;
  select profile_id into target from public.freelancers where id=p_freelancer_id and active;
  if target is null then return '[]'::jsonb; end if;
 end if;
 if not private.eventcore_can_view_photos(target) then raise exception 'forbidden'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'caption',caption,'object_path',object_path,'created_at',created_at) order by kind,slot) from public.profile_photos where profile_id=target),'[]'::jsonb);
end $$;
create function public.get_provider_photo_collection(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare target uuid;
begin
 if not private.eventcore_can_present_provider(p_organization_id) then raise exception 'forbidden'; end if;
 select owner_profile_id into target from public.organizations where id=p_organization_id;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'caption',caption,'object_path',object_path,'created_at',created_at) order by kind,slot) from public.profile_photos where profile_id=target and private.eventcore_can_view_photos(target)),'[]'::jsonb);
end $$;
create function public.get_provider_presentation(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_can_present_provider(p_organization_id) then raise exception 'forbidden'; end if;
 return (select jsonb_build_object('id',o.id,'display_name',o.display_name,'organization_type',o.organization_type,'bio',p.bio,
 'specialties',coalesce((select jsonb_agg(s.name order by s.name) from public.organization_specialties x join public.specialties s on s.id=x.specialty_id where x.organization_id=o.id and s.active),'[]'::jsonb),
 'average_stars',(select round(avg(r.rating),2) from public.provider_ratings r join public.commercial_contracts c on c.id=r.contract_id where c.provider_organization_id=o.id),
 'review_count',(select count(*)::int from public.provider_ratings r join public.commercial_contracts c on c.id=r.contract_id where c.provider_organization_id=o.id),
 'job_count',(select count(*)::int from public.contract_completion_confirmations x join public.commercial_contracts c on c.id=x.contract_id where c.provider_organization_id=o.id)) from public.organizations o join public.profiles p on p.id=o.owner_profile_id where o.id=p_organization_id);
end $$;
create or replace function public.get_professional_reputation(p_freelancer_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() or not (private.eventcore_owns_freelancer(p_freelancer_id) or private.eventcore_operates_freelancer(p_freelancer_id)) then raise exception 'forbidden'; end if;
 return (select jsonb_build_object('name',f.full_name,'availability',p.professional_status,'bio',p.bio,
 'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'date',r.created_at,'event_name',e.name) order by r.created_at desc,r.id) from public.ratings r join public.events e on e.id=r.event_id where r.freelancer_id=f.id and private.eventcore_actual_completed_assignment(r.assignment_id) and (private.eventcore_owns_freelancer(f.id) or private.eventcore_can_manage_event(e.id) or private.eventcore_can_finance_event(e.id))),'[]'::jsonb)) from public.freelancers f left join public.profiles p on p.id=f.profile_id where f.id=p_freelancer_id and f.active);
end $$;
create or replace function public.get_professional_directory() returns table(freelancer_id uuid,profile_id uuid,full_name text,city text,rating numeric,completed_jobs integer,review_count bigint,specialties text[]) language sql stable security definer set search_path='' as $$
 select f.id,f.profile_id,f.full_name,f.city,
 (select round(avg(r.rating),2) from public.ratings r where r.freelancer_id=f.id and private.eventcore_actual_completed_assignment(r.assignment_id)),
 (select count(distinct s.event_id)::int from public.assignments a join public.event_services s on s.id=a.event_service_id where a.freelancer_id=f.id and private.eventcore_actual_completed_assignment(a.id)),
 (select count(*) from public.ratings r where r.freelancer_id=f.id and private.eventcore_actual_completed_assignment(r.assignment_id)),
 coalesce((select array_agg(s.name order by s.sort_order,s.name) from public.profile_specialties x join public.specialties s on s.id=x.specialty_id where x.profile_id=f.profile_id and s.active),'{}'::text[])
 from public.freelancers f join public.profiles p on p.id=f.profile_id where private.eventcore_active_actor() and f.active and p.active and p.onboarding_completed and p.profile_type='freelancer'
 and (private.eventcore_profile_type() in ('team_lead','company','agency') or f.profile_id=auth.uid()) order by f.full_name,f.id;
$$;

-- Explicit policies and no raw writes on workflow evidence.
do $$ declare t text; begin
 foreach t in array array['assignment_terms','assignment_term_acceptances','workforce_payments','provider_freelancer_base','provider_teams','provider_team_members','work_expenses','work_expense_payments','assignment_completion_confirmations','contract_completion_confirmations','provider_ratings'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['assignment_terms','assignment_term_acceptances','workforce_payments','work_expenses','work_expense_payments','assignment_completion_confirmations','contract_completion_confirmations','provider_ratings','ratings'] loop
 execute format('create trigger workflow_immutable before update or delete on public.%I for each row execute function private.eventcore_commercial_immutable()',t);
 end loop;
end $$;
create policy terms_read on public.assignment_terms for select to authenticated using(private.eventcore_finances_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy term_acceptances_read on public.assignment_term_acceptances for select to authenticated using(exists(select 1 from public.assignment_terms t where t.id=term_id));
create policy workforce_payments_read on public.workforce_payments for select to authenticated using(private.eventcore_finances_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy base_read on public.provider_freelancer_base for select to authenticated using(private.eventcore_org_manager(organization_id));
create policy teams_read on public.provider_teams for select to authenticated using(private.eventcore_org_manager(organization_id));
create policy team_members_read on public.provider_team_members for select to authenticated using(exists(select 1 from public.provider_teams t where t.id=team_id));
create policy expenses_read on public.work_expenses for select to authenticated using(private.eventcore_can_finance_event(event_id));
create policy expense_payments_read on public.work_expense_payments for select to authenticated using(exists(select 1 from public.work_expenses e where e.id=expense_id));
create policy assignment_completion_read on public.assignment_completion_confirmations for select to authenticated using(private.eventcore_manages_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy contract_completion_read on public.contract_completion_confirmations for select to authenticated using(exists(select 1 from public.commercial_contracts c where c.id=contract_id and (private.eventcore_org_finance(c.provider_organization_id) or private.eventcore_org_finance(c.buyer_organization_id))));
create policy provider_ratings_read on public.provider_ratings for select to authenticated using(exists(select 1 from public.commercial_contracts c where c.id=contract_id and (private.eventcore_org_finance(c.provider_organization_id) or private.eventcore_org_finance(c.buyer_organization_id))));

create index assignment_terms_assignment_idx on public.assignment_terms(assignment_id,revision desc);
create index work_expenses_event_idx on public.work_expenses(event_id);
create index work_expense_payments_expense_idx on public.work_expense_payments(expense_id);
create index provider_team_members_worker_idx on public.provider_team_members(freelancer_id);
create index base_worker_idx on public.provider_freelancer_base(freelancer_id);
-- Trigger/DTO internals never become application RPCs.
revoke all on function private.eventcore_workflow_service_guard(),private.eventcore_workflow_event_guard(),private.eventcore_assignment_evidence_guard(),private.eventcore_payment_evidence_guard(),private.eventcore_lock_work_assignment(uuid),private.eventcore_terms_dto(uuid),private.eventcore_accepted_term(uuid),private.eventcore_actual_completed_assignment(uuid),private.eventcore_can_present_provider(uuid) from public,anon,authenticated;
-- can_view_photos is retained as the canonical RLS authorization helper.
revoke all on function public.propose_assignment_terms(uuid,jsonb),public.accept_assignment_terms(uuid),public.set_provider_base_member(uuid,uuid,boolean),public.save_provider_team(uuid,uuid,text),public.delete_provider_team(uuid),public.set_provider_team_member(uuid,uuid,boolean),public.get_provider_people(uuid),public.invite_selected_workers(uuid,uuid[]),public.record_work_expense(uuid,text,numeric,text),public.record_work_expense_payment(uuid,numeric,text,date,text),public.get_work_finance(uuid),public.complete_work_event(uuid),public.confirm_assignment_completion(uuid),public.confirm_contract_completion(uuid),public.submit_provider_rating(uuid,integer,text),public.get_provider_worker_history(uuid),public.get_buyer_provider_history(uuid),public.get_my_work_assignments(),public.get_buyer_work_status(uuid),public.get_provider_photo_collection(uuid),public.get_provider_presentation(uuid) from public,anon;
grant execute on function public.propose_assignment_terms(uuid,jsonb),public.accept_assignment_terms(uuid),public.set_provider_base_member(uuid,uuid,boolean),public.save_provider_team(uuid,uuid,text),public.delete_provider_team(uuid),public.set_provider_team_member(uuid,uuid,boolean),public.get_provider_people(uuid),public.invite_selected_workers(uuid,uuid[]),public.record_work_expense(uuid,text,numeric,text),public.record_work_expense_payment(uuid,numeric,text,date,text),public.get_work_finance(uuid),public.complete_work_event(uuid),public.confirm_assignment_completion(uuid),public.confirm_contract_completion(uuid),public.submit_provider_rating(uuid,integer,text),public.get_provider_worker_history(uuid),public.get_buyer_provider_history(uuid),public.get_my_work_assignments(),public.get_buyer_work_status(uuid),public.get_provider_photo_collection(uuid),public.get_provider_presentation(uuid) to authenticated;

revoke all on function public.create_external_work_client(uuid,text) from public,anon;
grant execute on function public.create_external_work_client(uuid,text) to authenticated;

create function public.publish_work_function(p_service_id uuid,p_published boolean) returns void language plpgsql security definer set search_path='' as $$
declare s public.event_services;
begin
 select * into s from public.event_services where id=p_service_id for update;
 perform 1 from public.events where id=s.event_id for update;
 if s.id is null or not private.eventcore_can_hire_event(s.event_id) or not private.eventcore_can_finance_event(s.event_id) or p_published is null then raise exception 'forbidden'; end if;
 if exists(select 1 from public.events where id=s.event_id and status in ('completed','cancelled')) then raise exception 'event_closed'; end if;
 update public.event_services set visibility=case when p_published then 'open' else 'private' end,application_enabled=p_published where id=s.id;
end $$;
revoke all on function public.publish_work_function(uuid,boolean) from public,anon;
grant execute on function public.publish_work_function(uuid,boolean) to authenticated;

revoke all on function private.eventcore_require_work_finance(uuid) from public,anon,authenticated;
create function public.get_work_opportunities() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('service_id',o.service_id,'event_id',o.event_id,'event_name',o.event_name,'start_at',o.start_at,'end_at',o.end_at,'venue',o.venue,'function_name',o.function_name,'specialty_id',o.specialty_id,'vacancies',o.vacancies,'amount',o.amount,'contractor_name',o.contractor_name,'requirements',o.requirements,'event_status',o.event_status,'compatible',o.compatible,'contract_days',o.contract_days,'remuneration',case when private.eventcore_profile_type()='freelancer' then jsonb_build_object('basis',coalesce(s.remuneration_basis,'service'),'rate',coalesce(s.remuneration_rate,s.freelancer_unit_cost),'contract_days',s.contract_days,'planned_hours',s.planned_hours,'benefits',null,'additions',coalesce(s.additions,0),'deductions',coalesce(s.deductions,0),'total',s.freelancer_unit_cost) end) order by o.start_at,o.function_name,o.service_id),'[]'::jsonb)
 from public.get_event_opportunities() o join public.event_services s on s.id=o.service_id;
$$;
revoke all on function public.get_work_opportunities() from public,anon;
grant execute on function public.get_work_opportunities() to authenticated;

-- A published function is a neutral opportunity, not permission to publish its private job/client/location.
CREATE OR REPLACE FUNCTION public.get_event_opportunities()
 RETURNS TABLE(service_id uuid, event_id uuid, event_name text, start_at timestamp with time zone, end_at timestamp with time zone, venue text, function_name text, specialty_id uuid, vacancies integer, amount numeric, contractor_name text, requirements text, event_status text, compatible boolean, contract_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select s.id,e.id,'Oportunidade: '||s.label,date_trunc('day',e.start_at,'America/Sao_Paulo'),date_trunc('day',e.end_at,'America/Sao_Paulo'),coalesce(e.public_region,'Região a confirmar'),s.label,s.specialty_id,
 greatest(0,s.quantity_needed-(select count(*)::int from public.assignments a where a.event_service_id=s.id and a.status in ('invited','confirmed','checked_in','checked_out'))),case when private.eventcore_profile_type()='freelancer' then s.freelancer_unit_cost else null end,coalesce(o.display_name,p.full_name,'EventCore'),s.public_description,e.status,
 (s.specialty_id is null or exists(select 1 from public.profile_specialties ps where ps.profile_id=(select auth.uid()) and ps.specialty_id=s.specialty_id)),s.contract_days
 from public.event_services s join public.events e on e.id=s.event_id left join public.organizations o on o.id=e.organization_id left join public.profiles p on p.id=coalesce(e.created_by_profile_id,e.coordinator_id)
 where s.visibility='open' and s.application_enabled and e.status in ('planning','staffing','confirmed','in_progress') and coalesce(e.end_at,e.start_at)>now()
 and exists(select 1 from public.profiles where id=(select auth.uid()) and active and onboarding_completed)
 and (e.organization_id is null or o.active) order by e.start_at,s.label;
$function$;


-- Retain canonical commercial state/authorization; compare DATE validity to São Paulo today.
create or replace function public.save_sale_quote(p_quote jsonb,p_items jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare org uuid:=nullif(p_quote->>'organization_id','')::uuid; rid uuid:=nullif(p_quote->>'request_id','')::uuid; pid uuid:=nullif(p_quote->>'id','')::uuid;
 client uuid:=nullif(p_quote->>'client_id','')::uuid; req public.contract_requests; old_quote public.proposals; item jsonb;
 qty integer; days integer; price numeric; cost numeric; hours numeric; total numeric:=0; validity date:=(p_quote->>'valid_until')::date;
begin
 perform private.eventcore_require_commercial(org,'provider');
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'invalid_quote_items'; end if;
 if length(trim(coalesce(p_quote->>'title','')))<2 or length(p_quote->>'title')>200 or validity is null or not isfinite(validity) or validity<private.eventcore_business_today()
 or length(coalesce(p_quote->>'payment_terms',''))>3000 then raise exception 'invalid_quote'; end if;
 -- Lock the request before the quote, consistently with submit/accept.
 if rid is not null then
  select * into req from public.contract_requests where id=rid for update;
  if req.id is null or req.provider_organization_id<>org or req.status in ('contracted','cancelled') then raise exception 'forbidden'; end if;
 end if;
 if pid is not null then
  select * into old_quote from public.proposals where id=pid for update;
  if old_quote.id is null or old_quote.organization_id is distinct from org or old_quote.request_id is distinct from rid then raise exception 'forbidden'; end if;
  if old_quote.status<>'draft' or old_quote.contract_id is not null then raise exception 'quote_immutable'; end if;
  if (p_quote->>'expected_revision')::integer is distinct from old_quote.revision then raise exception 'stale_quote'; end if;
  client:=old_quote.client_id;
 end if;
 if rid is not null and pid is null then
  -- Buyer identifier and customer display name are derived only from the authorized request.
  insert into public.clients(trade_name,organization_id) select display_name,org from public.organizations where id=req.buyer_organization_id returning id into client;
 elsif not exists(select 1 from public.clients where id=client and organization_id=org and active) then raise exception 'forbidden'; end if;
 if pid is null then
  insert into public.proposals(client_id,title,event_date,venue,created_by,organization_id,request_id,buyer_organization_id,valid_until,payment_terms,show_unit_prices)
  values(client,trim(p_quote->>'title'),nullif(p_quote->>'event_date','')::date,left(p_quote->>'venue',500),auth.uid(),org,rid,req.buyer_organization_id,validity,p_quote->>'payment_terms',coalesce((p_quote->>'show_unit_prices')::boolean,true)) returning id into pid;
 else
  update public.proposals set title=trim(p_quote->>'title'),event_date=nullif(p_quote->>'event_date','')::date,venue=left(p_quote->>'venue',500),valid_until=validity,payment_terms=p_quote->>'payment_terms',show_unit_prices=coalesce((p_quote->>'show_unit_prices')::boolean,true),revision=revision+1,updated_at=now() where id=pid;
  delete from public.proposal_items where proposal_id=pid;
 end if;
 for item in select value from jsonb_array_elements(p_items) loop
  qty:=(item->>'quantity')::integer; days:=(item->>'contract_days')::integer; price:=(item->>'client_unit_price')::numeric;
  cost:=nullif(item->>'freelancer_unit_cost','')::numeric; hours:=nullif(item->>'planned_hours','')::numeric;
  if qty is null or qty not between 1 and 10000 or days is null or days not between 1 and 366 or price is null or price not between 0 and 9999999999.99 or price<>round(price,2)
   or (cost is not null and (cost not between 0 and 9999999999.99 or cost<>round(cost,2))) or (hours is not null and hours not between 0 and 9999.99)
   or length(trim(coalesce(item->>'label','')))<1 or length(item->>'label')>300 then raise exception 'invalid_quote_item'; end if;
  total:=total+qty*days*price;
  if total>9999999999.99 then raise exception 'invalid_quote_total'; end if;
  insert into public.proposal_items(proposal_id,service_type,label,quantity,contract_days,client_unit_price,freelancer_unit_cost,planned_hours)
  values(pid,coalesce(item->>'service_type','other'),trim(item->>'label'),qty,days,price,cost,hours);
 end loop;
 update public.proposals set client_total=total where id=pid;
 return pid;
end $$;
create or replace function public.submit_sale_quote(p_proposal_id uuid,p_expected_revision integer) returns void
language plpgsql security definer set search_path='' as $$
declare p public.proposals; rid uuid;
begin
 select request_id into rid from public.proposals where id=p_proposal_id;
 perform 1 from public.contract_requests where id=rid for update;
 select * into p from public.proposals where id=p_proposal_id for update;
 perform private.eventcore_require_commercial(p.organization_id,'provider');
 if p.revision is distinct from p_expected_revision then raise exception 'stale_quote'; end if;
 if p.status<>'draft' or p.valid_until is null or p.valid_until<private.eventcore_business_today() or not exists(select 1 from public.proposal_items where proposal_id=p.id)
 or exists(select 1 from public.contract_requests where id=rid and status in ('contracted','cancelled')) then raise exception 'quote_not_available'; end if;
 update public.proposals set status='sent',submitted_at=now(),updated_at=now() where id=p.id;
 update public.contract_requests set status='quoted' where id=rid;
end $$;
create or replace function public.accept_sale_quote(p_proposal_id uuid,p_expected_revision integer,p_external_evidence text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.proposals; rid uuid; cid uuid:=gen_random_uuid(); snapshot jsonb; total numeric;
begin
 select request_id into rid from public.proposals where id=p_proposal_id;
 perform 1 from public.contract_requests where id=rid for update;
 select * into p from public.proposals where id=p_proposal_id for update;
 if p.id is null then raise exception 'forbidden'; end if;
 if p.buyer_organization_id is null then
  perform private.eventcore_require_commercial(p.organization_id,'provider');
  if length(trim(coalesce(p_external_evidence,'')))<3 or length(p_external_evidence)>2000 then raise exception 'external_acceptance_evidence_required'; end if;
 else
  perform private.eventcore_require_commercial(p.buyer_organization_id,'buyer');
  if not exists(select 1 from public.contract_requests r where r.id=p.request_id and r.provider_organization_id=p.organization_id and r.buyer_organization_id=p.buyer_organization_id and r.status='quoted') then raise exception 'quote_not_available'; end if;
 end if;
 if p.revision is distinct from p_expected_revision then raise exception 'stale_quote'; end if;
 if p.status<>'sent' or p.contract_id is not null or p.valid_until is null or p.valid_until<private.eventcore_business_today() then raise exception 'quote_not_available'; end if;
 if not exists(select 1 from public.organizations where id=p.organization_id and active and market_role='provider') then raise exception 'provider_required'; end if;
 select sum(quantity*contract_days*client_unit_price) into total from public.proposal_items where proposal_id=p.id;
 if total is null or total<>p.client_total then raise exception 'invalid_quote_total'; end if;
 snapshot:=private.eventcore_sale_quote_dto(p.id)||jsonb_build_object('status','accepted','contract_id',cid);
 insert into public.commercial_contracts(id,proposal_id,request_id,provider_organization_id,buyer_organization_id,client_id,sale_total,quote_snapshot,accepted_by,acceptance_method,external_evidence)
 values(cid,p.id,p.request_id,p.organization_id,p.buyer_organization_id,p.client_id,total,snapshot,auth.uid(),case when p.buyer_organization_id is null then 'external_recorded' else 'platform' end,case when p.buyer_organization_id is null then trim(p_external_evidence) end);
 update public.proposals set status='accepted',accepted_at=now(),contract_id=cid,updated_at=now() where id=p.id;
 update public.contract_requests set status='contracted' where id=p.request_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'sale_quote_accepted','contract',cid,jsonb_build_object('proposal_id',p.id,'revision',p.revision));
 return cid;
end $$;
create or replace function public.record_customer_receipt(p_contract_id uuid,p_amount numeric,p_method text,p_received_on date,p_idempotency_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts; r public.customer_receipts; result uuid; received numeric;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null then raise exception 'forbidden'; end if;
 perform private.eventcore_require_commercial(c.provider_organization_id,'provider');
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('pix','transfer','cash','other')
 or p_received_on is null or not isfinite(p_received_on) or p_received_on>private.eventcore_business_today() or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 then raise exception 'invalid_receipt'; end if;
 select * into r from public.customer_receipts where contract_id=c.id and idempotency_key=p_idempotency_key;
 if r.id is not null then
  if r.amount<>p_amount or r.method<>p_method or r.received_on<>p_received_on then raise exception 'idempotency_conflict'; end if;
  return r.id;
 end if;
 select coalesce(sum(amount),0) into received from public.customer_receipts where contract_id=c.id;
 if received+p_amount>c.sale_total then raise exception 'receipt_exceeds_receivable'; end if;
 insert into public.customer_receipts(contract_id,amount,method,received_on,recorded_by,idempotency_key) values(c.id,p_amount,p_method,p_received_on,auth.uid(),p_idempotency_key) returning id into result;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'customer_receipt_recorded','receipt',result,jsonb_build_object('contract_id',c.id));
 return result;
end $$;

-- Operational hours are schedule data; initial remuneration remains finance-only.
create or replace function public.get_event_operations(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_can_manage_event(p_event_id) then raise exception 'forbidden'; end if;
 return jsonb_build_object('event',(select jsonb_build_object('id',e.id,'name',e.name,'organization_id',e.organization_id,
 'status',e.status,'start_at',e.start_at,'end_at',e.end_at,'venue',e.venue,'arrival_tolerance_minutes',e.arrival_tolerance_minutes) from public.events e where e.id=p_event_id),
 'can_finance',private.eventcore_can_finance_event(p_event_id),
 'can_hire',private.eventcore_can_hire_event(p_event_id) and private.eventcore_can_finance_event(p_event_id) and exists(select 1 from public.events e where e.id=p_event_id and e.status not in ('completed','cancelled')),
 'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'event_id',s.event_id,'label',s.label,'service_type',s.service_type,
 'specialty_id',s.specialty_id,'quantity_needed',s.quantity_needed,'reserve_target',s.reserve_target,'contract_days',s.contract_days,'planned_hours',s.planned_hours,
 'briefing',s.briefing,'requirements',s.requirements,'visibility',s.visibility,'application_enabled',s.application_enabled) order by s.created_at,s.id) from public.event_services s where s.event_id=p_event_id),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'event_service_id',a.event_service_id,'freelancer_id',a.freelancer_id,'status',a.status) order by a.created_at,a.id)
 from public.assignments a join public.event_services s on s.id=a.event_service_id where s.event_id=p_event_id),'[]'::jsonb));
end $$;

-- Serialize actual attendance with event completion/schedule edits in the same service/event/assignment order.
create or replace function public.record_assignment_attendance(p_assignment_id uuid,p_kind text,p_lat numeric,p_lng numeric) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; ev public.events; att public.attendance; manager boolean; service_id uuid;
begin
 if not (private.eventcore_manages_assignment(p_assignment_id) or private.eventcore_owns_assignment(p_assignment_id)) then raise exception 'forbidden'; end if;
 select event_service_id into service_id from public.assignments where id=p_assignment_id;
 perform 1 from public.event_services where id=service_id for update;
 perform 1 from public.events where id=(select event_id from public.event_services where id=service_id) for update;
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
