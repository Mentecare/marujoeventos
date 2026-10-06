-- Run AFTER the pre-Task2 migration chain, then apply Task2, then run the after fixture.
-- All three files share this transaction; the after fixture rolls everything back.
begin;
create function pg_temp.legacy_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.legacy_error(statement text,expected text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then if sqlerrm=expected then return; end if; raise; end;
 raise exception 'FAIL: unexpectedly allowed: %',statement;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values
 ('11000000-0000-4000-8000-000000000001','legacy-provider@example.invalid','{"full_name":"Legacy provider"}'),
 ('11000000-0000-4000-8000-000000000002','legacy-worker@example.invalid','{"full_name":"Legacy worker"}'),
 ('11000000-0000-4000-8000-000000000003','legacy-outsider@example.invalid','{"full_name":"Outsider"}');
update public.profiles set profile_type='company',onboarding_completed=true where id in ('11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000003');
update public.profiles set profile_type='freelancer',onboarding_completed=true where id='11000000-0000-4000-8000-000000000002';
insert into public.profile_private_identity(profile_id,document_type,document_number) values ('11000000-0000-4000-8000-000000000001','cpf','52998224725');
insert into public.organizations(id,owner_profile_id,organization_type,display_name,market_role) values
 ('21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','company','Legacy provider','provider');
insert into public.clients(id,trade_name,organization_id) values ('31000000-0000-4000-8000-000000000001','Historical client','21000000-0000-4000-8000-000000000001');
-- Only disposable existing-record seed bypasses user triggers. Restore before real rating RPC.
set local session_replication_role=replica;
insert into public.freelancers(id,profile_id,full_name) values ('61000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','Legacy worker');
insert into public.events(id,client_id,name,venue,start_at,end_at,status,organization_id,created_by_profile_id,coordinator_id,arrival_tolerance_minutes)
select ('41000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'31000000-0000-4000-8000-000000000001','Historical work '||i,'Venue',now()-interval '3 days',null,'completed','21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001',15 from generate_series(1,2) i;
insert into public.event_services(id,event_id,service_type,label,quantity_needed,freelancer_unit_cost)
select ('51000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('41000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'other','Historical function',1,440 from generate_series(1,2) i;
insert into public.assignments(id,event_service_id,freelancer_id,status,agreed_amount,contractor_profile_id)
select ('71000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('51000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'61000000-0000-4000-8000-000000000001','checked_out',440,'11000000-0000-4000-8000-000000000001' from generate_series(1,2) i;
insert into public.attendance(assignment_id,check_in_at,check_out_at,validated_by,validated_at)
select ('71000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,now()-interval '3 days'+case when i=1 then interval '5 minutes' else interval '30 minutes' end,now()-interval '2 days','11000000-0000-4000-8000-000000000001',now()-interval '1 day' from generate_series(1,2) i;
insert into public.payments(assignment_id,amount,status,method,paid_at) values ('71000000-0000-4000-8000-000000000001',440,'paid','pix',now()-interval '1 day');
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select set_config('test.legacy_rating',public.submit_assignment_rating('71000000-0000-4000-8000-000000000001',4,'Valid pre-Task2 review')::text,true);
select pg_temp.legacy_check(jsonb_array_length(public.get_professional_reputation('61000000-0000-4000-8000-000000000001')->'reviews')=1,'provider sees accepted legacy review before Task2');
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select pg_temp.legacy_check(jsonb_array_length(public.get_professional_reputation('61000000-0000-4000-8000-000000000001')->'reviews')=1,'worker sees accepted legacy review before Task2');
reset role;
-- Snapshot existing evidence, not new schema columns, before the actual migration.
create temporary table legacy_review_baseline as
select (select jsonb_agg(to_jsonb(r) order by r.id) from public.ratings r) reviews,
 (select jsonb_agg(to_jsonb(a) order by a.id) from public.assignments a) assignments,
 (select jsonb_agg(to_jsonb(p) order by p.id) from public.payments p) payments,
 (select jsonb_agg(to_jsonb(t) order by t.id) from public.attendance t) attendance;
-- Intentionally leave BEGIN open for the migration and after fixture.
