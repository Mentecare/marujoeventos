-- Apply after the interface using create_event_with_services is in production.
-- Existing functions retain publication and staffing management; no data is changed.
revoke insert on public.event_services from authenticated;
drop policy services_write on public.event_services;
create policy services_update on public.event_services for update to authenticated
  using(private.eventcore_can_manage_event(event_id)) with check(private.eventcore_can_manage_event(event_id));
create policy services_delete on public.event_services for delete to authenticated
  using(private.eventcore_can_manage_event(event_id));

-- Moving an existing function is also a later addition to another event.
create or replace function private.eventcore_keep_service_event() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.event_id is distinct from old.event_id then raise exception 'functions_creation_only'; end if;
  return new;
end $$;
revoke all on function private.eventcore_keep_service_event() from public, anon, authenticated;
create trigger trg_eventcore_service_event_immutable before update of event_id on public.event_services
  for each row execute function private.eventcore_keep_service_event();
