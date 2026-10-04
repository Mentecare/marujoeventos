
create table if not exists public.google_oauth_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  refresh_token_enc text not null,
  access_token_enc text,
  access_expires_at timestamptz,
  scopes text[] not null default '{}',
  updated_at timestamptz not null default now()
);

alter table public.google_oauth_connections enable row level security;
revoke all on public.google_oauth_connections from anon, authenticated;

comment on table public.google_oauth_connections is 'Server-only encrypted Google OAuth credentials for EventCore. No browser role access.';

