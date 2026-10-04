create or replace function private.guard_job_application_update()
    returns trigger
    language plpgsql
    security definer
    set search_path=''
    as $$
    declare
      v_uid uuid := (select auth.uid());
      v_is_owner boolean := false;
      v_can_manage boolean := false;
    begin
      select exists (
        select 1 from public.freelancers f
        where f.id=old.freelancer_id and f.profile_id=v_uid
      ) into v_is_owner;

      select private.eventcore_can_manage_event(es.event_id)
      into v_can_manage
      from public.event_services es
      where es.id=old.event_service_id;

      if private.eventcore_is_staff() or coalesce(v_can_manage,false) then
        if new.event_service_id is distinct from old.event_service_id
           or new.freelancer_id is distinct from old.freelancer_id
           or new.created_at is distinct from old.created_at then
          raise exception 'application_identity_is_immutable';
        end if;
        return new;
      end if;

      if not v_is_owner then
        raise exception 'application_not_owned';
      end if;

      if new.event_service_id is distinct from old.event_service_id
         or new.freelancer_id is distinct from old.freelancer_id
         or new.created_at is distinct from old.created_at then
        raise exception 'application_identity_is_immutable';
      end if;

      if new.status is distinct from old.status
         and not (old.status in ('interested','shortlisted') and new.status='withdrawn') then
        raise exception 'freelancer_may_only_withdraw_application';
      end if;

      return new;
    end;
    $$;

    drop trigger if exists trg_guard_job_application_update on public.job_applications;
    create trigger trg_guard_job_application_update
      before update on public.job_applications
      for each row execute function private.guard_job_application_update();
