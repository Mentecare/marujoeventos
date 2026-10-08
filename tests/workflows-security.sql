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
select pg_temp.check_true(private.eventcore_business_date('2026-10-07T00:54:00Z'::timestamptz)='2026-10-06'::date,'00:54 UTC is still the previous Brazilian business day');
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
-- Ten independent worker participants for the exact approved totals; no real accounts.
insert into auth.users(id,email,raw_user_meta_data) select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'workflow-worker-'||i||'@example.invalid','{}'::jsonb from generate_series(11,20) i;
update public.profiles set profile_type='freelancer',onboarding_completed=true where id in (select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid from generate_series(11,20) i);
insert into public.freelancers(id,profile_id,full_name) select ('60000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Worker '||i from generate_series(11,20) i;
insert into public.profile_specialties(profile_id,specialty_id) select p.id,(select id from public.specialties where active order by id limit 1) from public.profiles p where p.profile_type='freelancer';
insert into public.profile_photos(id,profile_id,kind,slot,object_path,byte_size,caption,real_declared) values
('99000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','portfolio',1,'10000000-0000-4000-8000-000000000001/99000000-0000-4000-8000-000000000001.webp',1024,'Provider real work',true),
('99000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005','portfolio',1,'10000000-0000-4000-8000-000000000005/99000000-0000-4000-8000-000000000002.webp',1024,'Worker real work',true);
set local role authenticated;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
-- I2 exact owner raw-write probe: initial functions and deletion are immutable.
select pg_temp.expect_error($q$update public.event_services set label='Changed after creation',quantity_needed=20,freelancer_unit_cost=999 where id='50000000-0000-4000-8000-000000000001'$q$,'function_conditions_creation_only');
select pg_temp.expect_error($q$delete from public.event_services where id='50000000-0000-4000-8000-000000000001'$q$,'function_conditions_creation_only');
-- I3 actual completed historical assignment/payment amounts cannot change.
update public.events set start_at=now()-interval '3 days',end_at=now()-interval '1 day',status='completed' where id='40000000-0000-4000-8000-000000000001';
select pg_temp.expect_error($q$select public.set_assignment_amount('70000000-0000-4000-8000-000000000001',999)$q$,'historical_agreement_immutable');
select pg_temp.check_true((select agreed_amount=440 from public.assignments where id='70000000-0000-4000-8000-000000000001') and (select amount=440 from public.payments where assignment_id='70000000-0000-4000-8000-000000000001'),'I3 original historical 440 agreement/payment preserved');
select set_config('test.external_client',public.create_external_work_client('20000000-0000-4000-8000-000000000001','External customer without account')::text,true);
select set_config('test.work',public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id',current_setting('test.external_client'),'name','Private WhatsApp work','venue','Venue','origin','whatsapp','start_at',now()+interval '1 day','end_at',now()+interval '2 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220,'benefits','Meals and transport','additions',0,'deductions',0)))::text,true);
select set_config('test.event',(current_setting('test.work')::jsonb->'event'->>'id'),true);
select set_config('test.service',(current_setting('test.work')::jsonb->'services'->0->>'id'),true);
select pg_temp.check_true((current_setting('test.work')::jsonb->'event'->>'origin')='whatsapp' and (current_setting('test.work')::jsonb->'services'->0->>'visibility')='private' and (current_setting('test.work')::jsonb->'services'->0->>'freelancer_unit_cost')::numeric=440,'origin independent from private visibility; 220 daily x2 = 440 worker total');
select public.set_provider_base_member('20000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001',true);
select public.set_provider_base_member('20000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002',true);
select set_config('test.team',public.save_provider_team('20000000-0000-4000-8000-000000000001',null,'Habitual team')::text,true);
select public.set_provider_team_member(current_setting('test.team')::uuid,'60000000-0000-4000-8000-000000000001',true);
select public.set_provider_base_member('20000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000020',true);
select pg_temp.expect_denied($q$select public.get_profile_photo_collection('60000000-0000-4000-8000-000000000020')$q$);
select pg_temp.check_true(jsonb_array_length(public.get_provider_people('20000000-0000-4000-8000-000000000001')->'base')=3 and jsonb_array_length(public.get_provider_worker_history('20000000-0000-4000-8000-000000000001'))=0,'base/team membership creates no history or allocation');
select pg_temp.check_keys(public.get_provider_people('20000000-0000-4000-8000-000000000001'),array['base','teams'],'people DTO root keys');
select pg_temp.check_keys(public.get_provider_people('20000000-0000-4000-8000-000000000001')->'base'->0,array['freelancer_id','full_name','city','active'],'base DTO excludes contacts/documents/wages');
select pg_temp.check_keys(public.get_provider_people('20000000-0000-4000-8000-000000000001')->'teams'->0,array['id','name','freelancer_ids'],'reusable team DTO keys');
select set_config('test.assignment',public.create_event_assignment(current_setting('test.service')::uuid,'60000000-0000-4000-8000-000000000001')::text,true);
select pg_temp.check_true(jsonb_array_length(public.get_profile_photo_collection('60000000-0000-4000-8000-000000000001'))=1,'legitimate provider retains worker portfolio');
select pg_temp.check_true((select count(*)=1 from public.assignments where event_service_id=current_setting('test.service')::uuid),'invitation only selected recipient');
select pg_temp.expect_error(format('select public.create_event_assignment(%L,''60000000-0000-4000-8000-000000000002'',''confirmed'')',current_setting('test.service')),'worker_acceptance_required');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(public.get_event_operations(current_setting('test.event')::uuid)->'services'->0 ? 'planned_hours','coordinator sees operational hours without remuneration');
select pg_temp.check_true(public.get_event_operations(current_setting('test.event')::uuid)::text not like '%remuneration%' and public.get_event_operations(current_setting('test.event')::uuid)::text not like '%agreed_amount%','coordinator has no rates');
select pg_temp.expect_denied(format('select public.get_event_remunerations(%L)',current_setting('test.event')));
select pg_temp.expect_denied(format('select public.get_work_finance(%L)',current_setting('test.event')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000007',true);
select pg_temp.check_true(not exists(select 1 from public.assignments where id=current_setting('test.assignment')::uuid),'uninvited colleague cannot read invite');
select pg_temp.expect_denied(format('select public.accept_assignment_terms((select id from public.assignment_terms where assignment_id=%L limit 1))',current_setting('test.assignment')));
select pg_temp.check_true(not exists(select 1 from public.get_event_opportunities() where service_id=current_setting('test.service')::uuid),'private job absent from marketplace');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.check_true((public.get_my_work_assignments()->0->'offered_terms'->>'total')::numeric=440 and jsonb_array_length(public.get_my_work_assignments())=2,'worker sees own initial conditions and legacy own work');
select pg_temp.check_keys(public.get_my_work_assignments()->0,array['id','worker_name','can_review','freelancer_id','event_service_id','event_id','event_name','venue','start_at','end_at','event_status','status','function_name','legacy_agreed_amount','offered_terms','accepted_terms','terms_history','payments','completion_confirmed'],'own worker DTO exact adapter keys');
select pg_temp.check_keys(public.get_my_work_assignments()->0->'offered_terms',array['id','assignment_id','revision','basis','rate','contract_days','planned_hours','benefits','additions','deductions','total','created_at','accepted_at'],'term DTO always includes nullable conditions');
select public.respond_to_assignment(current_setting('test.assignment')::uuid,'confirmed');
select pg_temp.check_true((public.get_my_work_assignments()->0->'accepted_terms'->>'total')::numeric=440,'availability acceptance records remuneration acceptance');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error(format('select public.set_assignment_amount(%L,999)',current_setting('test.assignment')),'remuneration_revision_required');
select pg_temp.expect_error(format('select public.propose_assignment_terms(%L,''{"basis":"daily","rate":230,"contract_days":3}'')',current_setting('test.assignment')),'invalid_remuneration');
select set_config('test.revision',public.propose_assignment_terms(current_setting('test.assignment')::uuid,'{"basis":"daily","rate":230,"contract_days":2,"benefits":"Meals and transport","additions":0,"deductions":0}')::text,true);
select pg_temp.check_true((public.get_event_remunerations(current_setting('test.event')::uuid)->0->'accepted_terms'->>'total')::numeric=440 and (public.get_event_remunerations(current_setting('test.event')::uuid)->0->'offered_terms'->>'total')::numeric=460,'provider finance separates accepted/offered per-assignment terms');
select pg_temp.check_true((public.get_work_finance(current_setting('test.event')::uuid)->>'labor_contracted')::numeric=440,'pending revision never becomes payable');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select public.accept_assignment_terms(current_setting('test.revision')::uuid);
select pg_temp.check_true((public.get_my_work_assignments()->0->'accepted_terms'->>'total')::numeric=460 and (select agreed_amount=440 from public.assignments where id=current_setting('test.assignment')::uuid),'accepted revision separate; original amount untouched');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.mark_assignment_paid(current_setting('test.assignment')::uuid,'pix');
select pg_temp.check_true((public.get_work_finance(current_setting('test.event')::uuid)->>'labor_paid')::numeric=460,'payment uses explicitly accepted 460');
select pg_temp.expect_error(format('select public.propose_assignment_terms(%L,''{"basis":"service","rate":999,"contract_days":2}'')',current_setting('test.assignment')),'agreement_closed');
-- Completion requires actual participant evidence; future work cannot generate a history/review.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error(format('select public.confirm_assignment_completion(%L)',current_setting('test.assignment')),'completed_event_required');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
update public.events set start_at=now()-interval '3 days',end_at=now()-interval '1 day',status='completed' where id=current_setting('test.event')::uuid;
select pg_temp.check_true(jsonb_array_length(public.get_provider_worker_history('20000000-0000-4000-8000-000000000001'))=0,'registered completed event alone is not evidence');
select pg_temp.expect_error(format('select public.submit_assignment_rating(%L,5,''Great'')',current_setting('test.assignment')),'confirmed_completed_work_required');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select public.confirm_assignment_completion(current_setting('test.assignment')::uuid);
reset role;
insert into public.organization_members(organization_id,profile_id,member_role) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005','manager');
set local role authenticated;
select pg_temp.expect_error(format('select public.submit_assignment_rating(%L,5,''Self review'')',current_setting('test.assignment')),'self_review_not_allowed');
reset role;
delete from public.organization_members where organization_id='20000000-0000-4000-8000-000000000001' and profile_id='10000000-0000-4000-8000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select pg_temp.check_true((public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0->>'job_count')::int=1 and (public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0->'punctuality')='null'::jsonb,'participant-confirmed actual external work; no invented punctuality');
select public.submit_assignment_rating(current_setting('test.assignment')::uuid,5,'Great');
select pg_temp.expect_error(format('select public.submit_assignment_rating(%L,4,''Again'')',current_setting('test.assignment')),'assignment_already_rated');
select pg_temp.check_true((public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0->>'average_stars')::numeric=5,'real worker review');
select pg_temp.check_keys(public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0,array['freelancer_id','full_name','city','job_count','average_stars','review_count','punctuality','punctuality_count'],'worker history exact evidence DTO keys');
-- Platform application -> hire remains the canonical flow; hire is an invitation, not consent.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select set_config('test.request',public.create_contract_request('20000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Full example','Two days',(now() at time zone 'America/Sao_Paulo')::date+3,'Venue')::text,true);
select pg_temp.check_true(public.get_provider_presentation('20000000-0000-4000-8000-000000000001')->'average_stars'='null'::jsonb,'provider with no reviews has null stars');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.quote',public.save_sale_quote(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','request_id',current_setting('test.request'),'title','Full example','valid_until',(now() at time zone 'America/Sao_Paulo')::date),'[{"label":"Assembly","quantity":10,"contract_days":2,"client_unit_price":280,"freelancer_unit_cost":220}]')::text,true);
select public.submit_sale_quote(current_setting('test.quote')::uuid,1);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select set_config('test.contract',public.accept_sale_quote(current_setting('test.quote')::uuid,1)::text,true);
select pg_temp.check_true(jsonb_array_length(public.get_buyer_provider_history('20000000-0000-4000-8000-000000000002'))=0,'accepted contract alone creates no buyer history');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select public.configure_business_identity('{"organization_id":"20000000-0000-4000-8000-000000000003","display_name":"Other provider","organization_type":"company","market_role":"provider","document":"11222333000181"}');
select set_config('test.foreign_client',public.create_external_work_client('20000000-0000-4000-8000-000000000003','Other client')::text,true);
select pg_temp.expect_denied(format('insert into public.events(client_id,organization_id,created_by_profile_id,coordinator_id,commercial_contract_id,name,venue,start_at,end_at) values(%L,''20000000-0000-4000-8000-000000000003'',auth.uid(),auth.uid(),%L,''Forged contract event'',''Venue'',now(),now()+interval ''1 day'')',current_setting('test.foreign_client'),current_setting('test.contract')));

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.full',public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id',(select client_id from public.commercial_contracts where id=current_setting('test.contract')::uuid),'commercial_contract_id',current_setting('test.contract'),'origin','platform','name','Full example','venue','Venue','start_at',now()+interval '1 day','end_at',now()+interval '2 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220,'open_marketplace',true)))::text,true);
select set_config('test.full_event',(current_setting('test.full')::jsonb->'event'->>'id'),true);
select set_config('test.full_service',(current_setting('test.full')::jsonb->'services'->0->>'id'),true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000011',true);
select pg_temp.check_true((select event_name<>'Full example' and venue<>'Venue' and requirements is null from public.get_event_opportunities() where service_id=current_setting('test.full_service')::uuid),'published function never exposes private job name/address/requirements');
select pg_temp.check_true((select (x->'remuneration'->>'rate')::numeric=220 and (x->'remuneration'->>'total')::numeric=440 from jsonb_array_elements(public.get_work_opportunities()) x where x->>'service_id'=current_setting('test.full_service')),'eligible worker opportunity has initial 220/day offer total440, no actual colleague wages');
select pg_temp.check_keys((select x from jsonb_array_elements(public.get_work_opportunities()) x where x->>'service_id'=current_setting('test.full_service')),array['service_id','event_id','event_name','start_at','end_at','venue','function_name','specialty_id','vacancies','amount','contractor_name','requirements','event_status','compatible','contract_days','remuneration'],'opportunity exact sanitized DTO keys');
select pg_temp.check_keys((select x->'remuneration' from jsonb_array_elements(public.get_work_opportunities()) x where x->>'service_id'=current_setting('test.full_service')),array['basis','rate','contract_days','planned_hours','benefits','additions','deductions','total'],'opportunity remuneration exact required nullable keys');
select set_config('test.application',public.apply_for_opportunity(current_setting('test.full_service')::uuid,'Available')::text,true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.hired',public.hire_application(current_setting('test.application')::uuid)::text,true);
select pg_temp.check_true((select status='invited' from public.assignments where id=current_setting('test.hired')::uuid),'application hire does not fabricate availability acceptance');
select public.invite_selected_workers(current_setting('test.full_service')::uuid,array(select ('60000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid from generate_series(12,20) i));
do $$ declare i integer; aid uuid; begin
 for i in 11..20 loop
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-'||lpad(i::text,12,'0'),true);
  select id into aid from public.assignments where event_service_id=current_setting('test.full_service')::uuid;
  perform public.respond_to_assignment(aid,'confirmed');
  perform pg_temp.check_true((public.get_my_work_assignments()->0->'accepted_terms'->>'total')::numeric=440 and jsonb_array_length(public.get_my_work_assignments())=1,'each worker sees own 440 only');
  perform pg_temp.check_true(not exists(select 1 from public.commercial_contracts),'worker has no sale contract');
 end loop;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.record_customer_receipt(current_setting('test.contract')::uuid,1000,'pix',(now() at time zone 'America/Sao_Paulo')::date,'full-receipt');
select public.mark_assignment_paid(current_setting('test.hired')::uuid,'pix');
select pg_temp.check_true((public.get_work_finance(current_setting('test.full_event')::uuid)->>'sale_contracted')::numeric=5600 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'sale_received')::numeric=1000 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'sale_receivable')::numeric=4600,'sale 5600, real received1000, receivable4600');
select pg_temp.check_true((public.get_work_finance(current_setting('test.full_event')::uuid)->>'labor_contracted')::numeric=4400 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'labor_paid')::numeric=440 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'labor_payable')::numeric=3960 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'estimated_result')::numeric=1200,'labor4400, actual paid440, payable3960, estimated1200 before expenses/taxes');
select pg_temp.check_keys(public.get_work_finance(current_setting('test.full_event')::uuid),array['event_id','sale_source','sale_contracted','sale_received','sale_receivable','sale_deductions','labor_contracted','labor_paid','labor_payable','unknown_labor_count','other_contracted','other_paid','other_payable','unknown_expense_count','estimated_result','result_label','expenses'],'finance exact source/unknown DTO keys');
select set_config('test.expense',public.record_work_expense(current_setting('test.full_event')::uuid,'Transport',200,'Receipt #1')::text,true);
select public.record_work_expense_payment(current_setting('test.expense')::uuid,50,'pix',(now() at time zone 'America/Sao_Paulo')::date,'transport-1');
select pg_temp.check_true((public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_contracted')::numeric=200 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_paid')::numeric=50 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_payable')::numeric=150 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'estimated_result')::numeric=1000,'expense reporting has distinct contract/paid/payable sources');
select pg_temp.expect_error(format('select public.record_work_expense_payment(%L,151,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''overpay'')',current_setting('test.expense')),'expense_exceeds_payable');
select pg_temp.check_true(public.record_work_expense_payment(current_setting('test.expense')::uuid,50,'pix',(now() at time zone 'America/Sao_Paulo')::date,'transport-1')=(select id from public.work_expense_payments where expense_id=current_setting('test.expense')::uuid),'expense retry returns prior payment without duplicate');
select pg_temp.expect_error(format('select public.record_work_expense_payment(%L,51,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''transport-1'')',current_setting('test.expense')),'idempotency_conflict');
select pg_temp.check_keys(public.get_work_finance(current_setting('test.full_event')::uuid)->'expenses'->0,array['id','label','amount','receipt_reference','paid'],'expense DTO separates receipt and paid evidence');
select pg_temp.check_true(public.get_work_finance('40000000-0000-4000-8000-000000000001')->'sale_received'='null'::jsonb,'historical gross never fabricated as receipt');
select pg_temp.check_true((select rating is null and review_count=0 from public.get_professional_directory() where freelancer_id='60000000-0000-4000-8000-000000000002'),'cached default5 is not earned reputation');
-- Authentic current attendance provides measured punctuality; availability is not attendance.
update public.events set start_at=now()-interval '3 hours',end_at=now()-interval '1 hour' where id=current_setting('test.full_event')::uuid;
select public.record_assignment_attendance(current_setting('test.hired')::uuid,'in',-22,-43);
select public.record_assignment_attendance(current_setting('test.hired')::uuid,'out',-22,-43);
select public.validate_assignment_attendance(current_setting('test.hired')::uuid);
select pg_temp.expect_error(format('update public.events set start_at=now() where id=%L',current_setting('test.full_event')),'recorded_schedule_immutable');
select public.complete_work_event(current_setting('test.full_event')::uuid);
select pg_temp.check_true((public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0->>'punctuality_count')::integer=1 and (public.get_provider_worker_history('20000000-0000-4000-8000-000000000001')->0->>'punctuality')::numeric=0,'late server-recorded validated attendance outranks unmeasured history; no backdated punctuality');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(not exists(select 1 from jsonb_array_elements(public.get_work_opportunities()) x where x->'remuneration'<>'null'::jsonb),'buyer opportunity has no remuneration condition DTO');
select pg_temp.check_true(public.get_buyer_work_status(current_setting('test.contract')::uuid)::text not like '%agreed_amount%' and public.get_buyer_work_status(current_setting('test.contract')::uuid)::text not like '%freelancer_unit_cost%','buyer sale+execution excludes all wage/cost values');
select pg_temp.check_keys(public.get_buyer_work_status(current_setting('test.contract')::uuid),array['contract_id','sale_total','quote','received_total','work'],'buyer status exact sale-only root keys');
select pg_temp.check_keys(public.get_buyer_work_status(current_setting('test.contract')::uuid)->'work',array['event_id','name','venue','start_at','end_at','status','completion_confirmed','reviewed','can_confirm'],'buyer execution excludes worker identities');
select pg_temp.check_true(not exists(select 1 from public.assignment_terms) and not exists(select 1 from public.workforce_payments) and not exists(select 1 from public.work_expenses),'buyer raw worker finance denied');
select pg_temp.expect_error(format('select public.submit_provider_rating(%L,5,''Great'')',current_setting('test.contract')),'confirmed_completed_work_required');
select public.confirm_contract_completion(current_setting('test.contract')::uuid);
-- A buyer who is also a provider member cannot review their own provider.
reset role;
insert into public.organization_members(organization_id,profile_id,member_role) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','member');
set local role authenticated;
select pg_temp.expect_denied(format('select public.submit_provider_rating(%L,5,''Self provider'')',current_setting('test.contract')));
reset role;
delete from public.organization_members where organization_id='20000000-0000-4000-8000-000000000001' and profile_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select public.submit_provider_rating(current_setting('test.contract')::uuid,4,'Actual completed service');
select pg_temp.expect_error(format('select public.submit_provider_rating(%L,5,''Again'')',current_setting('test.contract')),'provider_already_rated');
select pg_temp.check_true((public.get_buyer_provider_history('20000000-0000-4000-8000-000000000002')->0->>'job_count')::integer=1 and (public.get_buyer_provider_history('20000000-0000-4000-8000-000000000002')->0->>'average_stars')::numeric=4,'buyer provider history has real completion and separate stars');
select pg_temp.check_keys(public.get_buyer_provider_history('20000000-0000-4000-8000-000000000002')->0,array['organization_id','display_name','job_count','average_stars','review_count'],'provider history exact evidence DTO keys');
select pg_temp.check_keys(public.get_provider_presentation('20000000-0000-4000-8000-000000000001'),array['id','display_name','organization_type','bio','specialties','average_stars','review_count','job_count'],'provider presentation allowlists presentation only');
select pg_temp.check_true(jsonb_array_length(public.get_provider_photo_collection('20000000-0000-4000-8000-000000000001'))=1,'eligible buyer can view actual provider portfolio metadata');
select pg_temp.expect_denied($q$select public.get_profile_photo_collection('60000000-0000-4000-8000-000000000001')$q$);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select pg_temp.expect_denied($q$select public.get_provider_presentation('20000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$select public.get_provider_photo_collection('20000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$select public.get_profile_photo_collection('60000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$select public.get_professional_reputation('60000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$select public.get_provider_people('20000000-0000-4000-8000-000000000001')$q$);
select pg_temp.check_true(not exists(select 1 from public.profile_photos),'unrelated generic admin cannot raw-read private portfolios');
select pg_temp.check_true(not exists(select 1 from public.provider_freelancer_base) and not exists(select 1 from public.assignment_terms),'private base/terms cannot leak to generic admin');
-- Reusable-team deletion/removal does not erase historical assignments or reviews.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.set_provider_base_member('20000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001',false);
select public.delete_provider_team(current_setting('test.team')::uuid);
select pg_temp.check_true(jsonb_array_length(public.get_provider_worker_history('20000000-0000-4000-8000-000000000001'))=2,'removing base/team leaves actual history');
select pg_temp.expect_error(format('update public.events set status=''planning'' where id=%L',current_setting('test.full_event')),'completed_event_immutable');
select pg_temp.expect_error(format('select public.publish_work_function(%L,false)',current_setting('test.full_service')),'event_closed');
select set_config('test.unknown_expense',public.record_work_expense(current_setting('test.full_event')::uuid,'Tax unresolved',null)::text,true);
select pg_temp.check_true(public.get_work_finance(current_setting('test.full_event')::uuid)->'other_contracted'='null'::jsonb and public.get_work_finance(current_setting('test.full_event')::uuid)->'other_payable'='null'::jsonb and public.get_work_finance(current_setting('test.full_event')::uuid)->'estimated_result'='null'::jsonb and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'unknown_expense_count')::integer=1,'unresolved expense keeps contracted/payable/result unknown');
select pg_temp.expect_error(format('select public.record_work_expense_payment(%L,1,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''unknown-expense'')',current_setting('test.unknown_expense')),'expense_amount_unknown');
-- Unknown evidence remains immutable, a single effective resolution becomes payable.
select set_config('test.resolution',public.resolve_work_expense(current_setting('test.unknown_expense')::uuid,100,'Invoice tax 1')::text,true);
select pg_temp.check_true(public.resolve_work_expense(current_setting('test.unknown_expense')::uuid,100,'Invoice tax 1')::text=current_setting('test.resolution'),'resolution retry is idempotent');
select pg_temp.expect_error(format('select public.resolve_work_expense(%L,101,''Invoice tax 1'')',current_setting('test.unknown_expense')),'expense_already_resolved');
select public.record_work_expense_payment(current_setting('test.unknown_expense')::uuid,100,'pix',(now() at time zone 'America/Sao_Paulo')::date,'resolved-payment');
select public.record_work_expense_payment(current_setting('test.unknown_expense')::uuid,100,'pix',(now() at time zone 'America/Sao_Paulo')::date,'resolved-payment');
select pg_temp.check_true((public.get_work_finance(current_setting('test.full_event')::uuid)->>'unknown_expense_count')::integer=0 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_contracted')::numeric=300 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_paid')::numeric=150 and (public.get_work_finance(current_setting('test.full_event')::uuid)->>'other_payable')::numeric=150,'effective expense counted/paid once');
select pg_temp.expect_error(format('select public.record_work_expense_payment(%L,1,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''resolved-overpay'')',current_setting('test.unknown_expense')),'expense_exceeds_payable');
-- Previously external work without contract can acquire an audited sale and real receipt.
select set_config('test.sale',public.record_work_sale(current_setting('test.event')::uuid,1000,'External quote accepted 1')::text,true);
select pg_temp.check_true(public.record_work_sale(current_setting('test.event')::uuid,1000,'External quote accepted 1')::text=current_setting('test.sale'),'sale retry stable');
select pg_temp.expect_error(format('select public.record_work_sale(%L,1001,''External quote accepted 1'')',current_setting('test.event')),'sale_already_recorded');
select set_config('test.receipt',public.record_work_sale_receipt(current_setting('test.event')::uuid,250,'pix',(now() at time zone 'America/Sao_Paulo')::date,'external-receipt-1')::text,true);
select pg_temp.check_true(public.record_work_sale_receipt(current_setting('test.event')::uuid,250,'pix',(now() at time zone 'America/Sao_Paulo')::date,'external-receipt-1')::text=current_setting('test.receipt'),'receipt retry stable');
select pg_temp.check_true((public.get_work_finance(current_setting('test.event')::uuid)->>'sale_contracted')::numeric=1000 and (public.get_work_finance(current_setting('test.event')::uuid)->>'sale_received')::numeric=250 and (public.get_work_finance(current_setting('test.event')::uuid)->>'sale_receivable')::numeric=750,'external sale lifecycle finance projection');
select pg_temp.expect_error(format('select public.record_work_sale_receipt(%L,751,''pix'',(now() at time zone ''America/Sao_Paulo'')::date,''overpay-sale'')',current_setting('test.event')),'receipt_exceeds_receivable');
-- Late contract linking must share the one-event invariant with original creation.
select set_config('test.late_quote',public.save_sale_quote(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id',current_setting('test.external_client'),'title','Later external quote','valid_until',(now() at time zone 'America/Sao_Paulo')::date),'[{"label":"Accepted external work","quantity":1,"contract_days":1,"client_unit_price":1000}]')::text,true);
select public.submit_sale_quote(current_setting('test.late_quote')::uuid,1);
select set_config('test.late_contract',public.accept_sale_quote(current_setting('test.late_quote')::uuid,1,'External accepted quotation evidence')::text,true);
select set_config('test.late_event',(public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id',current_setting('test.external_client'),'name','Work awaiting quote','venue','Venue','start_at',now()+interval '1 day','end_at',now()+interval '2 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',1,'contract_days',1,'remuneration_basis','daily','remuneration_rate',100)))->'event'->>'id'),true);
select public.link_work_sale_contract(current_setting('test.late_event')::uuid,current_setting('test.late_contract')::uuid);
select public.link_work_sale_contract(current_setting('test.late_event')::uuid,current_setting('test.late_contract')::uuid);
select public.record_work_sale_receipt(current_setting('test.late_event')::uuid,250,'pix',(now() at time zone 'America/Sao_Paulo')::date,'late-contract-receipt');
select pg_temp.check_true((public.get_work_finance(current_setting('test.late_event')::uuid)->>'sale_source')='accepted_contract' and (public.get_work_finance(current_setting('test.late_event')::uuid)->>'sale_receivable')::numeric=750 and (select commercial_contract_id is null from public.events where id=current_setting('test.late_event')::uuid),'late link uses immutable contract/receipts without changing original event');
select pg_temp.expect_error(format('insert into public.events(client_id,organization_id,created_by_profile_id,coordinator_id,commercial_contract_id,name,venue,start_at,end_at) values(%L,''20000000-0000-4000-8000-000000000001'',auth.uid(),auth.uid(),%L,''Duplicate contract work'',''Venue'',now(),now()+interval ''1 day'')',current_setting('test.external_client'),current_setting('test.late_contract')),'sale_already_linked');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.get_buyer_work_status(current_setting('test.contract')::uuid)->'work'->>'event_id'=current_setting('test.full_event'),'original contract status remains unchanged');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select pg_temp.expect_denied(format('select public.resolve_work_expense(%L,100,''forged tenant'')',current_setting('test.unknown_expense')));
select pg_temp.expect_denied(format('select public.record_work_sale(%L,1000,''forged tenant'')',current_setting('test.event')));
select pg_temp.expect_denied(format('select public.link_work_sale_contract(%L,%L)',current_setting('test.late_event'),current_setting('test.late_contract')));
select pg_temp.expect_denied(format('insert into public.work_contract_links(event_id,contract_id,recorded_by) values(%L,%L,auth.uid())',current_setting('test.late_event'),current_setting('test.late_contract')));
select pg_temp.expect_denied(format('select public.record_work_sale_receipt(%L,1,''pix'',current_date,''forged'')',current_setting('test.event')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select pg_temp.expect_denied(format('select public.resolve_work_expense(%L,100,''operator'')',current_setting('test.unknown_expense')));
select pg_temp.expect_denied(format('select public.record_work_sale(%L,1000,''operator'')',current_setting('test.event')));
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.expect_denied(format('select public.resolve_work_expense(%L,100,''worker'')',current_setting('test.unknown_expense')));
select pg_temp.check_true(not exists(select 1 from public.work_expense_resolutions) and not exists(select 1 from public.work_sale_entries) and not exists(select 1 from public.work_sale_receipts) and not exists(select 1 from public.work_contract_links),'worker raw finance evidence denied');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select pg_temp.check_true((select amount is null and receipt_reference is null from public.work_expenses where id=current_setting('test.unknown_expense')::uuid),'original unknown expense unchanged');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error(format('update public.assignments set status=''cancelled'' where id=%L',current_setting('test.assignment')),'completed_assignment_immutable');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
-- Exact I3 raw bypass probes apply even with definer authority and an authenticated actor.
reset role;
select pg_temp.expect_error($q$update public.assignments set agreed_amount=999 where id='70000000-0000-4000-8000-000000000001'$q$,'historical_agreement_immutable');
select pg_temp.expect_error($q$update public.payments set amount=999 where assignment_id='70000000-0000-4000-8000-000000000001'$q$,'historical_payment_immutable');
select pg_temp.expect_error(format('update public.assignment_terms set total=999 where assignment_id=%L',current_setting('test.assignment')),'commercial_record_immutable');
select pg_temp.expect_error(format('delete from public.assignment_term_acceptances where term_id=%L',current_setting('test.revision')),'commercial_record_immutable');
select pg_temp.expect_error(format('update public.workforce_payments set amount=999 where assignment_id=%L',current_setting('test.assignment')),'commercial_record_immutable');
select pg_temp.expect_error(format('delete from public.ratings where assignment_id=%L',current_setting('test.assignment')),'commercial_record_immutable');
select pg_temp.expect_error(format('delete from public.provider_ratings where contract_id=%L',current_setting('test.contract')),'commercial_record_immutable');
select pg_temp.expect_error(format('insert into public.event_services(event_id,service_type,label,quantity_needed) values(%L,''other'',''RPC bypass'',1)',current_setting('test.full_event')),'functions_creation_only');
-- Disposable legacy/new evidence matrix: unknown scheduled end cannot manufacture work.
set local session_replication_role=replica;
insert into public.events(id,client_id,name,venue,start_at,end_at,status,organization_id,created_by_profile_id,coordinator_id,origin)
select ('42000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'30000000-0000-4000-8000-000000000001','Evidence case '||i,'Venue',case when i=8 then now()+interval '1 day' else now()-interval '3 days' end,null,'completed','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',case when i=6 then 'other' else null end from generate_series(1,9) i;
insert into public.event_services(id,event_id,service_type,label,quantity_needed)
select ('52000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('42000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'other','Evidence',1 from generate_series(1,9) i;
insert into public.assignments(id,event_service_id,freelancer_id,status,agreed_amount)
select ('72000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('52000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'60000000-0000-4000-8000-000000000002',case when i=9 then 'confirmed' else 'checked_out' end,440 from generate_series(1,9) i;
insert into public.attendance(assignment_id,check_in_at,check_out_at,validated_by,validated_at)
select ('72000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,now()-interval '2 days',case when i=4 then now()-interval '3 days' when i=5 then now()+interval '1 day' else now()-interval '1 day' end,case when i=3 then null else '10000000-0000-4000-8000-000000000001'::uuid end,case when i=3 then null else now() end from generate_series(1,9) i where i<>2;
insert into public.assignment_terms(assignment_id,revision,basis,rate,contract_days,total,created_by) values ('72000000-0000-4000-8000-000000000007',1,'service',440,1,440,'10000000-0000-4000-8000-000000000001');
set local session_replication_role=origin;
select pg_temp.check_true(bool_and(private.eventcore_actual_completed_assignment(('72000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid)=(i=1)),'NULL-end fallback admits only legacy checked-out ordered validated past work; rejects absent/unvalidated/reversed/future attendance, new origin/terms, future start and availability-only status') from generate_series(1,9) i;
rollback;
