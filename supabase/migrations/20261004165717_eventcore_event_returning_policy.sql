-- Returning an inserted event evaluates SELECT RLS before a stable lookup
-- can see the new row. Check the row's organization directly instead.
drop policy events_read on public.events;
create policy events_read on public.events for select to authenticated
using(private.eventcore_org_manager(organization_id) or private.eventcore_assigned_event(id));
