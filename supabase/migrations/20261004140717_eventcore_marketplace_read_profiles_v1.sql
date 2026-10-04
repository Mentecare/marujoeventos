create policy "business profiles read opportunity events"
      on public.events for select to authenticated
      using (
        private.eventcore_profile_type() in ('team_lead','company','agency')
        and exists (
          select 1 from public.event_services es
          where es.event_id=events.id and es.visibility='open' and es.application_enabled
        )
      );

    create policy "business profiles read open event services"
      on public.event_services for select to authenticated
      using (
        private.eventcore_profile_type() in ('team_lead','company','agency')
        and visibility='open'
        and application_enabled
        and exists (
          select 1 from public.events e
          where e.id=event_services.event_id and e.status<>'cancelled'
        )
      );
