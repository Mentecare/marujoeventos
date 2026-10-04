
create extension if not exists pgcrypto;
create schema if not exists private;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role text not null default 'freelancer' check (role in ('admin','coordinator','freelancer','client')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.freelancers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  full_name text not null,
  phone text,
  city text,
  active boolean not null default true,
  rating numeric(2,1) not null default 5.0 check (rating >= 0 and rating <= 5),
  completed_jobs integer not null default 0 check (completed_jobs >= 0),
  no_show_count integer not null default 0 check (no_show_count >= 0),
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  legal_name text,
  trade_name text not null,
  tax_id text,
  contact_name text,
  email text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.proposals (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  title text not null,
  event_date date,
  venue text,
  status text not null default 'draft' check (status in ('draft','sent','accepted','rejected','cancelled')),
  client_total numeric(12,2) not null default 0 check (client_total >= 0),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.proposal_items (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals(id) on delete cascade,
  service_type text not null check (service_type in ('loader','security','waiter','other')),
  label text not null,
  quantity integer not null check (quantity > 0),
  client_unit_price numeric(12,2) not null check (client_unit_price >= 0),
  freelancer_unit_cost numeric(12,2) check (freelancer_unit_cost is null or freelancer_unit_cost >= 0),
  planned_hours numeric(6,2) check (planned_hours is null or planned_hours >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid unique references public.proposals(id) on delete set null,
  client_id uuid not null references public.clients(id) on delete restrict,
  name text not null,
  venue text not null,
  start_at timestamptz not null,
  end_at timestamptz,
  status text not null default 'planning' check (status in ('planning','staffing','confirmed','in_progress','completed','cancelled')),
  arrival_tolerance_minutes integer not null default 15 check (arrival_tolerance_minutes >= 0),
  coordinator_id uuid references public.profiles(id) on delete set null,
  notes text,
  google_calendar_id text,
  google_event_id text,
  calendar_sync_status text not null default 'not_linked'
    check (calendar_sync_status in ('not_linked','pending','synced','out_of_sync','error')),
  calendar_last_synced_at timestamptz,
  calendar_last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.event_services (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  service_type text not null check (service_type in ('loader','security','waiter','other')),
  label text not null,
  quantity_needed integer not null check (quantity_needed > 0),
  reserve_target integer not null default 0 check (reserve_target >= 0),
  freelancer_unit_cost numeric(12,2) check (freelancer_unit_cost is null or freelancer_unit_cost >= 0),
  briefing text,
  created_at timestamptz not null default now()
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  event_service_id uuid not null references public.event_services(id) on delete cascade,
  freelancer_id uuid not null references public.freelancers(id) on delete restrict,
  status text not null default 'invited'
    check (status in ('invited','confirmed','reserve','cancelled','checked_in','checked_out','no_show')),
  agreed_amount numeric(12,2) check (agreed_amount is null or agreed_amount >= 0),
  invited_at timestamptz not null default now(),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_service_id, freelancer_id)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.assignments(id) on delete cascade,
  check_in_at timestamptz,
  check_in_lat numeric(9,6),
  check_in_lng numeric(9,6),
  check_out_at timestamptz,
  check_out_lat numeric(9,6),
  check_out_lng numeric(9,6),
  evidence_path text,
  validated_by uuid references public.profiles(id) on delete set null,
  validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.assignments(id) on delete restrict,
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'pending' check (status in ('pending','approved','paid','held','cancelled')),
  method text check (method is null or method in ('pix','transfer','cash','other')),
  paid_at timestamptz,
  receipt_path text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.absence_records (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  freelancer_id uuid not null references public.freelancers(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete restrict,
  reason text,
  recorded_by uuid references public.profiles(id) on delete set null,
  reversal_of uuid references public.absence_records(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('freelancer','event','assignment','client','proposal')),
  entity_id uuid not null,
  document_type text not null,
  storage_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','expired')),
  uploaded_by uuid references public.profiles(id) on delete set null,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_proposals_client on public.proposals(client_id);
create index idx_events_client on public.events(client_id);
create index idx_events_start on public.events(start_at);
create unique index idx_events_google_event
  on public.events (google_calendar_id, google_event_id)
  where google_event_id is not null;
create index idx_event_services_event on public.event_services(event_id);
create index idx_assignments_service on public.assignments(event_service_id);
create index idx_assignments_freelancer on public.assignments(freelancer_id);
create index idx_payments_status on public.payments(status);
create index idx_absence_freelancer on public.absence_records(freelancer_id);
create index idx_audit_entity on public.audit_logs(entity_type, entity_id);

alter table public.profiles enable row level security;
alter table public.freelancers enable row level security;
alter table public.clients enable row level security;
alter table public.proposals enable row level security;
alter table public.proposal_items enable row level security;
alter table public.events enable row level security;
alter table public.event_services enable row level security;
alter table public.assignments enable row level security;
alter table public.attendance enable row level security;
alter table public.payments enable row level security;
alter table public.absence_records enable row level security;
alter table public.documents enable row level security;
alter table public.audit_logs enable row level security;

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on public.freelancers, public.clients, public.proposals,
  public.proposal_items, public.events, public.event_services, public.assignments,
  public.attendance, public.payments, public.documents to authenticated;
grant select, insert on public.absence_records, public.audit_logs to authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, phone, updated_at) on public.profiles to authenticated;
grant usage, select on all sequences in schema public to authenticated;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, public;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

create policy "profiles read self or staff" on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator')
);

create policy "profiles update self or staff" on public.profiles
for update to authenticated
using (
  id = (select auth.uid())
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator')
)
with check (
  id = (select auth.uid())
  or coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator')
);

create policy "staff manage freelancers" on public.freelancers
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "freelancers read own record" on public.freelancers
for select to authenticated
using (profile_id = (select auth.uid()));

create policy "staff manage clients" on public.clients
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff manage proposals" on public.proposals
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff manage proposal items" on public.proposal_items
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff manage events" on public.events
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff manage event services" on public.event_services
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff manage assignments" on public.assignments
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "freelancers read own assignments" on public.assignments
for select to authenticated
using (
  exists (
    select 1 from public.freelancers f
    where f.id = assignments.freelancer_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "staff manage attendance" on public.attendance
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "freelancers read own attendance" on public.attendance
for select to authenticated
using (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.id = attendance.assignment_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "freelancers insert own attendance" on public.attendance
for insert to authenticated
with check (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.id = attendance.assignment_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "freelancers update own attendance" on public.attendance
for update to authenticated
using (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.id = attendance.assignment_id
      and f.profile_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.id = attendance.assignment_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "staff manage payments" on public.payments
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "freelancers read own payments" on public.payments
for select to authenticated
using (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.id = payments.assignment_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "staff read absence records" on public.absence_records
for select to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff insert absence records" on public.absence_records
for insert to authenticated
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "freelancers read own absences" on public.absence_records
for select to authenticated
using (
  exists (
    select 1 from public.freelancers f
    where f.id = absence_records.freelancer_id
      and f.profile_id = (select auth.uid())
  )
);

create policy "staff manage documents" on public.documents
for all to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'))
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff read audit" on public.audit_logs
for select to authenticated
using (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create policy "staff insert audit" on public.audit_logs
for insert to authenticated
with check (coalesce(auth.jwt()->'app_metadata'->>'role','') in ('admin','coordinator'));

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), nullif(split_part(coalesce(new.email,''),'@',1),''), 'Usuário'),
    nullif(new.raw_user_meta_data->>'phone',''),
    'freelancer'
  );
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

comment on column public.events.google_event_id is
  'Google Calendar event ID used for idempotent EventCore synchronization.';

