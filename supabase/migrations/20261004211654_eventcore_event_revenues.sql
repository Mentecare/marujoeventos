-- Separate business prices from the sanitized event data visible to professionals.
-- This additive migration does not rewrite existing events, assignments or payments.
create table public.event_financials (
  event_id uuid primary key references public.events(id) on delete cascade,
  gross_amount numeric(12,2) not null check (gross_amount between 0 and 9999999999.99),
  deductions_amount numeric(12,2) not null default 0 check (deductions_amount between 0 and 9999999999.99),
  extra_costs_amount numeric(12,2) not null default 0 check (extra_costs_amount between 0 and 9999999999.99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deductions_within_revenue check (deductions_amount <= gross_amount)
);

alter table public.event_financials enable row level security;
revoke all on public.event_financials from public, anon, authenticated;
grant select, insert, update on public.event_financials to authenticated;
grant all on public.event_financials to service_role;

create policy event_financials_read on public.event_financials
  for select to authenticated
  using (private.eventcore_can_manage_event(event_id));
create policy event_financials_insert on public.event_financials
  for insert to authenticated
  with check (private.eventcore_can_manage_event(event_id));
create policy event_financials_update on public.event_financials
  for update to authenticated
  using (private.eventcore_can_manage_event(event_id))
  with check (private.eventcore_can_manage_event(event_id));

create function private.eventcore_touch_financials() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger event_financials_updated_at before update on public.event_financials
  for each row execute function private.eventcore_touch_financials();

comment on table public.event_financials is 'Client gross revenue, deductions and extra costs, restricted to event managers. Team costs are derived from assignments/payments.';
