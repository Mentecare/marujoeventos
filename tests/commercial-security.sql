-- Execute as postgres in an isolated transaction AFTER the migration. No persistent fixtures.
-- Any exception fails the suite. RLS is tested with SET LOCAL ROLE authenticated.
begin;
create function pg_temp.check_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_denied(statement text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then
   if sqlerrm in ('forbidden','identity_required','provider_required','quote_not_available','quote_immutable','stale_quote','external_acceptance_evidence_required','freelancer_ownership_is_immutable') or sqlstate='42501' then return; end if;
   raise;
 end;
 raise exception 'FAIL: unexpectedly allowed: %',statement;
end $$;
create function pg_temp.expect_error(statement text, expected text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then if sqlerrm=expected then return; end if; raise; end;
 raise exception 'FAIL: unexpectedly allowed: %',statement;
end $$;
create function pg_temp.check_keys(value jsonb, expected text[], label text) returns void language plpgsql as $$
begin
 perform pg_temp.check_true((select array_agg(k order by k) from jsonb_object_keys(value) k)=(select array_agg(k order by k) from unnest(expected) k),label);
end $$;
select pg_temp.check_true(private.eventcore_document_valid('cpf' ,'52998224725'),'CPF');
select pg_temp.check_true(private.eventcore_document_valid('cnpj','11222333000181'),'numeric CNPJ');
select pg_temp.check_true(private.eventcore_document_valid('cnpj','12ABC34501DE35'),'official alphanumeric CNPJ');
select pg_temp.check_true(not private.eventcore_document_valid('cnpj','12ABC34501DE34'),'bad digit');
-- Fixed test UUID prefix is deliberately isolated; the transaction rolls back auth triggers too.
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-4000-8000-000000000001','commercial-provider@example.invalid','{"full_name":"Provider"}'),
 ('10000000-0000-4000-8000-000000000002','commercial-buyer@example.invalid','{"full_name":"Buyer"}'),
 ('10000000-0000-4000-8000-000000000003','commercial-outsider@example.invalid','{"full_name":"Other"}'),
 ('10000000-0000-4000-8000-000000000004','commercial-coordinator@example.invalid','{"full_name":"Coordinator"}'),
 ('10000000-0000-4000-8000-000000000005','commercial-worker@example.invalid','{"full_name":"Worker"}'),
 ('10000000-0000-4000-8000-000000000006','commercial-legacy@example.invalid','{"full_name":"Legacy"}'),
 ('10000000-0000-4000-8000-000000000007','commercial-colleague@example.invalid','{"full_name":"Colleague"}'),
 ('10000000-0000-4000-8000-000000000008','commercial-unrelated-coordinator@example.invalid','{"full_name":"Unrelated coordinator"}'),
 ('10000000-0000-4000-8000-000000000009','commercial-identified-operator@example.invalid','{"full_name":"Identified operator"}'),
 ('10000000-0000-4000-8000-000000000010','commercial-onboarding@example.invalid','{"full_name":"New worker"}');
update public.profiles set profile_type='company',onboarding_completed=true where id::text like '10000000-%';
update public.profiles set role='admin' where id='10000000-0000-4000-8000-000000000003';
update public.profiles set role='coordinator' where id='10000000-0000-4000-8000-000000000004';
update public.profiles set profile_type='freelancer' where id in ('10000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000010');
update public.profiles set role='coordinator' where id in ('10000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000009');
update public.profiles set role='admin' where id='10000000-0000-4000-8000-000000000002';
insert into public.profile_private_identity(profile_id,document_type,document_number) values
 ('10000000-0000-4000-8000-000000000001','cpf','52998224725'),
 ('10000000-0000-4000-8000-000000000002','cnpj','12ABC34501DE35'),
 ('10000000-0000-4000-8000-000000000009','cpf','11144477735');
insert into public.organizations(id,owner_profile_id,organization_type,display_name,market_role,buyer_subtype) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','company','Provider','provider',null),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','agency','Buyer','buyer','agency'),
 ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','company','Other','unclassified',null);
insert into public.organization_members(organization_id,profile_id,member_role) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','manager'),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000009','manager');
insert into public.clients(id,trade_name,organization_id) values
 ('30000000-0000-4000-8000-000000000001','External','20000000-0000-4000-8000-000000000001'),
 ('30000000-0000-4000-8000-000000000002','Historical',null);
-- Setup legacy records without bypassing production guards: suppress only user triggers locally as postgres.
set local session_replication_role=replica;
insert into public.events(id,client_id,name,venue,start_at,organization_id,created_by_profile_id,coordinator_id) values
 ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','Provider event','Venue',now()+interval '1 day','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004'),
 ('40000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','Legacy event','Venue',now()-interval '1 day',null,'10000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000006'),
 ('40000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001','Buyer event','Venue',now()+interval '1 day','20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002');
insert into public.event_services(id,event_id,service_type,label,quantity_needed,freelancer_unit_cost) values
 ('50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','other','Assembly',10,440),
 ('50000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003','other','Buyer trap',10,440);
insert into public.freelancers(id,profile_id,full_name) values
 ('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005','Worker'),
 ('60000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000007','Colleague'),
 ('60000000-0000-4000-8000-000000000003',null,'Legacy unlinked');
insert into public.assignments(id,event_service_id,freelancer_id,status,agreed_amount) values
 ('70000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','confirmed',440),
 ('70000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002','confirmed',660);
insert into public.payments(assignment_id,amount,status) values('70000000-0000-4000-8000-000000000001',440,'pending'),('70000000-0000-4000-8000-000000000002',660,'pending');
insert into public.event_financials(event_id,gross_amount) values('40000000-0000-4000-8000-000000000001',5600);
update public.event_services set visibility='open',application_enabled=true where id='50000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
set local role authenticated;
-- C1: unrelated admin/coordinator and buyer staff cannot forge worker ownership, including INSERT/DELETE.
do $$ declare actor text; changed integer; begin
 foreach actor in array array['10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000002'] loop
  perform set_config('request.jwt.claim.sub',actor,true);
  update public.freelancers set profile_id=actor::uuid where id='60000000-0000-4000-8000-000000000001'; get diagnostics changed=row_count;
  perform pg_temp.check_true(changed=0,'linked ownership rebind denied: '||actor);
  delete from public.freelancers where id='60000000-0000-4000-8000-000000000001'; get diagnostics changed=row_count;
  perform pg_temp.check_true(changed=0,'linked deletion cannot enable reinsert: '||actor);
  perform pg_temp.expect_denied(format('insert into public.freelancers(profile_id,full_name) values(%L,''Forged self worker'')',actor));
  perform pg_temp.expect_denied($q$insert into public.freelancers(profile_id,full_name) values('10000000-0000-4000-8000-000000000006','Forged other worker')$q$);
  perform pg_temp.check_true(not exists(select 1 from public.assignments) and not exists(select 1 from public.payments),'staff rebind attempt exposes no wages: '||actor);
  perform pg_temp.expect_denied($q$select public.get_event_operations('40000000-0000-4000-8000-000000000001')$q$);
 end loop;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
update public.freelancers set full_name='Maintained legacy worker',city='São Paulo' where id='60000000-0000-4000-8000-000000000003';
select pg_temp.check_true(exists(select 1 from public.freelancers where id='60000000-0000-4000-8000-000000000003' and profile_id is null and full_name='Maintained legacy worker'),'authorized unlinked legacy maintenance retained');
select pg_temp.expect_error($q$update public.freelancers set profile_id='10000000-0000-4000-8000-000000000003' where id='60000000-0000-4000-8000-000000000003'$q$,'freelancer_ownership_is_immutable');
insert into public.freelancers(id,full_name) values('60000000-0000-4000-8000-000000000004','New unlinked maintenance record');
delete from public.freelancers where id='60000000-0000-4000-8000-000000000004';
select pg_temp.check_true(not exists(select 1 from public.freelancers where id='60000000-0000-4000-8000-000000000004'),'authorized unlinked insert/delete retained');
-- M1/M2: identified operator without finance cannot hire; each payload row has an exact allowlist.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000009',true);
select pg_temp.check_true(private.eventcore_has_identity() and private.eventcore_can_hire_event('40000000-0000-4000-8000-000000000001') and not private.eventcore_can_finance_event('40000000-0000-4000-8000-000000000001'),'identified operating prerequisite alone is insufficient');
select pg_temp.check_true((public.get_event_operations('40000000-0000-4000-8000-000000000001')->>'can_hire')::boolean=false,'effective hiring flag includes finance');
select pg_temp.expect_denied($q$select public.create_event_assignment('50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000003')$q$);
select pg_temp.check_true(jsonb_array_length(public.get_event_operations('40000000-0000-4000-8000-000000000001')->'services')=1 and jsonb_array_length(public.get_event_operations('40000000-0000-4000-8000-000000000001')->'assignments')=2,'allowlisted operational rows remain populated');
select pg_temp.check_keys(public.get_event_operations('40000000-0000-4000-8000-000000000001'),array['event','can_finance','can_hire','services','assignments'],'operations root keys');
select pg_temp.check_keys(public.get_event_operations('40000000-0000-4000-8000-000000000001')->'event',array['id','name','organization_id','status','start_at','end_at','venue','arrival_tolerance_minutes'],'operations event keys');
select pg_temp.check_keys(value,array['id','event_id','label','service_type','specialty_id','quantity_needed','reserve_target','contract_days','planned_hours','briefing','requirements','visibility','application_enabled'],'operations service keys') from jsonb_array_elements(public.get_event_operations('40000000-0000-4000-8000-000000000001')->'services');
select pg_temp.check_keys(value,array['id','event_service_id','freelancer_id','status'],'operations assignment keys') from jsonb_array_elements(public.get_event_operations('40000000-0000-4000-8000-000000000001')->'assignments');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.set_organization_finance_member('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000009',true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000009',true);
select pg_temp.check_true((public.get_event_operations('40000000-0000-4000-8000-000000000001')->>'can_hire')::boolean,'effective hiring flag allows identified finance operator');
update public.events set status='cancelled' where id='40000000-0000-4000-8000-000000000001';
select pg_temp.check_true((public.get_event_operations('40000000-0000-4000-8000-000000000001')->>'can_hire')::boolean=false,'closed event cannot advertise hire capability');
select pg_temp.expect_error($q$select public.create_event_assignment('50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000003')$q$,'event_closed');
update public.events set status='completed',start_at=now()-interval '2 days',end_at=now()-interval '1 day' where id='40000000-0000-4000-8000-000000000001';
select pg_temp.check_true((public.get_event_operations('40000000-0000-4000-8000-000000000001')->>'can_hire')::boolean=false,'completed event cannot advertise hire capability');
select pg_temp.expect_error($q$select public.create_event_assignment('50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000003')$q$,'event_closed');
-- Restore isolated fixture state after completion probes; production cannot reopen it.
reset role;
set local session_replication_role=replica;
update public.events set status='planning',start_at=now()+interval '1 day',end_at=null where id='40000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',true);
select pg_temp.check_true(private.eventcore_can_manage_event('40000000-0000-4000-8000-000000000002'),'undocumented legacy creator operations');
select pg_temp.check_true(private.eventcore_can_finance_event('40000000-0000-4000-8000-000000000002'),'undocumented legacy creator finance');
select pg_temp.check_true(not private.eventcore_can_hire_event('40000000-0000-4000-8000-000000000002'),'legacy new hiring gates identity/classification');
select pg_temp.check_true((public.get_commercial_context()->>'identity_complete')::boolean=false,'legacy identity is honestly incomplete');
select pg_temp.expect_denied($q$select public.configure_business_identity('{"organization_id":"20000000-0000-4000-8000-000000000001","display_name":"Forged provider","organization_type":"company","market_role":"provider","document":"52998224725"}')$q$);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.expect_denied($q$select public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000002','client_id','30000000-0000-4000-8000-000000000001','name','Buyer direct work','venue','Venue','start_at',now()+interval '1 day','end_at',now()+interval '2 days'),'[]')$q$);
select pg_temp.expect_error($q$insert into public.events(client_id,name,venue,start_at,organization_id,created_by_profile_id,coordinator_id) values('30000000-0000-4000-8000-000000000001','Buyer raw work','Venue',now()+interval '1 day','20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002')$q$,'invalid_event_tenant');
select pg_temp.expect_denied($q$select public.create_event_assignment('50000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$insert into public.assignments(event_service_id,freelancer_id) values('50000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001')$q$);
with changed as (update public.event_services set visibility='open',application_enabled=true where id='50000000-0000-4000-8000-000000000002' returning id) select pg_temp.check_true(not exists(select 1 from changed),'buyer raw publication denied');
select pg_temp.expect_denied($q$select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix')$q$);
select pg_temp.expect_denied($q$select public.create_contract_request('20000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','Forged buyer','',(now() at time zone 'America/Sao_Paulo')::date,null)$q$);
select pg_temp.check_true(not exists(select 1 from public.get_event_opportunities() where amount is not null),'buyer opportunity DTO has no worker cost');
select set_config('test.request_id' ,public.create_contract_request('20000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Assembly','Two days',(now() at time zone 'America/Sao_Paulo')::date+7,'Venue')::text,true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.new_event',public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id','30000000-0000-4000-8000-000000000001','name','New private work','venue','Venue','start_at',now()+interval '1 day','end_at',now()+interval '2 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'freelancer_unit_cost',220)))::text,true);
select pg_temp.check_true((current_setting('test.new_event')::jsonb->'services'->0->>'visibility')='private' and (current_setting('test.new_event')::jsonb->'services'->0->>'application_enabled')::boolean=false,'authorized provider creates private work by default');
select pg_temp.check_true((current_setting('test.new_event')::jsonb->'services'->0->>'contract_days')::integer=2 and (current_setting('test.new_event')::jsonb->'services'->0->>'freelancer_unit_cost')::numeric=220,'creation preserves supplied days and amount');
select set_config('test.quote_id',public.save_sale_quote(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','request_id',current_setting('test.request_id'),'title','Assembly','valid_until',(now() at time zone 'America/Sao_Paulo')::date+10,'payment_terms','Net 7','show_unit_prices',false), '[{"label":"Assembly","quantity":10,"contract_days":2,"client_unit_price":280,"freelancer_unit_cost":220}]')::text,true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.expect_denied(format('select public.get_sale_quote(%L)',current_setting('test.quote_id'))); -- buyer cannot see draft
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.submit_sale_quote(current_setting('test.quote_id')::uuid,1);
select pg_temp.expect_denied(format('select public.accept_sale_quote(%L,1)',current_setting('test.quote_id'))); -- provider cannot impersonate platform buyer
select pg_temp.check_true((public.get_sale_quote(current_setting('test.quote_id')::uuid)->>'client_total')::numeric=5600,'correct sale total');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(private.eventcore_can_manage_event('40000000-0000-4000-8000-000000000001'),'coordinator operations');
select pg_temp.check_true(public.get_event_operations('40000000-0000-4000-8000-000000000001')::text not like '%freelancer_unit_cost%' and public.get_event_operations('40000000-0000-4000-8000-000000000001')::text not like '%agreed_amount%','coordinator operational DTO excludes remuneration');
select pg_temp.check_true(not exists(select 1 from public.payments) and not exists(select 1 from public.assignments) and not exists(select 1 from public.event_services) and not exists(select 1 from public.event_financials),'coordinator raw finance tables denied');
select pg_temp.expect_denied($q$select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix')$q$);
select pg_temp.expect_denied($q$select public.set_organization_finance_member('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004',true)$q$);
select pg_temp.check_true(not private.eventcore_can_finance_event('40000000-0000-4000-8000-000000000001'),'coordinator finance denied');
select pg_temp.check_true(not exists(select 1 from public.proposals where id=current_setting('test.quote_id')::uuid),'raw quote coordinator denied');
select pg_temp.expect_denied(format('select public.get_sale_quote(%L)',current_setting('test.quote_id')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.set_organization_finance_member('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(private.eventcore_can_finance_event('40000000-0000-4000-8000-000000000001'),'explicit finance grant');
select pg_temp.check_true(exists(select 1 from public.payments where amount=440),'explicit finance reads remuneration');
select pg_temp.expect_denied($q$select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix')$q$); -- identity still required for new payment
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select pg_temp.expect_denied(format('select public.get_sale_quote(%L)',current_setting('test.quote_id')));
select pg_temp.check_true(not exists(select 1 from public.proposal_items where proposal_id=current_setting('test.quote_id')::uuid),'generic admin raw finance denied');
select pg_temp.expect_denied($q$select public.get_commercial_workspace('20000000-0000-4000-8000-000000000001')$q$);
select pg_temp.check_true(not exists(select 1 from public.contract_requests where id=current_setting('test.request_id')::uuid),'cross-org request invisible');
select public.configure_business_identity('{"organization_id":"20000000-0000-4000-8000-000000000003","display_name":"Other provider","organization_type":"company","market_role":"provider","document":"11.222.333/0001-81"}');
select pg_temp.check_true(exists(select 1 from public.organizations where id='20000000-0000-4000-8000-000000000003' and market_role='provider'),'classification only through authorized action');
select pg_temp.expect_error($q$select public.configure_business_identity('{"organization_id":"20000000-0000-4000-8000-000000000003","display_name":"Other buyer","organization_type":"company","market_role":"buyer","buyer_subtype":"agency","document":"11.222.333/0001-81"}')$q$,'market_role_locked');
select pg_temp.expect_denied(format('select public.save_sale_quote(jsonb_build_object(''organization_id'',''20000000-0000-4000-8000-000000000003'',''request_id'',%L,''title'',''Forged provider'',''valid_until'',(now() at time zone ''America/Sao_Paulo'')::date+1), ''[{"label":"Assembly","quantity":1,"contract_days":1,"client_unit_price":100}]''::jsonb)',current_setting('test.request_id')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.get_sale_quote(current_setting('test.quote_id')::uuid)::text not like '%freelancer_unit_cost%','buyer sale DTO');
select pg_temp.check_true(not exists(select 1 from public.proposal_items where proposal_id=current_setting('test.quote_id')::uuid),'buyer cannot read internal quote rows');
select pg_temp.expect_denied(format('select public.accept_sale_quote(%L,999)',current_setting('test.quote_id')));
select set_config('test.contract_id',public.accept_sale_quote(current_setting('test.quote_id')::uuid,1)::text,true);
select pg_temp.expect_denied(format('select public.accept_sale_quote(%L,1)',current_setting('test.quote_id')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select pg_temp.expect_denied(format('update public.proposals set client_total=1 where id=%L',current_setting('test.quote_id')));
select set_config('test.receipt_id',public.record_customer_receipt(current_setting('test.contract_id')::uuid,1000,'pix',(now() at time zone 'America/Sao_Paulo')::date,'fixture-receipt-1')::text,true);
select pg_temp.check_true(public.record_customer_receipt(current_setting('test.contract_id')::uuid,1000,'pix',(now() at time zone 'America/Sao_Paulo')::date,'fixture-receipt-1')::text=current_setting('test.receipt_id'),'receipt retry idempotency');
select pg_temp.expect_error(format('select public.record_customer_receipt(%L,1001,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''fixture-receipt-1'')',current_setting('test.contract_id')),'idempotency_conflict');
select pg_temp.expect_error(format('select public.record_customer_receipt(%L,5000,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''overpay'')',current_setting('test.contract_id')),'receipt_exceeds_receivable');
select pg_temp.check_true((public.get_commercial_workspace('20000000-0000-4000-8000-000000000001')->'contracts'->0->>'receivable_total')::numeric=4600,'sale receivable independent of wage');
select pg_temp.check_true((public.get_commercial_workspace('20000000-0000-4000-8000-000000000001')->'contracts'->0->>'sale_total')::numeric=5600,'contract snapshot');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(not exists(select 1 from public.commercial_contracts where id=current_setting('test.contract_id')::uuid),'cross tenant contract');
select pg_temp.check_true(not exists(select 1 from public.customer_receipts where contract_id=current_setting('test.contract_id')::uuid),'cross tenant receipt');
select pg_temp.expect_denied(format('select public.record_customer_receipt(%L,1,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''forged'')',current_setting('test.contract_id')));
-- External client requires no auth account; draft revision guards and acceptance evidence still apply.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.external_quote',public.save_sale_quote(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id','30000000-0000-4000-8000-000000000001','title','External quotation','valid_until',(now() at time zone 'America/Sao_Paulo')::date+10,'payment_terms','On delivery'), '[{"label":"External assembly","quantity":10,"contract_days":2,"client_unit_price":280,"freelancer_unit_cost":220}]')::text,true);
select pg_temp.expect_denied(format('select public.save_sale_quote(jsonb_build_object(''organization_id'',''20000000-0000-4000-8000-000000000001'',''id'',%L,''expected_revision'',99,''title'',''External revision'',''valid_until'',(now() at time zone ''America/Sao_Paulo'')::date+10), ''[{"label":"Assembly","quantity":1,"contract_days":1,"client_unit_price":100}]'')',current_setting('test.external_quote')));
select public.save_sale_quote(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','id',current_setting('test.external_quote'),'expected_revision',1,'title','External quotation','valid_until',(now() at time zone 'America/Sao_Paulo')::date+10), '[{"label":"External assembly","quantity":10,"contract_days":2,"client_unit_price":280,"freelancer_unit_cost":220}]');
select pg_temp.check_true((public.get_sale_quote(current_setting('test.external_quote')::uuid)->>'revision')::integer=2,'draft revision increments');
select pg_temp.expect_denied(format('select public.submit_sale_quote(%L,1)',current_setting('test.external_quote')));
select public.submit_sale_quote(current_setting('test.external_quote')::uuid,2);
select pg_temp.expect_denied(format('select public.accept_sale_quote(%L,2)',current_setting('test.external_quote')));
select set_config('test.external_contract',public.accept_sale_quote(current_setting('test.external_quote')::uuid,2,'Client confirmed acceptance by signed message')::text,true);
select pg_temp.check_true((public.get_sale_quote(current_setting('test.external_quote')::uuid)->>'client_total')::numeric=5600,'external accepted total');
select pg_temp.check_true(exists(select 1 from public.commercial_contracts where id=current_setting('test.external_contract')::uuid and buyer_organization_id is null and acceptance_method='external_recorded'),'external contract has no buyer account');
select pg_temp.expect_error($q$select public.create_event_assignment('50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','invited','NaN'::numeric)$q$,'invalid_assignment');
select pg_temp.expect_error($q$select public.set_assignment_amount('70000000-0000-4000-8000-000000000001',1.001)$q$,'invalid_payment_amount');
select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.expect_denied(format('select public.get_sale_quote(%L)',current_setting('test.external_quote')));
select pg_temp.expect_denied(format('select public.record_customer_receipt(%L,1,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''buyer-record'')',current_setting('test.contract_id')));
-- Own worker history includes own agreed total, never another participant's wage or provider sales.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.check_true((select count(*)=1 from public.assignments) and (select count(*)=1 from public.payments),'worker own assignment/payment');
select pg_temp.check_true((select amount=440 and status='paid' from public.payments where assignment_id='70000000-0000-4000-8000-000000000001'),'historical agreed total stays 440');
select pg_temp.check_true(jsonb_array_length(public.get_my_schedule()->'services')=1 and public.get_my_schedule()::text not like '%freelancer_unit_cost%','sanitized own worker schedule');
select pg_temp.check_true(not exists(select 1 from public.commercial_contracts) and not exists(select 1 from public.proposals),'worker no company sales');
select pg_temp.check_true(not exists(select 1 from public.assignments where freelancer_id='60000000-0000-4000-8000-000000000002') and not exists(select 1 from public.payments where assignment_id='70000000-0000-4000-8000-000000000002'),'worker cannot read colleague wages on the same service');
with changed as (delete from public.freelancers where id='60000000-0000-4000-8000-000000000001' returning id) select pg_temp.check_true(not exists(select 1 from changed),'worker cannot unlink identity by deleting its row');
select pg_temp.expect_denied($q$insert into public.freelancers(profile_id,full_name) values('10000000-0000-4000-8000-000000000005','Reinserted worker')$q$);
select pg_temp.check_true(exists(select 1 from public.freelancers where id='60000000-0000-4000-8000-000000000001' and profile_id=auth.uid()),'original worker link survives attacks');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000007',true);
select pg_temp.check_true((select count(*)=1 from public.assignments) and (select count(*)=1 from public.payments) and (select amount=660 from public.payments where assignment_id='70000000-0000-4000-8000-000000000002'),'colleague sees only own wage');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000010',true);
select public.complete_profile(jsonb_build_object('profile_type','freelancer','full_name','Self-onboarded worker','document','390.533.447-05','specialty_ids',jsonb_build_array((select id from public.specialties where active order by id limit 1))));
select pg_temp.check_true(exists(select 1 from public.freelancers where profile_id=auth.uid()),'verified worker self-onboarding creates its own immutable link');
select public.complete_profile(jsonb_build_object('profile_type','freelancer','full_name','Updated self worker','document','390.533.447-05','specialty_ids',jsonb_build_array((select id from public.specialties where active order by id limit 1))));
select pg_temp.check_true(exists(select 1 from public.freelancers where profile_id=auth.uid() and full_name='Updated self worker'),'verified linked worker metadata update retained');
-- Existing complete_profile signature accepts the unified CPF field for a company responsible.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',true);
select public.complete_profile(jsonb_build_object('profile_type','company','full_name','Legacy responsible','organization_name','Legacy company','document','123.456.789-09','specialty_ids',jsonb_build_array((select id from public.specialties where active order by id limit 1))));
select pg_temp.check_true((public.get_commercial_context()->>'identity_complete')::boolean and (public.get_commercial_context()->>'document_type')='cpf','company responsible accepts unified CPF');
select pg_temp.check_true(not exists(select 1 from public.organizations where owner_profile_id=auth.uid() and market_role<>'unclassified'),'old profile payload does not infer market role');
select pg_temp.check_true(private.eventcore_can_manage_event('40000000-0000-4000-8000-000000000002'),'profile completion preserves legacy event access');
-- Verify immutable triggers independently of authenticated grant revocation.
reset role;
select pg_temp.expect_error($q$update public.freelancers set profile_id='10000000-0000-4000-8000-000000000006' where id='60000000-0000-4000-8000-000000000001'$q$,'freelancer_ownership_is_immutable'); -- definer authority cannot rebind an authenticated actor's identity
select pg_temp.expect_error(format('update public.proposals set client_total=1 where id=%L',current_setting('test.quote_id')),'quote_immutable');
select pg_temp.expect_error(format('update public.proposal_items set client_unit_price=1 where proposal_id=%L',current_setting('test.quote_id')),'quote_immutable');
select pg_temp.expect_error(format('update public.commercial_contracts set sale_total=1 where id=%L',current_setting('test.contract_id')),'commercial_record_immutable');
select pg_temp.expect_error(format('delete from public.customer_receipts where id=%L',current_setting('test.receipt_id')),'commercial_record_immutable');
rollback;
