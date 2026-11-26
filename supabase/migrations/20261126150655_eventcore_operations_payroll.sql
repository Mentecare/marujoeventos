-- Additive operations: preserve all previous migrations, values and acceptance evidence.
-- Deploy to homologation first. Recovery: revoke new write RPCs; retain the immutable ledger.
create table public.assignment_payment_entries (
 id uuid primary key default gen_random_uuid(),
 assignment_id uuid not null references public.assignments(id) on delete restrict,
 term_id uuid references public.assignment_term_acceptances(term_id),
 amount numeric(12,2) not null check(amount>0),
 method text not null check(method in ('pix','transfer','cash','other')),
 payment_kind text not null check(payment_kind in ('advance','partial','settlement')),
 paid_on date not null,
 evidence_reference text check(length(evidence_reference)<=500),
 notes text check(length(notes)<=1000),
 idempotency_key text not null check(length(trim(idempotency_key)) between 1 and 100),
 recorded_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 unique(assignment_id,idempotency_key)
);
create table public.work_shifts (
 id uuid primary key default gen_random_uuid(),event_service_id uuid not null references public.event_services(id) on delete restrict,
 label text not null check(length(trim(label)) between 1 and 120),starts_at timestamptz not null,ends_at timestamptz not null,
 meeting_point text not null check(length(trim(meeting_point)) between 1 and 300),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 check(isfinite(starts_at) and isfinite(ends_at) and ends_at>starts_at)
);
create table public.work_shift_assignments (
 shift_id uuid not null references public.work_shifts(id) on delete restrict,
 assignment_id uuid not null references public.assignments(id) on delete restrict,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 primary key(shift_id,assignment_id)
);
create index work_shift_assignments_assignment_idx on public.work_shift_assignments(assignment_id);
create index work_shifts_service_idx on public.work_shifts(event_service_id);
create table public.assignment_replacements (
 id uuid primary key default gen_random_uuid(),
 previous_assignment_id uuid not null unique references public.assignments(id),
 replacement_assignment_id uuid not null unique references public.assignments(id),
 reason text not null check(length(trim(reason)) between 1 and 1000),
 recorded_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 check(previous_assignment_id<>replacement_assignment_id)
);

create function private.eventcore_payable_amount(p_assignment uuid) returns numeric language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.assignment_terms where assignment_id=a.id)
 then (select total from public.assignment_terms where id=private.eventcore_accepted_term(a.id))
 else coalesce((select amount from public.payments where assignment_id=a.id),a.agreed_amount) end
 from public.assignments a where a.id=p_assignment;
$$;
create function private.eventcore_paid_amount(p_assignment uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(amount) from public.payments where assignment_id=p_assignment and status='paid'),0)
 +coalesce((select sum(amount) from public.workforce_payments where assignment_id=p_assignment),0)
 +coalesce((select sum(amount) from public.assignment_payment_entries where assignment_id=p_assignment),0);
$$;
create function public.record_assignment_payment(p_assignment_id uuid,p_amount numeric,p_method text,p_paid_on date,p_payment_kind text,p_evidence_reference text,p_notes text,p_idempotency_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare a public.assignments; previous public.assignment_payment_entries; total numeric; paid numeric; result uuid;
begin
 perform private.eventcore_lock_work_assignment(p_assignment_id);
 if not private.eventcore_can_pay_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2)
 or p_method is null or p_method not in ('pix','transfer','cash','other') or p_payment_kind is null or p_payment_kind not in ('advance','partial','settlement')
 or p_paid_on is null or not isfinite(p_paid_on) or p_paid_on>private.eventcore_business_today()
 or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 or length(coalesce(p_evidence_reference,''))>500 or length(coalesce(p_notes,''))>1000 then raise exception 'invalid_installment'; end if;
 select * into previous from public.assignment_payment_entries where assignment_id=p_assignment_id and idempotency_key=p_idempotency_key;
 if previous.id is not null then
  if previous.amount<>p_amount or previous.method<>p_method or previous.paid_on<>p_paid_on or previous.payment_kind<>p_payment_kind
  or previous.evidence_reference is distinct from nullif(trim(p_evidence_reference),'') or previous.notes is distinct from nullif(trim(p_notes),'') then raise exception 'idempotency_conflict'; end if;
  return previous.id;
 end if;
 select * into a from public.assignments where id=p_assignment_id;
 if a.status not in ('confirmed','checked_in','checked_out') then raise exception 'worker_acceptance_required'; end if;
 total:=private.eventcore_payable_amount(a.id);paid:=private.eventcore_paid_amount(a.id);
 if total is null then raise exception 'worker_acceptance_required'; end if;
 if paid+p_amount>total then raise exception 'payment_exceeds_payable'; end if;
 if p_payment_kind='settlement' and paid+p_amount<>total then raise exception 'settlement_must_match_balance'; end if;
 if exists(select 1 from public.payments where assignment_id=a.id and status in ('held','cancelled')) then raise exception 'payment_on_hold'; end if;
 insert into public.assignment_payment_entries(assignment_id,term_id,amount,method,paid_on,payment_kind,evidence_reference,notes,idempotency_key,recorded_by)
 values(a.id,private.eventcore_accepted_term(a.id),p_amount,p_method,p_paid_on,p_payment_kind,nullif(trim(p_evidence_reference),''),nullif(trim(p_notes),''),p_idempotency_key,auth.uid()) returning id into result;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'assignment_installment_recorded','assignment_payment',result,jsonb_build_object('assignment_id',a.id));
 return result;
end $$;
-- Reads contain only the caller's own payroll, or an explicitly authorized event's payroll.
create function public.get_assignment_payment_entries(p_assignment_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() or not(private.eventcore_finances_assignment(p_assignment_id) or private.eventcore_owns_assignment(p_assignment_id)) then raise exception 'forbidden'; end if;
 return jsonb_build_object('total',private.eventcore_payable_amount(p_assignment_id),'paid',private.eventcore_paid_amount(p_assignment_id),
 'balance',private.eventcore_payable_amount(p_assignment_id)-private.eventcore_paid_amount(p_assignment_id),
 'entries',coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount',amount,'method',method,'paid_on',paid_on,'payment_kind',payment_kind,'evidence_reference',evidence_reference,'notes',notes) order by paid_on,created_at,id) from public.assignment_payment_entries where assignment_id=p_assignment_id),'[]'::jsonb));
end $$;
-- Preserve accepted conditions after the first partial payment, including pending revisions.
create function private.eventcore_partial_payment_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 if tg_table_name='assignment_terms' then aid:=new.assignment_id;
 elsif tg_table_name='assignment_term_acceptances' then select assignment_id into aid from public.assignment_terms where id=new.term_id;
 else aid:=new.id; if new.status not in ('cancelled','reserve','no_show') or new.status=old.status then return new; end if;
 end if;
 if exists(select 1 from public.assignment_payment_entries where assignment_id=aid) then raise exception 'assignment_has_installments'; end if;
 return new;
end $$;
create trigger b_installments_terms before insert on public.assignment_terms for each row execute function private.eventcore_partial_payment_guard();
create trigger b_installments_acceptance before insert on public.assignment_term_acceptances for each row execute function private.eventcore_partial_payment_guard();
create trigger b_installments_assignment before update on public.assignments for each row execute function private.eventcore_partial_payment_guard();

create function public.create_work_shift(p_service_id uuid,p_label text,p_starts_at timestamptz,p_ends_at timestamptz,p_meeting_point text) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.event_services; e public.events; result uuid;
begin
 select * into s from public.event_services where id=p_service_id for update;
 select * into e from public.events where id=s.event_id for update;
 if not private.eventcore_can_hire_event(e.id) then raise exception 'forbidden'; end if;
 if e.status in ('completed','cancelled') or e.end_at is null or e.end_at<=now() then raise exception 'event_closed'; end if;
 if p_starts_at is null or p_ends_at is null or not isfinite(p_starts_at) or not isfinite(p_ends_at) or p_starts_at<e.start_at or p_ends_at>e.end_at or p_starts_at>=p_ends_at or p_starts_at<=now()
 or length(trim(coalesce(p_label,''))) not between 1 and 120 or length(trim(coalesce(p_meeting_point,''))) not between 1 and 300 then raise exception 'invalid_shift'; end if;
 insert into public.work_shifts(event_service_id,label,starts_at,ends_at,meeting_point,created_by) values(s.id,trim(p_label),p_starts_at,p_ends_at,trim(p_meeting_point),auth.uid()) returning id into result;
 return result;
end $$;
create function public.set_work_shift_assignment(p_shift_id uuid,p_assignment_id uuid,p_assigned boolean) returns void
language plpgsql security definer set search_path='' as $$
declare eid uuid; sh public.work_shifts; a public.assignments;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 select * into sh from public.work_shifts where id=p_shift_id;
 if not private.eventcore_can_hire_event(eid) or sh.event_service_id is distinct from a.event_service_id or p_assigned is null then raise exception 'forbidden'; end if;
 if sh.starts_at<=now() or a.status not in ('invited','confirmed') or exists(select 1 from public.events where id=eid and status in ('completed','cancelled'))
 or exists(select 1 from public.attendance where assignment_id=a.id and check_in_at is not null) then raise exception 'schedule_locked'; end if;
 -- Serialize cross-event overlap checks for a single professional.
 perform 1 from public.freelancers where id=a.freelancer_id for update;
 if p_assigned then
  if exists(select 1 from public.work_shift_assignments sa join public.work_shifts os on os.id=sa.shift_id join public.assignments oa on oa.id=sa.assignment_id
   where oa.freelancer_id=a.freelancer_id and oa.status in ('invited','confirmed','checked_in','checked_out') and os.id<>sh.id and sh.starts_at<os.ends_at and sh.ends_at>os.starts_at) then raise exception 'worker_shift_conflict'; end if;
  insert into public.work_shift_assignments(shift_id,assignment_id,created_by) values(sh.id,a.id,auth.uid()) on conflict do nothing;
 else delete from public.work_shift_assignments where shift_id=sh.id and assignment_id=a.id;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'shift_assignment_updated','work_shift',sh.id,jsonb_build_object('assignment_id',a.id,'assigned',p_assigned));
end $$;
create function public.get_work_shifts(p_event_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if p_event_id is not null and not private.eventcore_can_manage_event(p_event_id) then raise exception 'forbidden'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',sh.id,'event_service_id',sh.event_service_id,'event_id',s.event_id,'label',sh.label,'starts_at',sh.starts_at,'ends_at',sh.ends_at,'meeting_point',sh.meeting_point,
 'assignment_ids',coalesce((select jsonb_agg(sa.assignment_id order by sa.assignment_id) from public.work_shift_assignments sa where sa.shift_id=sh.id and (p_event_id is not null or private.eventcore_owns_assignment(sa.assignment_id))),'[]'::jsonb)) order by sh.starts_at,sh.id)
 from public.work_shifts sh join public.event_services s on s.id=sh.event_service_id
 where (p_event_id is not null and s.event_id=p_event_id) or (p_event_id is null and exists(select 1 from public.work_shift_assignments sa where sa.shift_id=sh.id and private.eventcore_owns_assignment(sa.assignment_id)))),'[]'::jsonb);
end $$;

create function public.replace_event_assignment(p_assignment_id uuid,p_replacement_freelancer_id uuid,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare eid uuid; a public.assignments; result uuid; sh record;
begin
 eid:=private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 if not private.eventcore_can_hire_event(eid) or not private.eventcore_can_finance_event(eid) then raise exception 'forbidden'; end if;
 if a.freelancer_id=p_replacement_freelancer_id or length(trim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'invalid_replacement'; end if;
 if exists(select 1 from public.events where id=eid and (status in ('completed','cancelled') or end_at<=now())) then raise exception 'event_closed'; end if;
 if a.status not in ('invited','confirmed','reserve','cancelled','no_show') or exists(select 1 from public.attendance where assignment_id=a.id and check_in_at is not null)
 or private.eventcore_paid_amount(a.id)>0 or exists(select 1 from public.assignment_replacements where previous_assignment_id=a.id) then raise exception 'replacement_evidence_locked'; end if;
 if a.status not in ('cancelled','no_show') then update public.assignments set status='cancelled' where id=a.id; end if;
 result:=public.create_event_assignment(a.event_service_id,p_replacement_freelancer_id,'invited');
 for sh in select shift_id from public.work_shift_assignments where assignment_id=a.id loop
  perform public.set_work_shift_assignment(sh.shift_id,result,true);
 end loop;
 insert into public.assignment_replacements(previous_assignment_id,replacement_assignment_id,reason,recorded_by) values(a.id,result,trim(p_reason),auth.uid());
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'assignment_replaced','assignment',a.id,jsonb_build_object('replacement_assignment_id',result));
 return result;
end $$;

alter table public.assignment_payment_entries enable row level security;
alter table public.work_shifts enable row level security;
alter table public.work_shift_assignments enable row level security;
alter table public.assignment_replacements enable row level security;
revoke all on public.assignment_payment_entries,public.work_shifts,public.work_shift_assignments,public.assignment_replacements from anon,authenticated;
grant select on public.assignment_payment_entries,public.work_shifts,public.work_shift_assignments,public.assignment_replacements to authenticated;
create policy payroll_own_or_finance on public.assignment_payment_entries for select to authenticated using(private.eventcore_finances_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
create policy shift_participant on public.work_shifts for select to authenticated using(exists(select 1 from public.event_services s where s.id=event_service_id and private.eventcore_can_manage_event(s.event_id)) or exists(select 1 from public.work_shift_assignments sa where sa.shift_id=id and private.eventcore_owns_assignment(sa.assignment_id)));
create policy shift_assignment_participant on public.work_shift_assignments for select to authenticated using(private.eventcore_owns_assignment(assignment_id) or exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id where a.id=assignment_id and private.eventcore_can_manage_event(s.event_id)));
create policy replacement_operator on public.assignment_replacements for select to authenticated using(exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id where a.id=previous_assignment_id and private.eventcore_can_manage_event(s.event_id)));
create trigger payroll_immutable before update or delete on public.assignment_payment_entries for each row execute function private.eventcore_commercial_immutable();
create trigger shifts_immutable before update or delete on public.work_shifts for each row execute function private.eventcore_commercial_immutable();
create trigger replacement_immutable before update or delete on public.assignment_replacements for each row execute function private.eventcore_commercial_immutable();
revoke all on function private.eventcore_payable_amount(uuid),private.eventcore_paid_amount(uuid),private.eventcore_partial_payment_guard() from public,anon,authenticated;
revoke all on function public.record_assignment_payment(uuid,numeric,text,date,text,text,text,text),public.get_assignment_payment_entries(uuid),public.create_work_shift(uuid,text,timestamptz,timestamptz,text),public.set_work_shift_assignment(uuid,uuid,boolean),public.get_work_shifts(uuid),public.replace_event_assignment(uuid,uuid,text) from public,anon;
grant execute on function public.record_assignment_payment(uuid,numeric,text,date,text,text,text,text),public.get_assignment_payment_entries(uuid),public.create_work_shift(uuid,text,timestamptz,timestamptz,text),public.set_work_shift_assignment(uuid,uuid,boolean),public.get_work_shifts(uuid),public.replace_event_assignment(uuid,uuid,text) to authenticated;

-- The retained one-click settlement uses only the balance when installments exist.
create or replace function public.mark_assignment_paid(p_assignment_id uuid,p_method text) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; amount numeric; tid uuid; remaining numeric;
begin
 perform private.eventcore_lock_work_assignment(p_assignment_id);
 select * into a from public.assignments where id=p_assignment_id;
 if not private.eventcore_can_pay_assignment(a.id) then raise exception 'forbidden'; end if;
 if exists(select 1 from public.assignment_payment_entries where assignment_id=a.id) then
  remaining:=private.eventcore_payable_amount(a.id)-private.eventcore_paid_amount(a.id);
  if remaining=0 then return; end if;
  perform public.record_assignment_payment(a.id,remaining,p_method,private.eventcore_business_today(),'settlement',null,null,'legacy-settle-balance');return;
 end if;
 if a.status in ('cancelled','reserve','no_show') or p_method is null or p_method not in ('pix','transfer','cash','other') then raise exception 'invalid_payment'; end if;
 if exists(select 1 from public.assignment_terms where assignment_id=a.id) then
  tid:=private.eventcore_accepted_term(a.id);
  if tid is null then raise exception 'worker_acceptance_required'; end if;
  select total into amount from public.assignment_terms where id=tid;
  if amount is null or amount<=0 then raise exception 'payment_amount_required'; end if;
  if exists(select 1 from public.workforce_payments where assignment_id=a.id) then return; end if;
  insert into public.workforce_payments(assignment_id,term_id,amount,method,paid_by) values(a.id,tid,amount,p_method,auth.uid());
 else
  select p.amount into amount from public.payments p where p.assignment_id=a.id;
  amount:=coalesce(amount,a.agreed_amount);
  if amount is null or amount not between 0.01 and 9999999999.99 then raise exception 'payment_amount_required'; end if;
  if exists(select 1 from public.payments where assignment_id=a.id and status='paid') then return; end if;
  insert into public.payments(assignment_id,amount,status,method,paid_at) values(a.id,amount,'paid',p_method,now()) on conflict(assignment_id) do update set status='paid',method=excluded.method,paid_at=excluded.paid_at,updated_at=now();
 end if;
end $$;

-- Aggregate partial payments once, without changing contracted cost.
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
 select coalesce((select sum(w.amount) from public.workforce_payments w join public.assignments a on a.id=w.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id),0)+coalesce((select sum(p.amount) from public.payments p join public.assignments a on a.id=p.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id and p.status='paid'),0)+coalesce((select sum(ip.amount) from public.assignment_payment_entries ip join public.assignments a on a.id=ip.assignment_id join public.event_services s on s.id=a.event_service_id where s.event_id=e.id),0) into paid;
 select coalesce(sum(coalesce(x.amount,r.amount)),0)+coalesce(f.extra_costs_amount,0),count(*) filter(where coalesce(x.amount,r.amount) is null) into expenses,unknown_expenses from public.work_expenses x left join public.work_expense_resolutions r on r.expense_id=x.id where x.event_id=e.id;
 if coalesce(f.extra_costs_amount,0)=0 then select coalesce(sum(p.amount),0) into expense_paid from public.work_expense_payments p join public.work_expenses x on x.id=p.expense_id where x.event_id=e.id; end if;
 return jsonb_build_object('event_id',e.id,'sale_source',case when c.id is not null then 'accepted_contract' when f.event_id is not null then 'legacy_contracted_gross' when exists(select 1 from public.work_sale_entries where event_id=e.id) then 'recorded_sale' else 'unknown' end,
 'sale_contracted',sale,'sale_received',received,'sale_receivable',sale-received,'sale_deductions',coalesce(f.deductions_amount,0),
 'labor_contracted',case when unknown_labor=0 then labor end,'labor_paid',paid,'labor_payable',case when unknown_labor=0 then labor-paid end,'unknown_labor_count',unknown_labor,
 'other_contracted',case when unknown_expenses=0 then expenses end,'other_paid',expense_paid,'other_payable',case when unknown_expenses=0 then expenses-expense_paid end,'unknown_expense_count',unknown_expenses,
 'estimated_result',case when unknown_labor=0 and unknown_expenses=0 then sale-labor-expenses-coalesce(f.deductions_amount,0) end,'result_label','estimated_before_unresolved_expenses_and_taxes',
 'expenses',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'label',x.label,'amount',coalesce(x.amount,(select amount from public.work_expense_resolutions where expense_id=x.id)),'receipt_reference',x.receipt_reference,'paid',coalesce((select sum(p.amount) from public.work_expense_payments p where p.expense_id=x.id),0)) order by x.created_at,x.id) from public.work_expenses x where x.event_id=e.id),'[]'::jsonb));
end $$;

-- Keep the existing projection shape; each participant sees only authorized own rows.
create or replace function private.eventcore_work_assignment_dto(p_assignment uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'freelancer_id',a.freelancer_id,'event_service_id',s.id,'event_id',e.id,'event_name',e.name,'venue',e.venue,'start_at',e.start_at,'end_at',e.end_at,'event_status',e.status,'status',a.status,'function_name',s.label,
 'worker_name',(select full_name from public.freelancers where id=a.freelancer_id),'can_review',private.eventcore_can_manage_event(e.id) and not private.eventcore_owns_freelancer(a.freelancer_id) and private.eventcore_actual_completed_assignment(a.id) and not exists(select 1 from public.ratings where assignment_id=a.id),
 'legacy_agreed_amount',a.agreed_amount,'offered_terms',private.eventcore_terms_dto((select id from public.assignment_terms where assignment_id=a.id order by revision desc limit 1)),
 'accepted_terms',private.eventcore_terms_dto(private.eventcore_accepted_term(a.id)),
 'terms_history',coalesce((select jsonb_agg(private.eventcore_terms_dto(t.id) order by t.revision) from public.assignment_terms t where t.assignment_id=a.id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(x.row order by x.paid_at) from (
 select jsonb_build_object('id',p.id,'amount',p.amount,'status',p.status,'method',p.method,'paid_at',p.paid_at,'term_id',null) row,p.paid_at from public.payments p where p.assignment_id=a.id
 union all select jsonb_build_object('id',p.id,'amount',p.amount,'status','paid','method',p.method,'paid_at',p.paid_at,'term_id',p.term_id),p.paid_at from public.workforce_payments p where p.assignment_id=a.id
 union all select jsonb_build_object('id',ip.id,'amount',ip.amount,'status','paid','method',ip.method,'paid_at',ip.paid_on::timestamp at time zone 'America/Sao_Paulo','term_id',ip.term_id),ip.paid_on::timestamp at time zone 'America/Sao_Paulo' from public.assignment_payment_entries ip where ip.assignment_id=a.id) x),'[]'::jsonb),
 'completion_confirmed',private.eventcore_actual_completed_assignment(a.id))
 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id where a.id=p_assignment;
$$;

-- Event edits must keep previously defined shifts inside the contracted event window.
create function private.eventcore_shift_event_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at) and exists(select 1 from public.work_shifts sh join public.event_services s on s.id=sh.event_service_id where s.event_id=old.id and (sh.starts_at<new.start_at or new.end_at is null or sh.ends_at>new.end_at)) then raise exception 'existing_shifts_outside_event'; end if;
 return new;
end $$;
create trigger b_shift_event_window before update on public.events for each row execute function private.eventcore_shift_event_guard();
revoke all on function private.eventcore_shift_event_guard() from public,anon,authenticated;
