-- Photos are uploaded/decoded by the server; private delivery is authorized before signing.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('eventcore-profile-photos','eventcore-profile-photos',false,3000000,array['image/webp']);

create table public.profile_photos (
  id uuid primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check(kind in ('avatar','portfolio')),
  slot smallint not null check((kind='avatar' and slot=0) or (kind='portfolio' and slot between 1 and 10)),
  object_path text not null unique,
  byte_size integer not null check(byte_size between 1 and 3000000),
  mime_type text not null default 'image/webp' check(mime_type='image/webp'),
  caption text check(char_length(caption)<=160),
  real_declared boolean not null check(real_declared),
  declared_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(profile_id,kind,slot),
  check(object_path=profile_id::text||'/'||id::text||'.webp')
);
alter table public.profile_photos enable row level security;
revoke all on public.profile_photos from anon,authenticated;
grant select on public.profile_photos to authenticated;

create function private.eventcore_can_view_photos(p_profile_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles actor where actor.id=(select auth.uid()) and actor.active)
    and exists(select 1 from public.profiles target where target.id=p_profile_id and target.active
      and (target.id=(select auth.uid()) or (
        (private.eventcore_is_staff() or private.eventcore_is_business()) and exists(
          select 1 from public.freelancers f where f.profile_id=target.id and f.active
            and (target.profile_type='freelancer' or private.eventcore_is_staff())
        )
      )));
$$;
revoke all on function private.eventcore_can_view_photos(uuid) from public,anon;
grant execute on function private.eventcore_can_view_photos(uuid) to authenticated;
create policy profile_photos_authorized_read on public.profile_photos for select to authenticated
  using(private.eventcore_can_view_photos(profile_id));

-- Restrictive policies prevent future permissive policies on other buckets from bypassing this API.
create policy eventcore_photos_server_insert on storage.objects as restrictive for insert to anon,authenticated
  with check(bucket_id<>'eventcore-profile-photos');
create policy eventcore_photos_server_update on storage.objects as restrictive for update to anon,authenticated
  using(bucket_id<>'eventcore-profile-photos') with check(bucket_id<>'eventcore-profile-photos');
create policy eventcore_photos_server_delete on storage.objects as restrictive for delete to anon,authenticated
  using(bucket_id<>'eventcore-profile-photos');
create policy eventcore_photos_server_read on storage.objects as restrictive for select to anon,authenticated
  using(bucket_id<>'eventcore-profile-photos');

create function public.get_profile_photo_collection(p_freelancer_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare target uuid;
begin
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and active) then raise exception 'forbidden';end if;
  if p_freelancer_id is null then target:=(select auth.uid());
  else
    if not (private.eventcore_is_staff() or private.eventcore_is_business() or private.eventcore_owns_freelancer(p_freelancer_id)) then raise exception 'forbidden';end if;
    select f.profile_id into target from public.freelancers f left join public.profiles p on p.id=f.profile_id
      where f.id=p_freelancer_id and f.active and (f.profile_id is null or (p.active and (p.profile_type='freelancer' or private.eventcore_is_staff())));
    if target is null then return '[]'::jsonb;end if;
  end if;
  if not private.eventcore_can_view_photos(target) then raise exception 'forbidden';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'caption',caption,'object_path',object_path,'created_at',created_at) order by kind,slot)
    from public.profile_photos where profile_id=target),'[]'::jsonb);
end $$;

create function public.save_profile_photo(p_photo_id uuid,p_kind text,p_caption text default null,p_real_declared boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); chosen smallint; path text; meta jsonb; previous text;
begin
  -- Serializes all uploads/deletes for this account, including simultaneous requests for slot 10.
  perform 1 from public.profiles where id=actor and active for update;
  if not found then raise exception 'forbidden';end if;
  if p_real_declared is distinct from true then raise exception 'real_photo_declaration_required';end if;
  if p_kind is null or p_kind not in ('avatar','portfolio') then raise exception 'invalid_photo_kind';end if;
  if char_length(p_caption)>160 then raise exception 'invalid_photo_caption';end if;
  if p_photo_id is null then raise exception 'invalid_photo_object';end if;
  path:=actor::text||'/'||p_photo_id::text||'.webp';
  select metadata into meta from storage.objects where bucket_id='eventcore-profile-photos' and name=path;
  if meta is null or meta->>'mimetype' is distinct from 'image/webp' or coalesce((meta->>'size')::bigint,0) not between 1 and 3000000 then raise exception 'invalid_photo_object';end if;
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

create function public.delete_profile_photo(p_photo_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
  perform 1 from public.profiles where id=actor and active for update;
  if not found then raise exception 'forbidden';end if;
  if exists(select 1 from public.profile_photos where id=p_photo_id and profile_id<>actor) then raise exception 'forbidden';end if;
  delete from public.profile_photos where id=p_photo_id and profile_id=actor;
end $$;
revoke all on function public.get_profile_photo_collection(uuid) from public,anon;
revoke all on function public.save_profile_photo(uuid,text,text,boolean) from public,anon;
revoke all on function public.delete_profile_photo(uuid) from public,anon;
grant execute on function public.get_profile_photo_collection(uuid) to authenticated;
grant execute on function public.save_profile_photo(uuid,text,text,boolean) to authenticated;
grant execute on function public.delete_profile_photo(uuid) to authenticated;
