-- The only function-creation workflow accepts a NEW event and its draft functions.
-- SECURITY DEFINER is deliberate: clients will lose direct function INSERT.
create or replace function public.create_event_with_services(p_event jsonb, p_services jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  client uuid; organization uuid; starts timestamptz; ends timestamptz; tolerance integer;
  event_name text; venue_name text; event_status text;
  created_event public.events; created_service public.event_services; specialty public.specialties;
  draft jsonb; quantity integer; reserves integer; cost numeric; publish boolean;
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
    insert into public.event_services(event_id,specialty_id,service_type,label,quantity_needed,reserve_target,
      freelancer_unit_cost,briefing,requirements,visibility,application_enabled)
    values(created_event.id,specialty.id,case when specialty.slug in ('loader','security','waiter') then specialty.slug else 'other' end,
      specialty.name,quantity,reserves,cost,nullif(btrim(draft->>'briefing'),''),nullif(btrim(draft->>'requirements'),''),
      case when publish then 'open' else 'private' end,publish) returning * into created_service;
    created_services := created_services || jsonb_build_array(to_jsonb(created_service));
  end loop;
  return jsonb_build_object('event',to_jsonb(created_event),'services',created_services);
end $$;
revoke all on function public.create_event_with_services(jsonb,jsonb) from public, anon;
grant execute on function public.create_event_with_services(jsonb,jsonb) to authenticated;
