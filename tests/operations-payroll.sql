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
insert into public.profile_specialties(profile_id,specialty_id) select p.id,(select id from public.specialties where active order by id limit 1) from public.profiles p where p.profile_type='freelancer' and p.id::text like '10000000-%';
insert into public.profile_photos(id,profile_id,kind,slot,object_path,byte_size,caption,real_declared) values
('99000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','portfolio',1,'10000000-0000-4000-8000-000000000001/99000000-0000-4000-8000-000000000001.webp',1024,'Provider real work',true),
('99000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005','portfolio',1,'10000000-0000-4000-8000-000000000005/99000000-0000-4000-8000-000000000002.webp',1024,'Worker real work',true);

update public.events set end_at=now()+interval '3 days' where id='40000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
-- Partial payroll: legacy totals and immutable pending payment survive unchanged.
select set_config('test.entry',public.record_assignment_payment('70000000-0000-4000-8000-000000000001',100,'pix',(now() at time zone 'America/Sao_Paulo')::date,'advance','Pix TEST-1','Primeiro adiantamento','test-advance')::text,true);
select pg_temp.check_true((public.get_assignment_payment_entries('70000000-0000-4000-8000-000000000001')->>'balance')::numeric=340,'advance leaves balance 340');
select pg_temp.check_true((public.get_work_finance('40000000-0000-4000-8000-000000000001')->>'labor_contracted')::numeric=1100 and (public.get_work_finance('40000000-0000-4000-8000-000000000001')->>'labor_paid')::numeric=100,'partial payments never reduce contracted wages');
select pg_temp.check_true(public.record_assignment_payment('70000000-0000-4000-8000-000000000001',100,'pix',(now() at time zone 'America/Sao_Paulo')::date,'advance','Pix TEST-1','Primeiro adiantamento','test-advance')::text=current_setting('test.entry'),'idempotent replay');
select pg_temp.expect_error($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',101,'pix',current_date,'advance','Pix TEST-1','Primeiro adiantamento','test-advance')$q$,'idempotency_conflict');
select pg_temp.expect_error($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',341,'pix',current_date,'partial',null,null,'over')$q$,'payment_exceeds_payable');
select pg_temp.expect_error($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',1,'pix',current_date,'settlement',null,null,'bad-settle')$q$,'settlement_must_match_balance');
select pg_temp.expect_error($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',1,'pix',current_date+1,'partial',null,null,'future')$q$,'invalid_installment');
select pg_temp.expect_error($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',-1,'pix',current_date,'partial',null,null,'negative')$q$,'invalid_installment');
select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',40,'transfer',(now() at time zone 'America/Sao_Paulo')::date,'partial',null,null,'test-partial');
select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix');
select public.mark_assignment_paid('70000000-0000-4000-8000-000000000001','pix');
select pg_temp.check_true((public.get_assignment_payment_entries('70000000-0000-4000-8000-000000000001')->>'paid')::numeric=440 and (public.get_assignment_payment_entries('70000000-0000-4000-8000-000000000001')->>'balance')::numeric=0,'legacy settlement pays only remainder once');
select pg_temp.check_true((select amount=440 and status='pending' from public.payments where assignment_id='70000000-0000-4000-8000-000000000001'),'original legacy payment preserved');
select pg_temp.check_true((public.get_work_finance('40000000-0000-4000-8000-000000000001')->>'labor_paid')::numeric=440,'cash counted once');
select pg_temp.expect_denied($q$insert into public.assignment_payment_entries(assignment_id,amount,method,payment_kind,paid_on,idempotency_key,recorded_by) values('70000000-0000-4000-8000-000000000001',1,'pix','partial',current_date,'forged','10000000-0000-4000-8000-000000000001')$q$);
-- Shifts keep commercial function terms unchanged.
select set_config('test.shift',public.create_work_shift('50000000-0000-4000-8000-000000000001','Montagem',now()+interval '2 days',now()+interval '2 days 4 hours','Portão 2')::text,true);
select pg_temp.expect_error($q$select public.create_work_shift('50000000-0000-4000-8000-000000000001','Fora',now()+interval '4 days',now()+interval '5 days','Portão 2')$q$,'invalid_shift');
select public.set_work_shift_assignment(current_setting('test.shift')::uuid,'70000000-0000-4000-8000-000000000001',true);
select public.set_work_shift_assignment(current_setting('test.shift')::uuid,'70000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(jsonb_array_length(public.get_work_shifts('40000000-0000-4000-8000-000000000001'))=1,'operator sees event shift');
select pg_temp.expect_error(format('select public.set_work_shift_assignment(%L,''70000000-0000-4000-8000-000000000001'',null)',current_setting('test.shift')),'forbidden');
select set_config('test.work2',public.create_event_with_services(jsonb_build_object('organization_id','20000000-0000-4000-8000-000000000001','client_id','30000000-0000-4000-8000-000000000001','name','Outro evento','venue','Local 2','origin','whatsapp','start_at',now()+interval '1 day','end_at',now()+interval '3 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',3,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220)))::text,true);
select set_config('test.event2',current_setting('test.work2')::jsonb->'event'->>'id',true);
select set_config('test.service2',current_setting('test.work2')::jsonb->'services'->0->>'id',true);
select set_config('test.a2',public.create_event_assignment(current_setting('test.service2')::uuid,'60000000-0000-4000-8000-000000000001')::text,true);
select pg_temp.expect_error(format('select public.record_assignment_payment(%L,1,''pix'',current_date,''advance'',null,null,''no-accept'')',current_setting('test.a2')),'worker_acceptance_required');
select set_config('test.shift2',public.create_work_shift(current_setting('test.service2')::uuid,'Conflitante',now()+interval '2 days 1 hour',now()+interval '2 days 5 hours','Local 2')::text,true);
select pg_temp.expect_error(format('select public.set_work_shift_assignment(%L,%L,true)',current_setting('test.shift2'),current_setting('test.a2')),'worker_shift_conflict');

-- Terms remain frozen after the first installment, including an already pending revision.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select public.respond_to_assignment(current_setting('test.a2')::uuid,'confirmed');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('test.pending_term',public.propose_assignment_terms(current_setting('test.a2')::uuid,'{"basis":"daily","rate":225,"contract_days":2,"additions":0,"deductions":0}'::jsonb)::text,true);
select public.record_assignment_payment(current_setting('test.a2')::uuid,55,'pix',(now() at time zone 'America/Sao_Paulo')::date,'advance',null,null,'modern-advance');
select pg_temp.expect_error(format('select public.propose_assignment_terms(%L,''{"basis":"daily","rate":230,"contract_days":2}''::jsonb)',current_setting('test.a2')),'assignment_has_installments');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.expect_error(format('select public.accept_assignment_terms(%L)',current_setting('test.pending_term')),'assignment_has_installments');
select pg_temp.check_true((public.get_assignment_payment_entries(current_setting('test.a2')::uuid)->>'total')::numeric=440,'offered revision never overrides accepted total');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$update public.events set end_at=now()+interval '2 days 2 hours' where id='40000000-0000-4000-8000-000000000001'$q$,'existing_shifts_outside_event');
select pg_temp.expect_denied(format('insert into public.work_shift_assignments(shift_id,assignment_id,created_by) values(%L,%L,''10000000-0000-4000-8000-000000000001'')',current_setting('test.shift2'),current_setting('test.a2')));
-- Atomic replacement: old assignment survives, new invitation needs its own acceptance.
select set_config('test.replacement',public.replace_event_assignment('70000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000020','Indisponibilidade confirmada')::text,true);
select pg_temp.check_true((select status='cancelled' and agreed_amount=660 from public.assignments where id='70000000-0000-4000-8000-000000000002'),'old assignment evidence preserved');
select pg_temp.check_true((select status='invited' and agreed_amount=440 from public.assignments where id=current_setting('test.replacement')::uuid),'replacement is invitation, no auto-accept');
select pg_temp.check_true((select count(*)=1 from public.work_shift_assignments where assignment_id=current_setting('test.replacement')::uuid),'future shift copied');
select pg_temp.expect_error($q$select public.replace_event_assignment('70000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000011','Não permitido')$q$,'replacement_evidence_locked');
select pg_temp.expect_error($q$select public.replace_event_assignment('70000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000011','Repetição')$q$,'replacement_evidence_locked');
select pg_temp.expect_error(format('select public.replace_event_assignment(%L,''60000000-0000-4000-8000-000000000001'',''Duplicado'')',current_setting('test.a2')),'invalid_replacement');
select pg_temp.check_true((select status='confirmed' from public.assignments where id=current_setting('test.a2')::uuid),'failed replacement keeps old status');
-- Ownership/RLS: worker sees own shifts, installments and terms, never a colleague's.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select pg_temp.check_true((select count(*)=4 from public.assignment_payment_entries),'worker reads only own installments');
select pg_temp.check_true(jsonb_array_length(public.get_work_shifts())=1 and jsonb_array_length(public.get_work_shifts()->0->'assignment_ids')=1,'worker shift DTO hides other workers');
select pg_temp.expect_denied($q$select public.get_assignment_payment_entries('70000000-0000-4000-8000-000000000002')$q$);
select pg_temp.expect_denied($q$select public.get_work_shifts('40000000-0000-4000-8000-000000000001')$q$);
select pg_temp.expect_denied($q$select public.record_assignment_payment('70000000-0000-4000-8000-000000000001',1,'pix',current_date,'partial',null,null,'worker-write')$q$);
select pg_temp.check_true((select count(*)=0 from public.assignment_replacements),'worker cannot browse replacement reasons or colleagues');
-- Coordinator can operate but has no wage access; buyer cannot hire freelancers.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(jsonb_array_length(public.get_work_shifts('40000000-0000-4000-8000-000000000001'))=1,'coordinator reads operational shifts');
select pg_temp.check_true((select count(*)=0 from public.assignment_payment_entries),'coordinator without finance sees no wages');
select pg_temp.expect_denied($q$select public.get_assignment_payment_entries('70000000-0000-4000-8000-000000000001')$q$);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select pg_temp.expect_denied($q$select public.replace_event_assignment('70000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000011','Agência')$q$);
select pg_temp.expect_denied($q$select public.create_work_shift('50000000-0000-4000-8000-000000000002','Agência',now()+interval '2 days',now()+interval '2 days 1 hour','Local')$q$);
select pg_temp.check_true((select count(*)=0 from public.assignment_payment_entries),'buyer cannot read workforce installments');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select pg_temp.expect_denied($q$select public.get_work_shifts('40000000-0000-4000-8000-000000000001')$q$);
select pg_temp.check_true((select count(*)=0 from public.work_shifts),'unrelated organization cannot read shifts');
reset role;
rollback;
