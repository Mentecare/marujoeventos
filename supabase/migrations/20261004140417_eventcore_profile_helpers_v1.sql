create or replace function private.eventcore_is_staff()
    returns boolean
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select coalesce((select auth.jwt())->'app_metadata'->>'role','') in ('admin','coordinator')
         or exists (
           select 1 from public.profiles p
           where p.id=(select auth.uid()) and p.active and p.role in ('admin','coordinator')
         );
    $$;

    create or replace function private.eventcore_profile_type()
    returns text
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select p.profile_type
      from public.profiles p
      where p.id=(select auth.uid()) and p.active;
    $$;

    create or replace function private.eventcore_org_member(p_org uuid)
    returns boolean
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select private.eventcore_is_staff()
         or exists (
           select 1 from public.organizations o
           where o.id=p_org and o.active and o.owner_profile_id=(select auth.uid())
         )
         or exists (
           select 1 from public.organization_members om
           where om.organization_id=p_org
             and om.profile_id=(select auth.uid())
             and om.active
         );
    $$;

    create or replace function private.eventcore_org_manager(p_org uuid)
    returns boolean
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select private.eventcore_is_staff()
         or exists (
           select 1 from public.organizations o
           where o.id=p_org and o.active and o.owner_profile_id=(select auth.uid())
         )
         or exists (
           select 1 from public.organization_members om
           where om.organization_id=p_org
             and om.profile_id=(select auth.uid())
             and om.active
             and om.member_role in ('owner','manager')
         );
    $$;

    create or replace function private.eventcore_can_manage_event(p_event uuid)
    returns boolean
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select private.eventcore_is_staff()
         or exists (
           select 1 from public.events e
           where e.id=p_event and (
             e.created_by_profile_id=(select auth.uid())
             or e.coordinator_id=(select auth.uid())
             or (e.organization_id is not null and private.eventcore_org_manager(e.organization_id))
           )
         );
    $$;

    grant usage on schema private to authenticated;
    grant execute on function private.eventcore_is_staff() to authenticated;
    grant execute on function private.eventcore_profile_type() to authenticated;
    grant execute on function private.eventcore_org_member(uuid) to authenticated;
    grant execute on function private.eventcore_org_manager(uuid) to authenticated;
    grant execute on function private.eventcore_can_manage_event(uuid) to authenticated;
