-- Real PostgreSQL allow/deny/projection coverage; all fixtures roll back.
begin;
create function pg_temp.check_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_denied(statement text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then
  if sqlerrm='forbidden' or sqlstate='42501' then return; end if; raise;
 end;
 raise exception 'FAIL: unexpectedly allowed: %',statement;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values
 ('91000000-0000-4000-8000-000000000001','index-owner@example.invalid','{"full_name":"Owner"}'),
 ('91000000-0000-4000-8000-000000000002','index-finance@example.invalid','{"full_name":"Finance"}'),
 ('91000000-0000-4000-8000-000000000003','index-operations@example.invalid','{"full_name":"Operations"}'),
 ('91000000-0000-4000-8000-000000000004','index-unrelated@example.invalid','{"full_name":"Unrelated"}'),
 ('91000000-0000-4000-8000-000000000005','index-legacy@example.invalid','{"full_name":"Legacy"}'),
 ('91000000-0000-4000-8000-000000000006','index-buyer@example.invalid','{"full_name":"Buyer"}');
update public.profiles set profile_type='company',onboarding_completed=true where id::text like '91000000-%';
insert into public.organizations(id,owner_profile_id,organization_type,display_name,market_role,buyer_subtype) values
 ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','company','Provider','provider',null),
 ('92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000004','company','Unrelated','provider',null),
 ('92000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000006','agency','Buyer','buyer','agency');
insert into public.organization_members(organization_id,profile_id,member_role,finance_authorized) values
 ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','member',true),
 ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000003','manager',false);
insert into public.clients(id,trade_name,organization_id) values
 ('93000000-0000-4000-8000-000000000001','Customer','92000000-0000-4000-8000-000000000001');
-- Legacy fixtures only: no production mutation guard is weakened by this test.
set local session_replication_role=replica;
insert into public.events(id,client_id,name,venue,start_at,organization_id,created_by_profile_id) values
 ('94000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','Finance work','Private exact address',now()+interval '1 day','92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001'),
 ('94000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000001','Unrelated work','Secret',now()+interval '2 days','92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000004'),
 ('94000000-0000-4000-8000-000000000003','93000000-0000-4000-8000-000000000001','Unowned history','Historic',now()-interval '1 day',null,null),
 ('94000000-0000-4000-8000-000000000004','93000000-0000-4000-8000-000000000001','Legacy own','Historic',now()-interval '2 days',null,'91000000-0000-4000-8000-000000000005'),
 ('94000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000001','Buyer trap','Secret',now(),'92000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000006');
insert into public.event_financials(event_id,gross_amount) values
 ('94000000-0000-4000-8000-000000000001',5600),('94000000-0000-4000-8000-000000000004',123.45);
insert into public.freelancers(id,profile_id,full_name) values
 ('95000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000004','Worker One'),
 ('95000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000006','Worker Two');
insert into public.event_services(id,event_id,service_type,label,quantity_needed) values
 ('96000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','other','Crew',2);
insert into public.assignments(id,event_service_id,freelancer_id,status,agreed_amount) values
 ('97000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','confirmed',440),
 ('97000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002','confirmed',660);
insert into public.profile_private_identity(profile_id,document_type,document_number) values('91000000-0000-4000-8000-000000000002','cpf','11144477735');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.get_work_finance_index()=jsonb_build_array(jsonb_build_object('event_id','94000000-0000-4000-8000-000000000001','event_name','Finance work','organization_id','92000000-0000-4000-8000-000000000001')),'finance-only exact index allowlist and tenant scope');
select pg_temp.check_true((select count(*) from public.events)=0,'finance grant does not broaden operational event RLS');
select pg_temp.expect_denied($$select public.get_event_operations('94000000-0000-4000-8000-000000000001')$$);
select pg_temp.check_true((public.get_work_finance('94000000-0000-4000-8000-000000000001')->>'sale_contracted')::numeric=5600,'finance-only actual finance projection');
select pg_temp.check_true(public.get_work_finance('94000000-0000-4000-8000-000000000001')->'sale_received'='null'::jsonb,'legacy receipts stay unknown');
select pg_temp.check_true((public.get_event_remunerations('94000000-0000-4000-8000-000000000001')->0->>'worker_name')='Worker One' and (public.get_event_remunerations('94000000-0000-4000-8000-000000000001')->1->>'legacy_agreed_amount')::numeric=660,'finance-only per-worker wage discovery independent of operations');
select public.mark_assignment_paid('97000000-0000-4000-8000-000000000001','pix');
select pg_temp.check_true((public.get_event_remunerations('94000000-0000-4000-8000-000000000001')->0->'payments'->0->>'amount')::numeric=440,'finance-only authorized worker payment recorded');
select pg_temp.expect_denied($$select public.get_event_remunerations('94000000-0000-4000-8000-000000000002')$$);

select pg_temp.expect_denied($$select public.get_work_finance('94000000-0000-4000-8000-000000000002')$$);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'operations-only member has no finance index');
select pg_temp.check_true(public.get_event_operations('94000000-0000-4000-8000-000000000001')->'can_finance'='false'::jsonb,'operations remain available without finance');
select pg_temp.expect_denied($$select public.get_work_finance('94000000-0000-4000-8000-000000000001')$$);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(jsonb_array_length(public.get_work_finance_index())=1 and public.get_work_finance_index()->0->>'event_id'='94000000-0000-4000-8000-000000000002','unrelated provider gets only own work');
select pg_temp.expect_denied($$select public.get_work_finance('94000000-0000-4000-8000-000000000001')$$);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000006',true);
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'buyer gets no provider work even for malformed historic ownership');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000005',true);
select pg_temp.check_true(public.get_work_finance_index()=jsonb_build_array(jsonb_build_object('event_id','94000000-0000-4000-8000-000000000004','event_name','Legacy own','organization_id',null)),'undocumented legacy creator keeps only own finance');
select pg_temp.check_true((public.get_work_finance('94000000-0000-4000-8000-000000000004')->>'sale_contracted')::numeric=123.45,'historic total unchanged');
select set_config('test.buyer_history_org',public.configure_business_identity('{"display_name":"Legacy buyer","organization_type":"agency","market_role":"buyer","buyer_subtype":"agency","document":"52998224725"}')::text,true);
select pg_temp.check_true(jsonb_array_length(public.get_work_finance_index())=1 and (public.get_work_finance('94000000-0000-4000-8000-000000000004')->>'sale_contracted')::numeric=123.45,'buyer classification preserves creator historical finance');
select pg_temp.check_true(public.get_event_operations('94000000-0000-4000-8000-000000000004')->'can_hire'='false'::jsonb,'buyer historical detail cannot hire');
select pg_temp.expect_denied($$select public.create_event_assignment('96000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001')$$);

reset role;
update public.organization_members set finance_authorized=false where profile_id='91000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'revoked finance is immediately hidden');
reset role;
update public.organization_members set finance_authorized=true,active=false where profile_id='91000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'inactive member hidden');
reset role;
update public.organization_members set active=true where profile_id='91000000-0000-4000-8000-000000000002';
update public.profiles set active=false where id='91000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'inactive actor hidden');
reset role;
update public.profiles set active=true where id='91000000-0000-4000-8000-000000000002';
update public.organizations set active=false where id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.check_true(public.get_work_finance_index()='[]'::jsonb,'inactive organization hidden');
reset role;
select pg_temp.check_true(not has_function_privilege('anon','public.get_work_finance_index()','execute'),'anon ACL denied');
set local role anon;
select pg_temp.expect_denied('select public.get_work_finance_index()');
reset role;
select pg_temp.check_true((select organization_id is null and created_by_profile_id is null from public.events where id='94000000-0000-4000-8000-000000000003'),'unowned history unchanged');
rollback;
