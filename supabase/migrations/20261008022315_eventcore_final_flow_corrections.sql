-- Final additive corrections. Preserve all 33 prior migrations and all historical evidence.
-- Recovery: disable new write RPC grants and notification dispatch; retain evidence; roll forward.
alter table private.notification_batches add column leased_outbox_ids uuid[] not null default '{}';
create or replace function private.eventcore_notification_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='event_services' then
  if new.visibility='open' and new.application_enabled and (tg_op='INSERT' or old.visibility is distinct from new.visibility or old.application_enabled is distinct from new.application_enabled) then perform private.eventcore_enqueue_notification('opportunity:'||new.id,'opportunity',new.id); end if;
 elsif tg_table_name='assignments' then
  if tg_op='INSERT' or new.status is distinct from old.status then perform private.eventcore_enqueue_notification('assignment:'||new.id||':'||new.status,'assignment',new.id); end if;
 elsif tg_table_name='assignment_terms' then
  if new.revision>1 then perform private.eventcore_enqueue_notification('terms:'||new.id,'assignment',new.assignment_id); end if;
 elsif tg_table_name='commercial_contracts' then
  perform private.eventcore_enqueue_notification('contract:'||new.id,'contract',new.id);
 end if;
 return new;
end $$;
create or replace function public.claim_notification_batches(p_limit integer default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_batch private.notification_batches; j record; item jsonb; result jsonb:='[]'; counter integer:=0; cadence text; token uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 -- Changed cadence applies to already queued work without bypassing daily scheduling.
 update private.notification_outbox q set available_at=((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo'
 from public.notifications n join public.notification_preferences p on p.profile_id=n.profile_id
 where n.id=q.notification_id and q.status='queued' and q.batch_id is null and p.cadence='daily' and p.updated_at>n.created_at and q.available_at<=p.updated_at;
 update private.notification_batches b set cadence=p.cadence,available_at=case when p.cadence='daily' then ((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo' else now() end
 from public.notification_preferences p where p.profile_id=b.profile_id and b.cadence<>p.cadence and b.status in ('queued','disabled');
 -- Serialize claims, not external sends. A crashed worker's 5-minute lease is reclaimed.
 if not pg_try_advisory_xact_lock(7400401) then return result; end if;
 update private.notification_outbox q set status='suppressed' from public.notifications n where n.id=q.notification_id and q.status='queued' and not exists(select 1 from private.notification_batches active where active.id=q.batch_id and active.status='leased' and active.lease_until>now()) and not private.eventcore_notification_allowed(n.source_id,n.profile_id,q.channel);
 for v_batch in select * from private.notification_batches where status in ('queued','disabled','leased') and available_at<=now() and (lease_until is null or lease_until<=now()) and attempts<6 order by available_at limit least(greatest(p_limit,1),20) for update skip locked loop
  if not exists(select 1 from private.notification_outbox where batch_id=v_batch.id and status='queued') then update private.notification_batches set status='suppressed',lease_until=null where id=v_batch.id; continue; end if;
  if v_batch.status='leased' then
   if v_batch.attempts>=5 then update private.notification_batches set status='failed',attempts=6,lease_until=null where id=v_batch.id; update private.notification_outbox set status='failed' where batch_id=v_batch.id and status='queued'; continue; end if;
   update private.notification_batches set attempts=attempts+1 where id=v_batch.id;
  end if;
  token:=gen_random_uuid(); update private.notification_batches set status='leased',lease_token=token,lease_until=now()+interval '5 minutes' where id=v_batch.id;
  result:=result||jsonb_build_array(jsonb_build_object('id',v_batch.id,'lease_token',token)); counter:=counter+1;
 end loop;
 for j in select n.profile_id,q.channel,min(q.available_at) as due from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.status='queued' and q.batch_id is null and q.available_at<=now() group by n.profile_id,q.channel order by due loop
  exit when counter>=least(greatest(p_limit,1),20);
  select p.cadence into cadence from public.notification_preferences p where p.profile_id=j.profile_id;
  if cadence='immediate' and (select count(*) from private.notification_batches where profile_id=j.profile_id and channel=j.channel and acknowledged_at>now()-interval '1 hour')>=5 then continue; end if;
  token:=gen_random_uuid(); insert into private.notification_batches(profile_id,channel,cadence,status,lease_token,lease_until) values(j.profile_id,j.channel,cadence,'leased',token,now()+interval '5 minutes') returning * into v_batch;
  update private.notification_outbox set batch_id=v_batch.id where id in (select q.id from private.notification_outbox q join public.notifications n on n.id=q.notification_id where n.profile_id=j.profile_id and q.channel=j.channel and q.status='queued' and q.batch_id is null and q.available_at<=now() order by q.available_at,q.id limit case when cadence='daily' then 100 else 1 end);
  result:=result||jsonb_build_array(jsonb_build_object('id',v_batch.id,'lease_token',token)); counter:=counter+1;
 end loop;
 update private.notification_batches b set leased_outbox_ids=(select array_agg(q.id order by q.id) from private.notification_outbox q where q.batch_id=b.id and q.status='queued') where b.id in (select (x->>'id')::uuid from jsonb_array_elements(result) x);
 -- Build only current allowed DTOs, authoritative confirmed address and remaining owned devices.
 select coalesce(jsonb_agg(x.claim||jsonb_build_object('channel',b.channel,'to',case when b.channel='email' then u.email end,'notifications',(select jsonb_agg(private.eventcore_notification_dto(n.source_id) order by n.created_at,n.id) from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.batch_id=b.id and q.status='queued'),
 'delivered_device_count',(select count(*) from private.notification_device_receipts where batch_id=b.id),'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'subscription',jsonb_build_object('endpoint',d.endpoint,'keys',jsonb_build_object('p256dh',d.p256dh,'auth',d.auth_key)))) from public.notification_devices d where d.profile_id=b.profile_id and d.active and not exists(select 1 from private.notification_device_receipts r where r.batch_id=b.id and r.device_id=d.id)),'[]'::jsonb))),'[]') into result
 from jsonb_array_elements(result) x(claim) join private.notification_batches b on b.id=(x.claim->>'id')::uuid left join auth.users u on u.id=b.profile_id and u.email_confirmed_at is not null;
 return result;
end $$;
create or replace function public.recheck_notification_batch(p_batch_id uuid,p_lease_token uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 return exists(select 1 from private.notification_batches b where b.id=p_batch_id and b.status='leased' and b.lease_token=p_lease_token and b.lease_until>now() and cardinality(b.leased_outbox_ids)>0 and b.leased_outbox_ids=(select array_agg(q.id order by q.id) from private.notification_outbox q where q.batch_id=b.id and q.status='queued') and b.cadence=(select cadence from public.notification_preferences where profile_id=b.profile_id)) and not exists(select 1 from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.batch_id=p_batch_id and q.status='queued' and not private.eventcore_notification_allowed(n.source_id,n.profile_id,q.channel));
end $$;

create table public.work_expense_resolutions (
 id uuid primary key default gen_random_uuid(), expense_id uuid not null unique references public.work_expenses(id),
 amount numeric(12,2) not null check(amount>=0), evidence_reference text not null check(length(trim(evidence_reference)) between 1 and 500),
 recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.work_sale_entries (
 id uuid primary key default gen_random_uuid(), event_id uuid not null unique references public.events(id),
 amount numeric(12,2) not null check(amount>=0), evidence_reference text not null check(length(trim(evidence_reference)) between 1 and 2000),
 recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.work_sale_receipts (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id),
 amount numeric(12,2) not null check(amount>0), method text not null check(method in ('pix','transfer','cash','other')),
 received_on date not null, idempotency_key text not null check(length(trim(idempotency_key)) between 1 and 100),
 recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(event_id,idempotency_key)
);
create table public.work_contract_links (
 event_id uuid primary key references public.events(id), contract_id uuid not null unique references public.commercial_contracts(id),
 recorded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
alter table public.work_expense_resolutions enable row level security;
alter table public.work_sale_entries enable row level security;
alter table public.work_sale_receipts enable row level security;
alter table public.work_contract_links enable row level security;
revoke all on public.work_expense_resolutions,public.work_sale_entries,public.work_sale_receipts,public.work_contract_links from public,anon,authenticated;
grant select on public.work_expense_resolutions,public.work_sale_entries,public.work_sale_receipts,public.work_contract_links to authenticated;
create policy expense_resolutions_read on public.work_expense_resolutions for select to authenticated using(exists(select 1 from public.work_expenses e where e.id=expense_id and private.eventcore_can_finance_event(e.event_id)));
create policy sale_entries_read on public.work_sale_entries for select to authenticated using(private.eventcore_can_finance_event(event_id));
create policy sale_receipts_read on public.work_sale_receipts for select to authenticated using(private.eventcore_can_finance_event(event_id));
create policy contract_links_read on public.work_contract_links for select to authenticated using(private.eventcore_can_finance_event(event_id));
create trigger expense_resolutions_immutable before update or delete on public.work_expense_resolutions for each row execute function private.eventcore_commercial_immutable();
create trigger sale_entries_immutable before update or delete on public.work_sale_entries for each row execute function private.eventcore_commercial_immutable();
create trigger sale_receipts_immutable before update or delete on public.work_sale_receipts for each row execute function private.eventcore_commercial_immutable();
create trigger contract_links_immutable before update or delete on public.work_contract_links for each row execute function private.eventcore_commercial_immutable();
create or replace function private.eventcore_workflow_event_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.commercial_contract_id is not null then
   -- Serialize original creation and later linking on their shared contract row.
   perform 1 from public.commercial_contracts c where c.id=new.commercial_contract_id and c.provider_organization_id=new.organization_id and c.client_id=new.client_id for update;
   if not found then raise exception 'forbidden'; end if;
   if exists(select 1 from public.work_contract_links where contract_id=new.commercial_contract_id) then raise exception 'sale_already_linked'; end if;
  end if;
  new.origin:=coalesce(new.origin,'other');
  return new;
 end if;
 if new.origin is distinct from old.origin or new.commercial_contract_id is distinct from old.commercial_contract_id or new.public_region is distinct from old.public_region then raise exception 'work_origin_contract_immutable'; end if;
 if old.status='completed' and (new.status is distinct from old.status or new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.arrival_tolerance_minutes is distinct from old.arrival_tolerance_minutes) then raise exception 'completed_event_immutable'; end if;
 if (new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at or new.arrival_tolerance_minutes is distinct from old.arrival_tolerance_minutes) and exists(select 1 from public.attendance t join public.assignments a on a.id=t.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=old.id and t.check_in_at is not null) then raise exception 'recorded_schedule_immutable'; end if;
 return new;
end $$;

create function public.resolve_work_expense(p_expense_id uuid,p_amount numeric,p_evidence_reference text) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.work_expenses; r public.work_expense_resolutions; result uuid;
begin
 select * into e from public.work_expenses where id=p_expense_id for update;
 if e.id is null then raise exception 'forbidden'; end if;
 perform private.eventcore_require_work_finance(e.event_id);
 if p_amount is null or p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2) or length(trim(coalesce(p_evidence_reference,''))) not between 1 and 500 then raise exception 'invalid_expense'; end if;
 select * into r from public.work_expense_resolutions where expense_id=e.id;
 if r.id is not null then
  if r.amount=p_amount and r.evidence_reference=trim(p_evidence_reference) then return r.id; end if;
  raise exception 'expense_already_resolved';
 end if;
 if e.amount is not null then raise exception 'expense_already_known'; end if;
 insert into public.work_expense_resolutions(expense_id,amount,evidence_reference,recorded_by) values(e.id,p_amount,trim(p_evidence_reference),auth.uid()) returning id into result;
 return result;
end $$;
create function public.record_work_sale(p_event_id uuid,p_amount numeric,p_evidence_reference text) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.events; prior public.work_sale_entries; result uuid;
begin
 select * into e from public.events where id=p_event_id for update;
 perform private.eventcore_require_work_finance(p_event_id);
 if p_amount is null or p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2) or length(trim(coalesce(p_evidence_reference,''))) not between 1 and 2000 then raise exception 'invalid_sale'; end if;
 select * into prior from public.work_sale_entries where event_id=e.id;
 if prior.id is not null then
  if prior.amount=p_amount and prior.evidence_reference=trim(p_evidence_reference) then return prior.id; end if;
  raise exception 'sale_already_recorded';
 end if;
 if e.commercial_contract_id is not null or exists(select 1 from public.work_contract_links where event_id=e.id) or exists(select 1 from public.event_financials where event_id=e.id and gross_amount is not null) then raise exception 'sale_already_recorded'; end if;
 insert into public.work_sale_entries(event_id,amount,evidence_reference,recorded_by) values(e.id,p_amount,trim(p_evidence_reference),auth.uid()) returning id into result;
 return result;
end $$;
create function public.link_work_sale_contract(p_event_id uuid,p_contract_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.events; c public.commercial_contracts; prior uuid; sale numeric;
begin
 select * into e from public.events where id=p_event_id for update;
 perform private.eventcore_require_work_finance(p_event_id);
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null or not private.eventcore_org_finance(c.provider_organization_id) or c.client_id<>e.client_id or (e.organization_id is not null and e.organization_id<>c.provider_organization_id) then raise exception 'forbidden'; end if;
 select contract_id into prior from public.work_contract_links where event_id=e.id;
 if prior=c.id or e.commercial_contract_id=c.id then return; end if;
 if prior is not null or e.commercial_contract_id is not null or exists(select 1 from public.events where commercial_contract_id=c.id) or exists(select 1 from public.work_contract_links where contract_id=c.id) or exists(select 1 from public.work_sale_receipts where event_id=e.id) then raise exception 'sale_already_linked'; end if;
 select coalesce((select amount from public.work_sale_entries where event_id=e.id),(select gross_amount from public.event_financials where event_id=e.id)) into sale;
 if sale is not null and sale<>c.sale_total then raise exception 'sale_total_conflict'; end if;
 insert into public.work_contract_links(event_id,contract_id,recorded_by) values(e.id,c.id,auth.uid());
end $$;
create function public.record_work_sale_receipt(p_event_id uuid,p_amount numeric,p_method text,p_received_on date,p_idempotency_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.events; prior public.work_sale_receipts; result uuid; contract uuid; sale numeric;
begin
 select * into e from public.events where id=p_event_id for update;
 perform private.eventcore_require_work_finance(p_event_id);
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('pix','transfer','cash','other') or p_received_on is null or not isfinite(p_received_on) or p_received_on>private.eventcore_business_today() or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 then raise exception 'invalid_receipt'; end if;
 contract:=coalesce(e.commercial_contract_id,(select contract_id from public.work_contract_links where event_id=e.id));
 if contract is not null then return public.record_customer_receipt(contract,p_amount,p_method,p_received_on,p_idempotency_key); end if;
 select * into prior from public.work_sale_receipts where event_id=e.id and idempotency_key=p_idempotency_key;
 if prior.id is not null then
  if prior.amount<>p_amount or prior.method<>p_method or prior.received_on<>p_received_on then raise exception 'idempotency_conflict'; end if; return prior.id;
 end if;
 select coalesce((select amount from public.work_sale_entries where event_id=e.id),(select gross_amount from public.event_financials where event_id=e.id)) into sale;
 if sale is null then raise exception 'sale_amount_unknown'; end if;
 if p_amount+coalesce((select sum(amount) from public.work_sale_receipts where event_id=e.id),0)>sale then raise exception 'receipt_exceeds_receivable'; end if;
 insert into public.work_sale_receipts(event_id,amount,method,received_on,idempotency_key,recorded_by) values(e.id,p_amount,p_method,p_received_on,p_idempotency_key,auth.uid()) returning id into result;
 return result;
end $$;
revoke all on function public.resolve_work_expense(uuid,numeric,text),public.record_work_sale(uuid,numeric,text),public.link_work_sale_contract(uuid,uuid),public.record_work_sale_receipt(uuid,numeric,text,date,text) from public,anon;
grant execute on function public.resolve_work_expense(uuid,numeric,text),public.record_work_sale(uuid,numeric,text),public.link_work_sale_contract(uuid,uuid),public.record_work_sale_receipt(uuid,numeric,text,date,text) to authenticated;
create or replace function public.record_work_expense_payment(p_expense_id uuid,p_amount numeric,p_method text,p_paid_on date,p_idempotency_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare expense public.work_expenses; previous public.work_expense_payments; result uuid; effective numeric;
begin
 select * into expense from public.work_expenses where id=p_expense_id for update;
 if expense.id is null then raise exception 'forbidden'; end if;
 perform private.eventcore_require_work_finance(expense.event_id);
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('pix','transfer','cash','other') or p_paid_on is null or not isfinite(p_paid_on) or p_paid_on>private.eventcore_business_today() or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 then raise exception 'invalid_expense_payment'; end if;
 select * into previous from public.work_expense_payments where expense_id=p_expense_id and idempotency_key=p_idempotency_key;
 if previous.id is not null then
  if previous.amount<>p_amount or previous.method<>p_method or previous.paid_on<>p_paid_on then raise exception 'idempotency_conflict'; end if; return previous.id;
 end if;
 effective:=coalesce(expense.amount,(select amount from public.work_expense_resolutions where expense_id=expense.id));
 if effective is null then raise exception 'expense_amount_unknown'; end if;
 if p_amount+coalesce((select sum(amount) from public.work_expense_payments where expense_id=expense.id),0)>effective then raise exception 'expense_exceeds_payable'; end if;
 insert into public.work_expense_payments(expense_id,amount,method,paid_on,idempotency_key,recorded_by) values(expense.id,p_amount,p_method,p_paid_on,p_idempotency_key,auth.uid()) returning id into result;
 return result;
end $$;
create or replace function public.get_work_finance(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e public.events; c public.commercial_contracts; f public.event_financials; sale numeric; received numeric; labor numeric; paid numeric; unknown_labor integer; expenses numeric; expense_paid numeric; unknown_expenses integer;
begin
 if not private.eventcore_can_finance_event(p_event_id) then raise exception 'forbidden'; end if;
 select * into e from public.events where id=p_event_id;
 select * into c from public.commercial_contracts where id=coalesce(e.commercial_contract_id,(select contract_id from public.work_contract_links where event_id=e.id));
 select * into f from public.event_financials where event_id=e.id;
 sale:=coalesce(c.sale_total,f.gross_amount,(select amount from public.work_sale_entries where event_id=e.id));
 if c.id is not null then select coalesce(sum(amount),0) into received from public.customer_receipts where contract_id=c.id; elsif exists(select 1 from public.work_sale_entries where event_id=e.id) or exists(select 1 from public.work_sale_receipts where event_id=e.id) then select coalesce(sum(amount),0) into received from public.work_sale_receipts where event_id=e.id; end if;
 select coalesce(sum(x.amount),0),count(*) filter(where x.amount is null) into labor,unknown_labor from (
 select case when wp.id is not null then wp.amount when exists(select 1 from public.assignment_terms where assignment_id=a.id) then (select total from public.assignment_terms where id=private.eventcore_accepted_term(a.id)) else coalesce(p.amount,a.agreed_amount) end amount
 from public.assignments a join public.event_services s on s.id=a.event_service_id left join public.payments p on p.assignment_id=a.id left join public.workforce_payments wp on wp.assignment_id=a.id
 where s.event_id=e.id and (wp.id is not null or p.status='paid' or (a.status not in ('cancelled','reserve','no_show') and coalesce(p.status,'pending')<>'cancelled'))
 ) x;
 select coalesce((select sum(w.amount) from public.workforce_payments w join public.assignments a on a.id=w.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id),0)+coalesce((select sum(p.amount) from public.payments p join public.assignments a on a.id=p.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id and p.status='paid'),0) into paid;
 select coalesce(sum(coalesce(x.amount,r.amount)),0)+coalesce(f.extra_costs_amount,0),count(*) filter(where coalesce(x.amount,r.amount) is null) into expenses,unknown_expenses from public.work_expenses x left join public.work_expense_resolutions r on r.expense_id=x.id where x.event_id=e.id;
 if coalesce(f.extra_costs_amount,0)=0 then select coalesce(sum(p.amount),0) into expense_paid from public.work_expense_payments p join public.work_expenses x on x.id=p.expense_id where x.event_id=e.id; end if;
 return jsonb_build_object('event_id',e.id,'sale_source',case when c.id is not null then 'accepted_contract' when f.event_id is not null then 'legacy_contracted_gross' when exists(select 1 from public.work_sale_entries where event_id=e.id) then 'recorded_sale' else 'unknown' end,
 'sale_contracted',sale,'sale_received',received,'sale_receivable',sale-received,'sale_deductions',coalesce(f.deductions_amount,0),
 'labor_contracted',case when unknown_labor=0 then labor end,'labor_paid',paid,'labor_payable',case when unknown_labor=0 then labor-paid end,'unknown_labor_count',unknown_labor,
 'other_contracted',case when unknown_expenses=0 then expenses end,'other_paid',expense_paid,'other_payable',case when unknown_expenses=0 then expenses-expense_paid end,'unknown_expense_count',unknown_expenses,
 'estimated_result',case when unknown_labor=0 and unknown_expenses=0 then sale-labor-expenses-coalesce(f.deductions_amount,0) end,'result_label','estimated_before_unresolved_expenses_and_taxes',
 'expenses',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'label',x.label,'amount',coalesce(x.amount,(select amount from public.work_expense_resolutions where expense_id=x.id)),'receipt_reference',x.receipt_reference,'paid',coalesce((select sum(p.amount) from public.work_expense_payments p where p.expense_id=x.id),0)) order by x.created_at,x.id) from public.work_expenses x where x.event_id=e.id),'[]'::jsonb));
end $$;

create or replace function private.eventcore_work_assignment_dto(p_assignment uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'freelancer_id',a.freelancer_id,'event_service_id',s.id,'event_id',e.id,'event_name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,'event_status',e.status,'status',a.status,'function_name',s.label,
 'worker_name',(select full_name from public.freelancers where id=a.freelancer_id),'can_review',private.eventcore_can_manage_event(e.id) and not private.eventcore_owns_freelancer(a.freelancer_id) and private.eventcore_actual_completed_assignment(a.id) and not exists(select 1 from public.ratings where assignment_id=a.id),
 'legacy_agreed_amount',a.agreed_amount,'offered_terms',private.eventcore_terms_dto((select id from public.assignment_terms where assignment_id=a.id order by revision desc limit 1)),
 'accepted_terms',private.eventcore_terms_dto(private.eventcore_accepted_term(a.id)),
 'terms_history',coalesce((select jsonb_agg(private.eventcore_terms_dto(t.id) order by t.revision) from public.assignment_terms t where t.assignment_id=a.id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(x.row order by x.paid_at) from (
 select jsonb_build_object('id',p.id,'amount',p.amount,'status',p.status,'method',p.method,'paid_at',p.paid_at,'term_id',null) row,p.paid_at from public.payments p where p.assignment_id=a.id
 union all select jsonb_build_object('id',p.id,'amount',p.amount,'status','paid','method',p.method,'paid_at',p.paid_at,'term_id',p.term_id),p.paid_at from public.workforce_payments p where p.assignment_id=a.id) x),'[]'::jsonb),
 'completion_confirmed',private.eventcore_actual_completed_assignment(a.id))
 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where a.id=p_assignment;
$$;

create or replace function public.get_buyer_work_status(p_contract_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.commercial_contracts;
begin
 select * into c from public.commercial_contracts where id=p_contract_id;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) then raise exception 'forbidden'; end if;
 return jsonb_build_object('contract_id',c.id,'sale_total',c.sale_total,'quote',c.quote_snapshot,
 'received_total',coalesce((select sum(amount) from public.customer_receipts where contract_id=c.id),0),
 'work',(select jsonb_build_object('event_id',e.id,'name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,'status',e.status,'reviewed',exists(select 1 from public.provider_ratings where contract_id=c.id),'can_confirm',e.status='completed' and e.end_at<=now() and not private.eventcore_org_member(c.provider_organization_id),'completion_confirmed',exists(select 1 from public.contract_completion_confirmations where contract_id=c.id)) from public.events e where e.commercial_contract_id=c.id or exists(select 1 from public.work_contract_links l where l.event_id=e.id and l.contract_id=c.id)));
end $$;

create or replace function public.confirm_contract_completion(p_contract_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) or private.eventcore_org_member(c.provider_organization_id) then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.events where (commercial_contract_id=c.id or exists(select 1 from public.work_contract_links l where l.event_id=public.events.id and l.contract_id=c.id)) and status='completed' and end_at<=now()) then raise exception 'completed_event_required'; end if;
 insert into public.contract_completion_confirmations(contract_id,confirmed_by) values(c.id,auth.uid()) on conflict do nothing;
end $$;

create or replace function public.submit_provider_rating(p_contract_id uuid,p_rating integer,p_comment text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts; result uuid;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null or not private.eventcore_org_finance(c.buyer_organization_id) or private.eventcore_org_member(c.provider_organization_id) then raise exception 'forbidden'; end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>1000 then raise exception 'invalid_rating'; end if;
 if not exists(select 1 from public.contract_completion_confirmations where contract_id=c.id) then raise exception 'confirmed_completed_work_required'; end if;
 insert into public.provider_ratings(contract_id,reviewer_profile_id,rating,comment) values(c.id,auth.uid(),p_rating,nullif(trim(p_comment),'')) returning id into result;
 return result;
exception when unique_violation then raise exception 'provider_already_rated';
end $$;
