-- Days belong to each function, not to the event or its financial amount.
-- Historical rows remain NULL because their original duration was never recorded.
alter table public.event_services add column contract_days integer
  check (contract_days is null or contract_days > 0);
comment on column public.event_services.contract_days is
  'Number of contracted days per professional for this function, configured only when creating the event. NULL means unknown for legacy functions.';

create or replace function private.eventcore_keep_service_contract_days() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.contract_days is distinct from old.contract_days then
    raise exception 'contract_days_creation_only';
  end if;
  return new;
end $$;
revoke all on function private.eventcore_keep_service_contract_days() from public, anon, authenticated;
create trigger trg_eventcore_service_contract_days_immutable
  before update of contract_days on public.event_services
  for each row execute function private.eventcore_keep_service_contract_days();

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
  draft jsonb; quantity integer; reserves integer; days integer; cost numeric; publish boolean;
  created_services jsonb := '[]'::jsonb;
begin
  if actor is null or not (private.eventcore_is_staff() or private.eventcore_is_business()) then raise exception 'forbidden'; end if;
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
  if not private.eventcore_valid_event_tenant(organization,client,actor,actor)
    or not exists(select 1 from public.clients c where c.id=client and c.active) then raise exception 'forbidden'; end if;

  insert into public.events(client_id,name,venue,start_at,end_at,status,arrival_tolerance_minutes,
    coordinator_id,created_by_profile_id,organization_id,notes,calendar_sync_status)
  values(client,event_name,venue_name,starts,ends,event_status,tolerance,actor,actor,organization,
    nullif(btrim(p_event->>'notes'),''),'pending') returning * into created_event;

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
    insert into public.event_services(event_id,specialty_id,service_type,label,quantity_needed,reserve_target,contract_days,
      freelancer_unit_cost,briefing,requirements,visibility,application_enabled)
    values(created_event.id,specialty.id,case when specialty.slug in ('loader','security','waiter') then specialty.slug else 'other' end,
      specialty.name,quantity,reserves,days,cost,nullif(btrim(draft->>'briefing'),''),nullif(btrim(draft->>'requirements'),''),
      case when publish then 'open' else 'private' end,publish) returning * into created_service;
    created_services := created_services || jsonb_build_array(to_jsonb(created_service));
  end loop;
  return jsonb_build_object('event',to_jsonb(created_event),'services',created_services);
end $function$;

revoke all on function public.create_event_with_services(jsonb,jsonb) from public, anon;
grant execute on function public.create_event_with_services(jsonb,jsonb) to authenticated, service_role;

-- Append the public duration to the existing sanitized opportunity response.
-- No dependents exist; drop/recreate is needed for the additional return column.
drop function public.get_event_opportunities();
CREATE OR REPLACE FUNCTION public.get_event_opportunities()
 RETURNS TABLE(service_id uuid, event_id uuid, event_name text, start_at timestamp with time zone, end_at timestamp with time zone, venue text, function_name text, specialty_id uuid, vacancies integer, amount numeric, contractor_name text, requirements text, event_status text, compatible boolean, contract_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select s.id,e.id,e.name,e.start_at,e.end_at,e.venue,s.label,s.specialty_id,
 greatest(0,s.quantity_needed-(select count(*)::int from public.assignments a where a.event_service_id=s.id and a.status in ('invited','confirmed','checked_in','checked_out'))),s.freelancer_unit_cost,coalesce(o.display_name,p.full_name,'EventCore'),s.requirements,e.status,
 (s.specialty_id is null or exists(select 1 from public.profile_specialties ps where ps.profile_id=(select auth.uid()) and ps.specialty_id=s.specialty_id)),s.contract_days
 from public.event_services s join public.events e on e.id=s.event_id left join public.organizations o on o.id=e.organization_id left join public.profiles p on p.id=coalesce(e.created_by_profile_id,e.coordinator_id)
 where s.visibility='open' and s.application_enabled and e.status in ('planning','staffing','confirmed','in_progress') and coalesce(e.end_at,e.start_at)>now()
 and exists(select 1 from public.profiles where id=(select auth.uid()) and active and onboarding_completed)
 and (e.organization_id is null or o.active) order by e.start_at,s.label;
$function$;

revoke all on function public.get_event_opportunities() from public, anon;
grant execute on function public.get_event_opportunities() to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_my_schedule()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   'quantity_needed',s.quantity_needed,'reserve_target',s.reserve_target,'briefing',s.briefing,'contract_days',s.contract_days,
   'visibility',s.visibility,'application_enabled',s.application_enabled))
   from public.event_services s where exists(select 1 from public.assignments a where a.event_service_id=s.id and a.freelancer_id=professional)),'[]'::jsonb)
 ) into result;
 return result;
end $function$;

revoke all on function public.get_my_schedule() from public, anon;
grant execute on function public.get_my_schedule() to authenticated, service_role;
