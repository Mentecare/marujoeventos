
revoke all privileges on all tables in schema public from authenticated;
revoke all privileges on all sequences in schema public from authenticated;

grant select on public.profiles to authenticated;
grant update (full_name, phone, updated_at) on public.profiles to authenticated;

grant select, insert, update, delete on
  public.freelancers,
  public.clients,
  public.proposals,
  public.proposal_items,
  public.events,
  public.event_services,
  public.assignments,
  public.payments,
  public.documents
to authenticated;

grant select, insert, update on public.attendance to authenticated;
grant select, insert on public.absence_records to authenticated;
grant select, insert on public.audit_logs to authenticated;

grant usage, select on all sequences in schema public to authenticated;

