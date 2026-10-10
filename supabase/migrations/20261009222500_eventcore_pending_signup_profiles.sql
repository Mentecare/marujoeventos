-- EventCore: preserve one-time registration details until the email has been verified.
-- This is additive. It never updates existing accounts or commercial records.
create table if not exists public.pending_signup_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '30 days')
);
alter table public.pending_signup_profiles enable row level security;
revoke all on public.pending_signup_profiles from public,anon,authenticated;
grant select,insert,update,delete on public.pending_signup_profiles to service_role;
create index if not exists pending_signup_profiles_expiry_idx on public.pending_signup_profiles(expires_at);

-- SECURITY DEFINER is required to read a private draft and invoke the existing
-- authenticated complete_profile RPC in the same transaction.
create or replace function public.complete_pending_signup()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  draft public.pending_signup_profiles;
  already_completed boolean;
begin
  if actor is null then raise exception 'unauthorized'; end if;
  if not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null) then
    return jsonb_build_object('status','not_verified');
  end if;

  select * into draft from public.pending_signup_profiles
   where user_id=actor for update;
  if not found then return jsonb_build_object('status','missing'); end if;
  if draft.expires_at<=now() then
    delete from public.pending_signup_profiles where user_id=actor;
    return jsonb_build_object('status','expired');
  end if;

  select onboarding_completed into already_completed
    from public.profiles where id=actor and active for update;
  if not found then raise exception 'unauthorized'; end if;
  if already_completed then
    delete from public.pending_signup_profiles where user_id=actor;
    return jsonb_build_object('status','already_completed');
  end if;

  -- Reuse central validation, CPF uniqueness, profile specialization and tenant logic.
  -- Failure rolls the whole transaction back and retains this draft for recovery.
  perform public.complete_profile(draft.payload);
  delete from public.pending_signup_profiles where user_id=actor;
  return jsonb_build_object('status','completed');
end;
$$;
revoke all on function public.complete_pending_signup() from public,anon;
grant execute on function public.complete_pending_signup() to authenticated;
comment on table public.pending_signup_profiles is 'Private pre-verification signup payload. Service role only; removed after successful onboarding. Purge expired rows.';
notify pgrst,'reload schema';
