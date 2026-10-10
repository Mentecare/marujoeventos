-- Disposable fixture: real RPC, RLS, triggers and lease transitions. Rolls back all identities.
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$ begin begin execute statement; exception when others then if sqlerrm=expected or (expected='permission' and sqlstate='42501') then return; end if; raise; end; raise exception 'FAIL: unexpectedly allowed %',statement; end $$;
-- IDs may contain 220/440/280/5600 by chance; retain checks on actual payload values.
create function pg_temp.notification_has_private_payload(value jsonb,pattern text) returns boolean language sql immutable as $$
 select regexp_replace(value::text,'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}','UUID','gi') ~ pattern;
$$;
select pg_temp.check_true(not pg_temp.notification_has_private_payload(jsonb_build_object('link','/?assignment=44000000-2200-4000-8000-000000000440','title','Atualização do seu convite ou contrato de trabalho'),'SECRET|220|440|wage|margin|client|venue'),'safe UUID is not remuneration');
select pg_temp.check_true(not pg_temp.notification_has_private_payload(jsonb_build_object('opportunity',jsonb_build_object('id','28000000-5600-4000-8000-000000000280'),'title','Atualização de proposta ou contratação'),'PRIVATE|280|5600|client|venue|margin'),'safe nested quote UUID is not a sale value');
select pg_temp.check_true(pg_temp.notification_has_private_payload(jsonb_build_object('link','/?assignment=44000000-2200-4000-8000-000000000440','rate',220),'SECRET|220|440|wage|margin|client|venue'),'actual remuneration still rejected');
select pg_temp.check_true(pg_temp.notification_has_private_payload(jsonb_build_object('link','/?assignment=44000000-2200-4000-8000-000000000440','title','SECRET CLIENT'),'SECRET|220|440|wage|margin|client|venue'),'private client text still rejected');
select pg_temp.check_true(public.get_public_opportunity('00000000-0000-4000-8000-000000000000') is null,'unknown public preview unavailable');
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('94000000-0000-4000-8000-000000000001','provider-notify@example.invalid',now(),'{"full_name":"Provider notification"}'),
('94000000-0000-4000-8000-000000000002','worker-notify@example.invalid',now(),'{"full_name":"Worker notification"}'),
('94000000-0000-4000-8000-000000000003','other-notify@example.invalid',now(),'{"full_name":"Other notification"}'),
('94000000-0000-4000-8000-000000000004','unconfirmed-notify@example.invalid',null,'{"full_name":"Unconfirmed notification"}');
update public.profiles set profile_type='freelancer',onboarding_completed=true where id::text like '94000000-%';
update public.profiles set profile_type='company' where id='94000000-0000-4000-8000-000000000001';
insert into public.freelancers(id,profile_id,full_name,active) values('94100000-0000-4000-8000-000000000002','94000000-0000-4000-8000-000000000002','Worker',true),('94100000-0000-4000-8000-000000000003','94000000-0000-4000-8000-000000000003','Other',true);
insert into public.profile_specialties(profile_id,specialty_id) select '94000000-0000-4000-8000-000000000002',id from public.specialties where active order by id limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000004',true);
select pg_temp.expect_error($q$select public.save_notification_preferences('{"email_enabled":true}')$q$,'confirmed_email_required');
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select public.save_notification_preferences('{"mode":"all_eligible","email_enabled":true,"push_enabled":true}');
select set_config('test.device',public.register_notification_device(jsonb_build_object('endpoint','https://fcm.googleapis.com/fcm/send/notification-sql-fixture','keys',jsonb_build_object('p256dh',repeat('A',87),'auth',repeat('A',22))))::text,true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('test.org',public.configure_business_identity('{"display_name":"Notification provider","organization_type":"company","market_role":"provider","document":"52998224725"}')::text,true);
select set_config('test.client',public.create_external_work_client(current_setting('test.org')::uuid,'SECRET CLIENT')::text,true);
select set_config('test.work',public.create_event_with_services(jsonb_build_object('organization_id',current_setting('test.org'),'client_id',current_setting('test.client'),'name','SECRET PRIVATE EVENT','venue','SECRET ADDRESS','notes','SECRET NOTES','public_region','Rio','start_at',now()+interval '10 days','end_at',now()+interval '12 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220,'open_marketplace',true,'public_description','Authorized public description')))::text,true);
select set_config('test.service',(current_setting('test.work')::jsonb->'services'->0->>'id'),true);
select set_config('test.event',(current_setting('test.work')::jsonb->'event'->>'id'),true);
select pg_temp.check_true(public.get_public_opportunity(current_setting('test.service')::uuid)->>'region'='Rio','public region');
select pg_temp.check_true(public.get_public_opportunity(current_setting('test.service')::uuid)->>'description'='Authorized public description','authorized description');
select pg_temp.check_true((select array_agg(k order by k) from jsonb_object_keys(public.get_public_opportunity(current_setting('test.service')::uuid)) k)=array['date','days','description','id','provider','region','role','title'],'exact public allowlist');
select pg_temp.check_true(public.get_public_opportunity(current_setting('test.service')::uuid)::text !~ 'SECRET|220|440|client|venue|margin|freelancer','public has no private data');
select pg_temp.expect_error($q$select public.claim_notification_batches()$q$,'permission');
reset role;
select pg_temp.check_true((select count(*)=1 from public.notifications),'only compatible worker receives general opportunity');
select pg_temp.check_true((select count(*)=2 from private.notification_outbox),'event/recipient/channel outbox');
select private.eventcore_enqueue_notification('opportunity:'||current_setting('test.service'),'opportunity',current_setting('test.service')::uuid);
select pg_temp.check_true((select count(*)=2 from private.notification_outbox),'durable dedupe');
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000003',true);
select pg_temp.check_true((select count(*)=0 from public.notifications),'RLS other recipient sees no notifications');
select pg_temp.check_true((select count(*)=0 from public.notification_devices),'RLS device ownership');
select pg_temp.expect_error($q$select public.register_notification_device('{"endpoint":"https://fcm.googleapis.com/fcm/send/notification-sql-fixture","keys":{"p256dh":"bad","auth":"bad"}}')$q$,'device_already_owned');
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(jsonb_array_length(public.get_notification_center()->'notifications')=1,'own center');
select public.save_notification_preferences('{"mode":"relevant","regions":["Elsewhere"],"email_enabled":true,"push_enabled":true}');
select pg_temp.check_true(jsonb_array_length(public.get_work_opportunities())=1,'alert filters do not affect opportunity browsing');
select public.save_notification_preferences('{"mode":"all_eligible","email_enabled":true,"push_enabled":true}');
reset role;
-- Real service-only lease flow. No adapter called and no email/push endpoint requested here.
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select set_config('test.claim',public.claim_notification_batches(1)::text,true);
select set_config('test.batch',(current_setting('test.claim')::jsonb->0->>'id'),true);
select set_config('test.lease',(current_setting('test.claim')::jsonb->0->>'lease_token'),true);
select pg_temp.check_true(jsonb_array_length(current_setting('test.claim')::jsonb)=1,'bounded claim');
select pg_temp.check_true(public.recheck_notification_batch(current_setting('test.batch')::uuid,current_setting('test.lease')::uuid),'lease rechecked');
select pg_temp.check_true(jsonb_array_length(public.claim_notification_batches(20))=1,'active first lease cannot be reclaimed');
select public.finish_notification_batch(current_setting('test.batch')::uuid,current_setting('test.lease')::uuid,'retry','provider_unavailable');
select pg_temp.expect_error(format('select public.finish_notification_batch(%L,%L,%L)',current_setting('test.batch'),current_setting('test.lease'),'acknowledged'),'stale_lease');
reset role;
select pg_temp.check_true((select attempts=1 and status='queued' and acknowledged_at is null and available_at>now() from private.notification_batches where id=current_setting('test.batch')::uuid),'retry backoff without false sent acknowledgment');
update private.notification_batches set available_at=now() where id=current_setting('test.batch')::uuid;
-- Pause during a lease suppresses all pending notifications, but keeps browsing and center.
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select public.save_notification_preferences('{"mode":"all_eligible","email_enabled":true,"push_enabled":true,"paused_until":"9999-01-01T00:00:00Z"}');
select pg_temp.check_true(jsonb_array_length(public.get_notification_center()->'notifications')=1,'paused center works');
reset role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select pg_temp.check_true(jsonb_array_length(public.claim_notification_batches())=0,'pause rechecked; no external sends');
reset role;
-- Private direct invites never produce a general audience.
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select public.publish_work_function(current_setting('test.service')::uuid,false);
select set_config('test.assignment',public.create_event_assignment(current_setting('test.service')::uuid,'94100000-0000-4000-8000-000000000002')::text,true);
select pg_temp.check_true(public.get_public_opportunity(current_setting('test.service')::uuid) is null,'private ID has no preview');
reset role;
select pg_temp.check_true((select count(*)=1 from public.notifications n join private.notification_events ev on ev.id=n.source_id where ev.assignment_id=current_setting('test.assignment')::uuid),'one initial invitation');
select pg_temp.check_true(not exists(select 1 from public.notifications n join private.notification_events ev on ev.id=n.source_id where ev.kind='assignment' and n.profile_id<>'94000000-0000-4000-8000-000000000002'),'direct invite isolated to selected participant');
select pg_temp.check_true(not exists(select 1 from private.notification_events ev where pg_temp.notification_has_private_payload(private.eventcore_notification_dto(ev.id),'SECRET|220|440|wage|margin|client|venue')),'notification DTO has no private payload');
-- Closed work suppresses center and jobs; public previews never stale.
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
update public.events set status='cancelled' where id=current_setting('test.event')::uuid;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(jsonb_array_length(public.get_notification_center()->'notifications')=0,'closed/stale center suppressed');
reset role;
-- Daily aggregation and acknowledgment/retry transitions on new published opportunities.
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select public.save_notification_preferences('{"mode":"all_eligible","cadence":"daily","email_enabled":true,"push_enabled":true}');
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select public.create_event_with_services(jsonb_build_object('organization_id',current_setting('test.org'),'client_id',current_setting('test.client'),'name','PRIVATE DIGEST WORK','venue','PRIVATE DIGEST ADDRESS','start_at',now()+interval '20 days','end_at',now()+interval '22 days'),jsonb_build_array(jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220,'open_marketplace',true),jsonb_build_object('specialty_id',(select id from public.specialties where active order by id limit 1),'quantity_needed',10,'contract_days',2,'remuneration_basis','daily','remuneration_rate',220,'open_marketplace',true)));
reset role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select pg_temp.check_true(jsonb_array_length(public.claim_notification_batches())=0,'daily jobs wait until next midnight Sao Paulo');
reset role;
-- Advance only the disposable fixture's due timestamp, never wall-clock production behavior.
update private.notification_outbox set available_at=now() where status='queued' and batch_id is null;
set local role service_role;
select set_config('test.digest_claim',public.claim_notification_batches()::text,true);
select pg_temp.check_true(jsonb_array_length(current_setting('test.digest_claim')::jsonb)=2,'daily two channels batched');
select pg_temp.check_true(not exists(select 1 from jsonb_array_elements(current_setting('test.digest_claim')::jsonb) b where jsonb_array_length(b->'notifications')<>2),'digest holds two notifications per recipient/channel');
select set_config('test.email_batch',(select b->>'id' from jsonb_array_elements(current_setting('test.digest_claim')::jsonb) b where b->>'channel'='email'),true);
select set_config('test.email_lease',(select b->>'lease_token' from jsonb_array_elements(current_setting('test.digest_claim')::jsonb) b where b->>'channel'='email'),true);
select set_config('test.push_batch',(select b->>'id' from jsonb_array_elements(current_setting('test.digest_claim')::jsonb) b where b->>'channel'='push'),true);
select set_config('test.push_lease',(select b->>'lease_token' from jsonb_array_elements(current_setting('test.digest_claim')::jsonb) b where b->>'channel'='push'),true);
-- The original cached full/mixed payload must never regain authorization after another claim.
savepoint lease_race;
reset role;
update public.event_services set visibility='private' where id=(select ev.service_id from private.notification_outbox q join public.notifications n on n.id=q.notification_id join private.notification_events ev on ev.id=n.source_id where q.batch_id=current_setting('test.email_batch')::uuid limit 1);
set local role service_role;
select pg_temp.check_true(not public.recheck_notification_batch(current_setting('test.email_batch')::uuid,current_setting('test.email_lease')::uuid),'mixed digest initially denied');
select public.claim_notification_batches(20);
select pg_temp.check_true(not public.recheck_notification_batch(current_setting('test.email_batch')::uuid,current_setting('test.email_lease')::uuid),'mixed cached digest stays denied after second worker claim');
rollback to lease_race;
reset role;
update public.notification_preferences set email_enabled=false where profile_id='94000000-0000-4000-8000-000000000002';
set local role service_role;
select pg_temp.check_true(not public.recheck_notification_batch(current_setting('test.email_batch')::uuid,current_setting('test.email_lease')::uuid),'fully suppressed digest initially denied');
select public.claim_notification_batches(20);
select pg_temp.check_true(not public.recheck_notification_batch(current_setting('test.email_batch')::uuid,current_setting('test.email_lease')::uuid),'fully suppressed cached digest stays denied after second worker claim');
rollback to lease_race;
release savepoint lease_race;
select pg_temp.expect_error(format('select public.finish_notification_batch(%L,%L,%L)',current_setting('test.push_batch'),current_setting('test.push_lease'),'acknowledged'),'unacknowledged_devices');
select public.ack_notification_device(current_setting('test.push_batch')::uuid,current_setting('test.push_lease')::uuid,current_setting('test.device')::uuid);
select public.finish_notification_batch(current_setting('test.push_batch')::uuid,current_setting('test.push_lease')::uuid,'acknowledged');
select public.finish_notification_batch(current_setting('test.email_batch')::uuid,current_setting('test.email_lease')::uuid,'disabled','email_not_configured');
reset role;
select pg_temp.check_true((select status='disabled' and attempts=0 and acknowledged_at is null from private.notification_batches where id=current_setting('test.email_batch')::uuid),'missing provider stays queued disabled without attempt or sent result');
select pg_temp.check_true((select count(*)=2 from private.notification_outbox where batch_id=current_setting('test.push_batch')::uuid and status='delivered'),'acknowledged digest delivery');
-- Six bounded real retries with persistent batch identity and increasing due times.
do $$ declare claim jsonb; batch jsonb; attempt integer; begin
 for attempt in 1..6 loop
  update private.notification_batches set available_at=now() where id=current_setting('test.email_batch')::uuid;
  claim:=public.claim_notification_batches();batch:=claim->0;
  perform pg_temp.check_true(batch->>'id'=current_setting('test.email_batch'),'same durable retry batch');
  perform public.finish_notification_batch((batch->>'id')::uuid,(batch->>'lease_token')::uuid,'retry','provider_unavailable');
 end loop;
end $$;
select pg_temp.check_true((select status='failed' and attempts=6 and acknowledged_at is null from private.notification_batches where id=current_setting('test.email_batch')::uuid),'retry budget exhausted without false delivery');
select pg_temp.check_true((select count(*)=2 from private.notification_outbox where batch_id=current_setting('test.email_batch')::uuid and status='failed'),'failed jobs retained for recovery');

-- Commercial contract alerts use actual participants and explicit finance permission.
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('94000000-0000-4000-8000-000000000005','buyer-notify@example.invalid',now(),'{"full_name":"Buyer notification"}'),
('94000000-0000-4000-8000-000000000006','finance-notify@example.invalid',now(),'{"full_name":"Finance notification"}'),
('94000000-0000-4000-8000-000000000007','operations-notify@example.invalid',now(),'{"full_name":"Operations notification"}');
update public.profiles set profile_type='company',onboarding_completed=true where id in ('94000000-0000-4000-8000-000000000005','94000000-0000-4000-8000-000000000006','94000000-0000-4000-8000-000000000007');
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select public.set_organization_member(current_setting('test.org')::uuid,'94000000-0000-4000-8000-000000000006',true);
select public.set_organization_member(current_setting('test.org')::uuid,'94000000-0000-4000-8000-000000000007',true);
select public.set_organization_finance_member(current_setting('test.org')::uuid,'94000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000005',true);
select set_config('test.buyer_org',public.configure_business_identity('{"display_name":"Notification buyer","organization_type":"agency","market_role":"buyer","buyer_subtype":"agency","document":"11222333000181"}')::text,true);
select set_config('test.request',public.create_contract_request(current_setting('test.buyer_org')::uuid,current_setting('test.org')::uuid,'PRIVATE CONTRACT TITLE','PRIVATE CUSTOMER NOTES',current_date+20,'PRIVATE CONTRACT VENUE')::text,true);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('test.quote',public.save_sale_quote(jsonb_build_object('organization_id',current_setting('test.org'),'request_id',current_setting('test.request'),'title','PRIVATE CONTRACT TITLE','valid_until',current_date+20,'payment_terms','PRIVATE PAYMENT TERMS','show_unit_prices',true),jsonb_build_array(jsonb_build_object('label','PRIVATE CONTRACT LABEL','quantity',10,'contract_days',2,'client_unit_price',280)))::text,true);
select public.submit_sale_quote(current_setting('test.quote')::uuid,1);
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000005',true);
select set_config('test.contract',public.accept_sale_quote(current_setting('test.quote')::uuid,1)::text,true);
reset role;
select pg_temp.check_true((select count(*)=3 from public.notifications n join private.notification_events e on e.id=n.source_id where e.contract_id=current_setting('test.contract')::uuid),'contract owner/provider buyer and finance member only');
select pg_temp.check_true(not exists(select 1 from public.notifications n join private.notification_events e on e.id=n.source_id where e.contract_id=current_setting('test.contract')::uuid and n.profile_id in ('94000000-0000-4000-8000-000000000003','94000000-0000-4000-8000-000000000007')),'unrelated tenant and operations-only contract isolation');
select pg_temp.check_true(not exists(select 1 from private.notification_events e where e.contract_id=current_setting('test.contract')::uuid and pg_temp.notification_has_private_payload(private.eventcore_notification_dto(e.id),'PRIVATE|280|5600|client|venue|margin')),'contract notification has no sale or client fields');
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select public.set_organization_finance_member(current_setting('test.org')::uuid,'94000000-0000-4000-8000-000000000006',false);
reset role;
select pg_temp.check_true(not exists(select 1 from private.notification_events e where e.contract_id=current_setting('test.contract')::uuid and private.eventcore_notification_allowed(e.id,'94000000-0000-4000-8000-000000000006')),'revoked finance participant rechecked');

-- Anonymous has only sanitized public RPC.
set local role anon;
select pg_temp.check_true(public.get_public_opportunity(current_setting('test.service')::uuid) is null,'closed ID unavailable for anon');
select pg_temp.expect_error('select public.get_notification_center()','permission');
select pg_temp.expect_error('select * from public.notifications','permission');
rollback;
