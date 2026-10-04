alter table public.specialties enable row level security;
    alter table public.profile_specialties enable row level security;
    alter table public.profile_private_identity enable row level security;
    alter table public.organizations enable row level security;
    alter table public.organization_members enable row level security;
    alter table public.organization_specialties enable row level security;
    alter table public.job_applications enable row level security;
    alter table public.ratings enable row level security;

    revoke all on public.specialties, public.profile_specialties, public.profile_private_identity,
      public.organizations, public.organization_members, public.organization_specialties,
      public.job_applications, public.ratings from anon;

    grant select on public.specialties to authenticated;
    grant select,insert,update,delete on public.profile_specialties to authenticated;
    grant select,insert,update on public.profile_private_identity to authenticated;
    grant select,insert,update on public.organizations to authenticated;
    grant select,insert,update,delete on public.organization_members to authenticated;
    grant select,insert,update,delete on public.organization_specialties to authenticated;
    grant select,insert,update on public.job_applications to authenticated;
    grant select,insert on public.ratings to authenticated;

    create policy "authenticated read specialties"
      on public.specialties for select to authenticated
      using (active or private.eventcore_is_staff());

    create policy "own profile specialties"
      on public.profile_specialties for all to authenticated
      using (profile_id=(select auth.uid()) or private.eventcore_is_staff())
      with check (profile_id=(select auth.uid()) or private.eventcore_is_staff());

    create policy "own private identity"
      on public.profile_private_identity for all to authenticated
      using (profile_id=(select auth.uid()) or private.eventcore_is_staff())
      with check (profile_id=(select auth.uid()) or private.eventcore_is_staff());

    create policy "members read organizations"
      on public.organizations for select to authenticated
      using (private.eventcore_org_member(id));

    create policy "owners create organizations"
      on public.organizations for insert to authenticated
      with check (owner_profile_id=(select auth.uid()) or private.eventcore_is_staff());

    create policy "owners update organizations"
      on public.organizations for update to authenticated
      using (private.eventcore_org_manager(id))
      with check (private.eventcore_org_manager(id));

    create policy "members read organization members"
      on public.organization_members for select to authenticated
      using (private.eventcore_org_member(organization_id));

    create policy "managers manage organization members"
      on public.organization_members for all to authenticated
      using (private.eventcore_org_manager(organization_id))
      with check (private.eventcore_org_manager(organization_id));

    create policy "members read organization specialties"
      on public.organization_specialties for select to authenticated
      using (private.eventcore_org_member(organization_id));

    create policy "managers manage organization specialties"
      on public.organization_specialties for all to authenticated
      using (private.eventcore_org_manager(organization_id))
      with check (private.eventcore_org_manager(organization_id));

    create policy "organization members manage clients"
      on public.clients for all to authenticated
      using (organization_id is not null and private.eventcore_org_member(organization_id))
      with check (organization_id is not null and private.eventcore_org_member(organization_id));

    create policy "organization managers manage events"
      on public.events for all to authenticated
      using (
        created_by_profile_id=(select auth.uid())
        or coordinator_id=(select auth.uid())
        or (organization_id is not null and private.eventcore_org_manager(organization_id))
      )
      with check (
        created_by_profile_id=(select auth.uid())
        or coordinator_id=(select auth.uid())
        or (organization_id is not null and private.eventcore_org_manager(organization_id))
      );

    create policy "freelancers read opportunity events"
      on public.events for select to authenticated
      using (
        private.eventcore_profile_type()='freelancer'
        and exists (
          select 1 from public.event_services es
          where es.event_id=events.id and es.visibility='open' and es.application_enabled
        )
      );

    create policy "organization managers manage event services"
      on public.event_services for all to authenticated
      using (private.eventcore_can_manage_event(event_id))
      with check (private.eventcore_can_manage_event(event_id));

    create policy "freelancers read open event services"
      on public.event_services for select to authenticated
      using (
        private.eventcore_profile_type()='freelancer'
        and visibility='open'
        and application_enabled
        and exists (
          select 1 from public.events e
          where e.id=event_services.event_id and e.status<>'cancelled'
        )
      );

    create policy "freelancers create own applications"
      on public.job_applications for insert to authenticated
      with check (
        exists (
          select 1 from public.freelancers f
          where f.id=freelancer_id and f.profile_id=(select auth.uid())
        )
        and exists (
          select 1
          from public.event_services es
          join public.events e on e.id=es.event_id
          where es.id=event_service_id
            and es.visibility='open'
            and es.application_enabled
            and e.status<>'cancelled'
        )
      );

    create policy "participants read applications"
      on public.job_applications for select to authenticated
      using (
        exists (
          select 1 from public.freelancers f
          where f.id=freelancer_id and f.profile_id=(select auth.uid())
        )
        or exists (
          select 1 from public.event_services es
          where es.id=event_service_id
            and private.eventcore_can_manage_event(es.event_id)
        )
        or private.eventcore_is_staff()
      );

    create policy "participants update applications"
      on public.job_applications for update to authenticated
      using (
        exists (
          select 1 from public.freelancers f
          where f.id=freelancer_id and f.profile_id=(select auth.uid())
        )
        or exists (
          select 1 from public.event_services es
          where es.id=event_service_id
            and private.eventcore_can_manage_event(es.event_id)
        )
        or private.eventcore_is_staff()
      )
      with check (
        exists (
          select 1 from public.freelancers f
          where f.id=freelancer_id and f.profile_id=(select auth.uid())
        )
        or exists (
          select 1 from public.event_services es
          where es.id=event_service_id
            and private.eventcore_can_manage_event(es.event_id)
        )
        or private.eventcore_is_staff()
      );

    create policy "freelancers create own record"
      on public.freelancers for insert to authenticated
      with check (
        profile_id=(select auth.uid())
        and private.eventcore_profile_type()='freelancer'
      );

    create policy "freelancers update own record"
      on public.freelancers for update to authenticated
      using (profile_id=(select auth.uid()))
      with check (profile_id=(select auth.uid()));

    create policy "event managers manage assignments"
      on public.assignments for all to authenticated
      using (
        exists (
          select 1 from public.event_services es
          where es.id=assignments.event_service_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      )
      with check (
        exists (
          select 1 from public.event_services es
          where es.id=assignments.event_service_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      );

    create policy "event managers manage attendance"
      on public.attendance for all to authenticated
      using (
        exists (
          select 1
          from public.assignments a
          join public.event_services es on es.id=a.event_service_id
          where a.id=attendance.assignment_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      )
      with check (
        exists (
          select 1
          from public.assignments a
          join public.event_services es on es.id=a.event_service_id
          where a.id=attendance.assignment_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      );

    create policy "event managers manage payments"
      on public.payments for all to authenticated
      using (
        exists (
          select 1
          from public.assignments a
          join public.event_services es on es.id=a.event_service_id
          where a.id=payments.assignment_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      )
      with check (
        exists (
          select 1
          from public.assignments a
          join public.event_services es on es.id=a.event_service_id
          where a.id=payments.assignment_id
            and private.eventcore_can_manage_event(es.event_id)
        )
      );

    create policy "participants read ratings"
      on public.ratings for select to authenticated
      using (
        exists (
          select 1 from public.freelancers f
          where f.id=ratings.freelancer_id and f.profile_id=(select auth.uid())
        )
        or reviewer_profile_id=(select auth.uid())
        or private.eventcore_can_manage_event(event_id)
        or private.eventcore_is_staff()
      );

    create policy "contractors rate completed assignments"
      on public.ratings for insert to authenticated
      with check (
        reviewer_profile_id=(select auth.uid())
        and private.eventcore_can_manage_event(event_id)
        and exists (
          select 1
          from public.assignments a
          join public.event_services es on es.id=a.event_service_id
          where a.id=assignment_id
            and a.freelancer_id=ratings.freelancer_id
            and es.event_id=ratings.event_id
            and a.status='checked_out'
        )
      );
