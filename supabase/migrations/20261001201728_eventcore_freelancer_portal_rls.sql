
create policy "freelancers read assigned event services"
on public.event_services
for select
to authenticated
using (
  exists (
    select 1
    from public.assignments a
    join public.freelancers f on f.id = a.freelancer_id
    where a.event_service_id = event_services.id
      and f.profile_id = (select auth.uid())
  )
);

create policy "freelancers read assigned events"
on public.events
for select
to authenticated
using (
  exists (
    select 1
    from public.event_services es
    join public.assignments a on a.event_service_id = es.id
    join public.freelancers f on f.id = a.freelancer_id
    where es.event_id = events.id
      and f.profile_id = (select auth.uid())
  )
);

create or replace function private.guard_freelancer_assignment_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_staff boolean := coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator');
  v_uid uuid := (select auth.uid());
begin
  if v_is_staff then
    return new;
  end if;

  if v_uid is null or not exists (
    select 1
    from public.freelancers f
    where f.id = old.freelancer_id
      and f.profile_id = v_uid
  ) then
    raise exception 'assignment_not_owned';
  end if;

  if new.event_service_id is distinct from old.event_service_id
     or new.freelancer_id is distinct from old.freelancer_id
     or new.agreed_amount is distinct from old.agreed_amount
     or new.invited_at is distinct from old.invited_at
     or new.created_at is distinct from old.created_at then
    raise exception 'freelancer_may_only_change_status';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status in ('invited','reserve') and new.status in ('confirmed','cancelled'))
      or (old.status = 'confirmed' and new.status in ('checked_in','cancelled'))
      or (old.status = 'checked_in' and new.status = 'checked_out')
    ) then
      raise exception 'invalid_assignment_status_transition';
    end if;
  end if;

  if new.status = 'confirmed' and old.status is distinct from 'confirmed' then
    new.confirmed_at := coalesce(old.confirmed_at, now());
  else
    new.confirmed_at := old.confirmed_at;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_freelancer_assignment_update() from public, anon, authenticated;

drop trigger if exists guard_freelancer_assignment_update on public.assignments;
create trigger guard_freelancer_assignment_update
before update on public.assignments
for each row
execute function private.guard_freelancer_assignment_update();

create policy "freelancers update own assignment status"
on public.assignments
for update
to authenticated
using (
  exists (
    select 1
    from public.freelancers f
    where f.id = assignments.freelancer_id
      and f.profile_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.freelancers f
    where f.id = assignments.freelancer_id
      and f.profile_id = (select auth.uid())
  )
);

