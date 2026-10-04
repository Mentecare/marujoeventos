
create table if not exists public.integrations (
  id uuid primary key default gen_random_uuid(),
  kind text not null unique,
  account_email text,
  status text not null default 'disconnected' check (status in ('disconnected','connected','error')),
  connected_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.integrations enable row level security;

grant select, insert, update on public.integrations to authenticated;

create policy "staff manage integrations"
on public.integrations
for all
to authenticated
using (
  coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator')
)
with check (
  coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator')
);

