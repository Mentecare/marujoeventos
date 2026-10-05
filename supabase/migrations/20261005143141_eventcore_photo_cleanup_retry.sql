-- Durable retries: remove profile metadata first, retain the private object path until Storage confirms cleanup.
create table public.profile_photo_cleanup (
  object_path text primary key,
  profile_id uuid not null,
  not_before timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check(object_path like profile_id::text||'/%')
);
create index profile_photo_cleanup_actor_due on public.profile_photo_cleanup(profile_id,not_before);
alter table public.profile_photo_cleanup enable row level security;
revoke all on public.profile_photo_cleanup from public,anon,authenticated;
grant select,insert,update,delete on public.profile_photo_cleanup to service_role;

create function private.eventcore_queue_photo_cleanup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if TG_OP='DELETE' or (TG_OP='UPDATE' and OLD.object_path is distinct from NEW.object_path) then
    insert into public.profile_photo_cleanup(object_path,profile_id,not_before) values(OLD.object_path,OLD.profile_id,now())
      on conflict(object_path) do update set not_before=least(public.profile_photo_cleanup.not_before,excluded.not_before);
  end if;
  if TG_OP<>'DELETE' then delete from public.profile_photo_cleanup where object_path=NEW.object_path;end if;
  return null;
end $$;
revoke all on function private.eventcore_queue_photo_cleanup() from public,anon,authenticated;
create trigger eventcore_queue_photo_cleanup after insert or update or delete on public.profile_photos
  for each row execute function private.eventcore_queue_photo_cleanup();

create or replace function public.save_profile_photo(p_photo_id uuid,p_kind text,p_caption text default null,p_real_declared boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); chosen smallint; path text; meta jsonb; previous text;
begin
  perform 1 from public.profiles where id=actor and active for update;
  if not found then raise exception 'forbidden';end if;
  if p_real_declared is distinct from true then raise exception 'real_photo_declaration_required';end if;
  if p_kind is null or p_kind not in ('avatar','portfolio') then raise exception 'invalid_photo_kind';end if;
  if char_length(p_caption)>160 then raise exception 'invalid_photo_caption';end if;
  if p_photo_id is null then raise exception 'invalid_photo_object';end if;
  path:=actor::text||'/'||p_photo_id::text||'.webp';
  select metadata into meta from storage.objects where bucket_id='eventcore-profile-photos' and name=path;
  if meta is null or meta->>'mimetype' is distinct from 'image/webp' or coalesce((meta->>'size')::bigint,0) not between 1 and 3000000
    or exists(select 1 from public.profile_photo_cleanup where object_path=path and not_before<=now()) then raise exception 'invalid_photo_object';end if;
  if p_kind='avatar' then
    chosen:=0;
    select object_path into previous from public.profile_photos where profile_id=actor and kind='avatar';
  else
    select n::smallint into chosen from generate_series(1,10) n where not exists(select 1 from public.profile_photos p where p.profile_id=actor and p.kind='portfolio' and p.slot=n) order by n limit 1;
    if chosen is null then raise exception 'portfolio_full';end if;
  end if;
  insert into public.profile_photos(id,profile_id,kind,slot,object_path,byte_size,caption,real_declared)
    values(p_photo_id,actor,p_kind,chosen,path,(meta->>'size')::int,nullif(btrim(p_caption),''),true)
    on conflict(profile_id,kind,slot) do update set id=excluded.id,object_path=excluded.object_path,byte_size=excluded.byte_size,caption=excluded.caption,real_declared=true,declared_at=now(),created_at=now();
  return jsonb_build_object('id',p_photo_id,'previous_object_path',previous);
end $$;
