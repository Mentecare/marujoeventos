-- The production database is exercised with disposable fixtures only.
-- All successful and rejected operations are rolled back.
begin;
do $$ begin
  if to_regprocedure('public.create_event_with_services(jsonb,jsonb)') is null then
    raise exception 'event_creation_with_functions_not_implemented';
  end if;
end $$;
do $$ declare company uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); org uuid; other_org uuid; client uuid; foreign_client uuid; begin
  insert into auth.users(id,email,aud,role,raw_user_meta_data,raw_app_meta_data,email_confirmed_at)
  values(company,'creation-'||company||'@example.invalid','authenticated','authenticated','{}','{}',now()),
        (outsider,'creation-'||outsider||'@example.invalid','authenticated','authenticated','{}','{}',now());
  update public.profiles set active=true,profile_type='company',onboarding_completed=true where id=company;
  update public.profiles set active=true,profile_type='freelancer',onboarding_completed=true where id=outsider;
  insert into public.organizations(owner_profile_id,organization_type,display_name) values(company,'company','Creation validation') returning id into org;
  insert into public.organizations(owner_profile_id,organization_type,display_name) values(outsider,'company','Foreign validation') returning id into other_org;
  insert into public.clients(trade_name,organization_id) values('Creation client',org) returning id into client;
  insert into public.clients(trade_name,organization_id) values('Foreign client',other_org) returning id into foreign_client;
  perform set_config('test.creation_company',company::text,true);
  perform set_config('test.creation_outsider',outsider::text,true);
  perform set_config('test.creation_org',org::text,true);
  perform set_config('test.creation_other_org',other_org::text,true);
  perform set_config('test.creation_client',client::text,true);
  perform set_config('test.creation_foreign_client',foreign_client::text,true);
end $$;
set local role authenticated;
do $$ declare input jsonb; services jsonb; result jsonb; spec uuid; created_id uuid; bad jsonb; denied boolean; event_count int; service_count int; begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.creation_company'),'role','authenticated')::text,true);
  select id into spec from public.specialties where slug='loader' and active;
  input:=jsonb_build_object('name','  Creation validation  ','venue','  Validation venue  ',
    'client_id',current_setting('test.creation_client'),'organization_id',current_setting('test.creation_org'),
    'start_at',now(),'end_at',now()+interval '2 hours','status','planning','arrival_tolerance_minutes',15,
    'created_by_profile_id',current_setting('test.creation_outsider'),'coordinator_id',current_setting('test.creation_outsider'));
  services:=jsonb_build_array(
    jsonb_build_object('specialty_id',spec,'quantity_needed',2,'reserve_target',1,'freelancer_unit_cost',0,'open_marketplace',true,'briefing','  Chegar cedo  ','label','Forged label','service_type','security'),
    jsonb_build_object('specialty_id',spec,'quantity_needed',3,'reserve_target',0,'freelancer_unit_cost',null,'open_marketplace',false,'requirements','  Sapato fechado  '));
  result:=public.create_event_with_services(input,services);created_id:=(result->'event'->>'id')::uuid;
  if jsonb_array_length(result->'services')<>2 or (select count(*) from public.event_services s where s.event_id=created_id)<>2 then
    raise exception 'multiple_creation_functions_missing';
  end if;
  if not exists(select 1 from public.events e where e.id=created_id and e.created_by_profile_id=auth.uid() and e.coordinator_id=auth.uid() and e.name='Creation validation' and e.venue='Validation venue' and e.calendar_sync_status='pending') then
    raise exception 'event_creator_or_defaults_not_canonical';
  end if;
  if not exists(select 1 from public.event_services s join public.specialties sp on sp.id=s.specialty_id where s.event_id=created_id and s.label=sp.name and s.service_type='loader' and s.freelancer_unit_cost=0 and s.visibility='open' and s.application_enabled and s.briefing='Chegar cedo') then
    raise exception 'function_values_or_canonical_specialty_incorrect';
  end if;
  if not exists(select 1 from public.event_services s where s.event_id=created_id and s.freelancer_unit_cost is null and s.visibility='private' and not s.application_enabled and s.requirements='Sapato fechado') then
    raise exception 'absent_cost_changed_to_zero';
  end if;
  perform set_config('test.creation_event',created_id::text,true);
  result:=public.create_event_with_services(input);
  if jsonb_array_length(result->'services')<>0 then raise exception 'empty_functions_not_preserved';end if;
  perform set_config('test.creation_empty_event',result->'event'->>'id',true);
  select count(*) into event_count from public.events;select count(*) into service_count from public.event_services;
  foreach bad in array array[
    jsonb_build_object('specialty_id',gen_random_uuid(),'quantity_needed',1),
    jsonb_build_object('specialty_id',spec,'quantity_needed',0),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1.5),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'reserve_target',-1),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'freelancer_unit_cost',-0.01),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'freelancer_unit_cost',12.345),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'freelancer_unit_cost','NaN'),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'freelancer_unit_cost','Infinity'),
    jsonb_build_object('specialty_id',spec,'quantity_needed',1,'freelancer_unit_cost',10000000000)
  ] loop
    denied:=false;
    begin perform public.create_event_with_services(input,jsonb_build_array(services->0,bad));
    exception when raise_exception then if sqlerrm in ('invalid_event_function','invalid_event_specialty') then denied:=true;else raise;end if;end;
    if not denied then raise exception 'invalid_function_saved';end if;
    if (select count(*) from public.events)<>event_count or (select count(*) from public.event_services)<>service_count then raise exception 'partial_creation_left_records';end if;
  end loop;
  foreach bad in array array[
    input||jsonb_build_object('end_at',now()-interval '1 hour'),
    input||jsonb_build_object('name','  '),input||jsonb_build_object('status','completed'),
    input||jsonb_build_object('start_at','infinity'),input||jsonb_build_object('end_at',null)
  ] loop
    denied:=false;begin perform public.create_event_with_services(bad,services);
    exception when raise_exception then if sqlerrm='invalid_event_data' then denied:=true;else raise;end if;end;
    if not denied then raise exception 'invalid_event_saved';end if;
  end loop;
  denied:=false;begin perform public.create_event_with_services(input||jsonb_build_object('organization_id',current_setting('test.creation_other_org')),services);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'foreign_organization_creation_allowed';end if;
  denied:=false;begin perform public.create_event_with_services(input||jsonb_build_object('client_id',current_setting('test.creation_foreign_client')),services);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'foreign_client_creation_allowed';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.creation_outsider'),'role','authenticated')::text,true);
  denied:=false;begin perform public.create_event_with_services(input,services);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'freelancer_creation_allowed';end if;
  perform set_config('request.jwt.claims','{}',true);
  denied:=false;begin perform public.create_event_with_services(input,services);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'unauthenticated_creation_allowed';end if;
end $$;
set local role anon;
do $$ declare denied boolean:=false; begin
  begin perform public.create_event_with_services('{}','[]');exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'anonymous_creation_execute_allowed';end if;
end $$;
select 'PASS: atomic multiple-function creation; zero and absent costs; canonical identity and specialty; invalid inputs and tenant access rejected; fixtures rolled back' as validation;
rollback;
