-- Verify creation-only enforcement and existing publication management.
-- No production records or fixtures survive this transaction.
begin;
do $$ declare u uuid; actor_type text; org uuid; client uuid; begin
  foreach actor_type in array array['company','staff'] loop
    u:=gen_random_uuid();
    insert into auth.users(id,email,aud,role,raw_user_meta_data,raw_app_meta_data,email_confirmed_at)
    values(u,'creation-only-'||u||'@example.invalid','authenticated','authenticated','{}','{}',now());
    update public.profiles set active=true,profile_type='company',onboarding_completed=true,
      role=case when actor_type='staff' then 'admin' else 'freelancer' end where id=u;
    insert into public.organizations(owner_profile_id,organization_type,display_name) values(u,'company','Creation-only validation') returning id into org;
    insert into public.clients(trade_name,organization_id) values('Creation-only client',org) returning id into client;
    perform set_config('test.creation_only_'||actor_type,u::text,true);
    perform set_config('test.creation_only_org_'||actor_type,org::text,true);
    perform set_config('test.creation_only_client_'||actor_type,client::text,true);
  end loop;
end $$;
set local role authenticated;
do $$ declare actor_type text; input jsonb; draft jsonb; result jsonb; empty_event uuid; created_event uuid; service uuid; spec uuid; denied boolean; begin
  select id into spec from public.specialties where slug='loader' and active;
  foreach actor_type in array array['company','staff'] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.creation_only_'||actor_type),'role','authenticated')::text,true);
    input:=jsonb_build_object('name','Creation-only validation','venue','Validation venue',
      'client_id',current_setting('test.creation_only_client_'||actor_type),'organization_id',current_setting('test.creation_only_org_'||actor_type),
      'start_at',now(),'end_at',now()+interval '2 hours','status','confirmed');
    draft:=jsonb_build_object('specialty_id',spec,'quantity_needed',1,'open_marketplace',true);
    result:=public.create_event_with_services(input);empty_event:=(result->'event'->>'id')::uuid;
    result:=public.create_event_with_services(input||jsonb_build_object('id',empty_event),jsonb_build_array(draft));
    created_event:=(result->'event'->>'id')::uuid;service:=(result->'services'->0->>'id')::uuid;
    if created_event=empty_event or exists(select 1 from public.event_services s where s.event_id=empty_event) then
      raise exception 'creation_rpc_added_to_existing_event';
    end if;
    denied:=false;
    begin insert into public.event_services(event_id,service_type,label,specialty_id,quantity_needed)
      values(created_event,'loader','Late function',spec,1);
    exception when insufficient_privilege then denied:=true;end;
    if not denied then raise exception 'later_function_insert_allowed_%',actor_type;end if;
    denied:=false;
    begin update public.event_services set event_id=empty_event where id=service;
    exception when raise_exception then if sqlerrm in ('functions_creation_only','service_event_is_immutable') then denied:=true;else raise;end if;end;
    if not denied then raise exception 'function_moved_into_existing_event_%',actor_type;end if;
    update public.event_services set visibility='private',application_enabled=false where id=service;
    if not exists(select 1 from public.event_services where id=service and visibility='private' and not application_enabled) then raise exception 'existing_publication_close_failed';end if;
    update public.event_services set visibility='open',application_enabled=true where id=service;
    if not exists(select 1 from public.event_services where id=service and visibility='open' and application_enabled) then raise exception 'existing_publication_open_failed';end if;
  end loop;
end $$;
select 'PASS: company and staff cannot insert functions later or move functions; creation RPC always creates a new event; existing publication management preserved; fixtures rolled back' as validation;
rollback;
