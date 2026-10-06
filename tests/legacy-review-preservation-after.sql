-- Paired with before.sql and the actual Task2 migration in the same disposable transaction.
select pg_temp.legacy_check((select reviews=(select jsonb_agg(to_jsonb(r) order by r.id) from public.ratings r)
 and assignments=(select jsonb_agg(to_jsonb(a) order by a.id) from public.assignments a)
 and payments=(select jsonb_agg(to_jsonb(p) order by p.id) from public.payments p)
 and attendance=(select jsonb_agg(to_jsonb(t) order by t.id) from public.attendance t) from legacy_review_baseline),'migration preserves original review/assignment/payment/attendance rows exactly');
select pg_temp.legacy_check((select count(*)=2 and bool_and(end_at is null and origin is null) from public.events),'legacy NULL scheduled ends/origins remain NULL');
select pg_temp.legacy_check(private.eventcore_actual_completed_assignment('71000000-0000-4000-8000-000000000001') and private.eventcore_actual_completed_assignment('71000000-0000-4000-8000-000000000002'),'both validated actual legacy jobs remain admissible');
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select pg_temp.legacy_check(jsonb_array_length(public.get_provider_worker_history('21000000-0000-4000-8000-000000000001'))=1
 and (public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')->0->>'job_count')::integer=2
 and (public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')->0->>'review_count')::integer=1
 and (public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')->0->>'average_stars')::numeric=4
 and (public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')->0->>'punctuality_count')::integer=2
 and (public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')->0->>'punctuality')::numeric=50,'provider history preserves independent two jobs/one review/four stars/two attendances/50 percent metrics');
select pg_temp.legacy_check(public.get_professional_reputation('61000000-0000-4000-8000-000000000001')->'reviews'->0->>'id'=current_setting('test.legacy_rating'),'authorized provider reputation retains original review ID');
select pg_temp.legacy_check((select rating=4 and review_count=1 and completed_jobs=2 from public.get_professional_directory() where freelancer_id='61000000-0000-4000-8000-000000000001'),'provider directory uses independent actual legacy job/review metrics');
select pg_temp.legacy_error($q$select public.submit_assignment_rating('71000000-0000-4000-8000-000000000001',5,'Duplicate')$q$,'assignment_already_rated');
select pg_temp.legacy_error($q$update public.events set end_at=now() where id='41000000-0000-4000-8000-000000000001'$q$,'completed_event_immutable');
select pg_temp.legacy_error($q$select public.set_assignment_amount('71000000-0000-4000-8000-000000000001',999)$q$,'historical_agreement_immutable');
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select pg_temp.legacy_check(public.get_professional_reputation('61000000-0000-4000-8000-000000000001')->'reviews'->0->>'id'=current_setting('test.legacy_rating'),'worker reputation retains own original review ID');
select pg_temp.legacy_check(jsonb_array_length(public.get_my_work_assignments())=2 and not exists(select 1 from jsonb_array_elements(public.get_my_work_assignments()) a where a->'end_at'<>'null'::jsonb or a->'completion_confirmed'<>'true'::jsonb or (a->>'legacy_agreed_amount')::numeric<>440),'own worker work history retains NULL schedule/actual completion/original440 totals');
select pg_temp.legacy_check((select rating=4 and review_count=1 and completed_jobs=2 from public.get_professional_directory() where freelancer_id='61000000-0000-4000-8000-000000000001'),'worker own directory retains same independent evidence metrics');
select pg_temp.legacy_error($q$select public.confirm_assignment_completion('71000000-0000-4000-8000-000000000001')$q$,'completed_event_required');
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
select pg_temp.legacy_error($q$select public.get_provider_worker_history('21000000-0000-4000-8000-000000000001')$q$,'forbidden');
select pg_temp.legacy_error($q$select public.get_professional_reputation('61000000-0000-4000-8000-000000000001')$q$,'forbidden');
reset role;
rollback;
