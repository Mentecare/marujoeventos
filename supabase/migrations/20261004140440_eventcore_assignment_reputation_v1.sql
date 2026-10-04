create or replace function private.guard_freelancer_assignment_update()
    returns trigger
    language plpgsql
    security definer
    set search_path=''
    as $$
    declare
      v_is_staff boolean := coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator');
      v_uid uuid := (select auth.uid());
      v_can_manage boolean := false;
    begin
      select private.eventcore_can_manage_event(es.event_id)
        into v_can_manage
      from public.event_services es
      where es.id=old.event_service_id;

      if v_is_staff or coalesce(v_can_manage,false) then
        return new;
      end if;

      if v_uid is null or not exists (
        select 1 from public.freelancers f
        where f.id=old.freelancer_id and f.profile_id=v_uid
      ) then
        raise exception 'assignment_not_owned';
      end if;

      if new.event_service_id is distinct from old.event_service_id
         or new.freelancer_id is distinct from old.freelancer_id
         or new.agreed_amount is distinct from old.agreed_amount
         or new.invited_at is distinct from old.invited_at
         or new.created_at is distinct from old.created_at
         or new.contractor_profile_id is distinct from old.contractor_profile_id
         or new.application_id is distinct from old.application_id
         or new.hired_at is distinct from old.hired_at then
        raise exception 'freelancer_may_only_change_status';
      end if;

      if new.status is distinct from old.status then
        if not (
          (old.status in ('invited','reserve') and new.status in ('confirmed','cancelled'))
          or (old.status='confirmed' and new.status in ('checked_in','cancelled'))
          or (old.status='checked_in' and new.status='checked_out')
        ) then
          raise exception 'invalid_assignment_status_transition';
        end if;
      end if;

      if new.status='confirmed' and old.status is distinct from 'confirmed' then
        new.confirmed_at := coalesce(old.confirmed_at,now());
      else
        new.confirmed_at := old.confirmed_at;
      end if;

      return new;
    end;
    $$;

    create or replace function private.eventcore_refresh_freelancer_stats(p_freelancer uuid)
    returns void
    language plpgsql
    security definer
    set search_path=''
    as $$
    begin
      update public.freelancers f
      set rating=coalesce((
            select round(avg(r.rating)::numeric,2)
            from public.ratings r
            where r.freelancer_id=p_freelancer
          ),0),
          completed_jobs=(
            select count(*)::int
            from public.assignments a
            where a.freelancer_id=p_freelancer and a.status='checked_out'
          ),
          updated_at=now()
      where f.id=p_freelancer;
    end;
    $$;

    create or replace function private.eventcore_stats_from_rating()
    returns trigger
    language plpgsql
    security definer
    set search_path=''
    as $$
    begin
      perform private.eventcore_refresh_freelancer_stats(coalesce(new.freelancer_id,old.freelancer_id));
      return coalesce(new,old);
    end;
    $$;

    drop trigger if exists trg_eventcore_rating_stats on public.ratings;
    create trigger trg_eventcore_rating_stats
      after insert or update or delete on public.ratings
      for each row execute function private.eventcore_stats_from_rating();

    create or replace function private.eventcore_stats_from_assignment()
    returns trigger
    language plpgsql
    security definer
    set search_path=''
    as $$
    begin
      perform private.eventcore_refresh_freelancer_stats(coalesce(new.freelancer_id,old.freelancer_id));
      return coalesce(new,old);
    end;
    $$;

    drop trigger if exists trg_eventcore_assignment_stats on public.assignments;
    create trigger trg_eventcore_assignment_stats
      after insert or update of status or delete on public.assignments
      for each row execute function private.eventcore_stats_from_assignment();

    create or replace function public.get_professional_directory()
    returns table (
      freelancer_id uuid,
      profile_id uuid,
      full_name text,
      city text,
      rating numeric,
      completed_jobs integer,
      review_count bigint,
      specialties text[]
    )
    language sql
    stable
    security definer
    set search_path=''
    as $$
      select f.id, f.profile_id, f.full_name, f.city, f.rating, f.completed_jobs,
             (select count(*) from public.ratings r where r.freelancer_id=f.id),
             coalesce((
               select array_agg(s.name order by s.sort_order,s.name)
               from public.profile_specialties ps
               join public.specialties s on s.id=ps.specialty_id
               where ps.profile_id=f.profile_id and s.active
             ), array[]::text[])
      from public.freelancers f
      where f.active
        and (
          private.eventcore_is_staff()
          or private.eventcore_profile_type() in ('team_lead','company','agency')
          or f.profile_id=(select auth.uid())
        )
      order by f.rating desc, f.completed_jobs desc, f.full_name;
    $$;

    revoke all on function public.get_professional_directory() from public,anon;
    grant execute on function public.get_professional_directory() to authenticated;
