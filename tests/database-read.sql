-- No data changes: this failed with 42P17 before the hardening migration.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select count(*) from public.events;
select count(*) from public.event_services;
select count(*) from public.assignments;
select count(*) from public.payments;
rollback;
