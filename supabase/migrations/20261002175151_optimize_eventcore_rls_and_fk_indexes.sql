
-- Missing FK indexes flagged by Supabase advisors.
create index if not exists idx_absence_assignment_id on public.absence_records (assignment_id);
create index if not exists idx_absence_event_id on public.absence_records (event_id);
create index if not exists idx_absence_recorded_by on public.absence_records (recorded_by);
create index if not exists idx_absence_reversal_of on public.absence_records (reversal_of);
create index if not exists idx_attendance_validated_by on public.attendance (validated_by);
create index if not exists idx_audit_actor_id on public.audit_logs (actor_id);
create index if not exists idx_documents_uploaded_by on public.documents (uploaded_by);
create index if not exists idx_events_coordinator_id on public.events (coordinator_id);
create index if not exists idx_integrations_updated_by on public.integrations (updated_by);
create index if not exists idx_proposal_items_proposal_id on public.proposal_items (proposal_id);
create index if not exists idx_proposals_created_by on public.proposals (created_by);

-- Cache JWT role lookup once per statement instead of once per row.
alter policy "staff insert absence records" on public.absence_records
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff read absence records" on public.absence_records
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage assignments" on public.assignments
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage attendance" on public.attendance
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff insert audit" on public.audit_logs
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff read audit" on public.audit_logs
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage clients" on public.clients
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage documents" on public.documents
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage event services" on public.event_services
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage events" on public.events
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage freelancers" on public.freelancers
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage payments" on public.payments
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "profiles read self or staff" on public.profiles
  using (
    id = (select auth.uid())
    or coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator')
  );

alter policy "profiles update self or staff" on public.profiles
  using (
    id = (select auth.uid())
    or coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator')
  )
  with check (
    id = (select auth.uid())
    or coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator')
  );

alter policy "staff manage proposal items" on public.proposal_items
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

alter policy "staff manage proposals" on public.proposals
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'))
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'), '') in ('admin','coordinator'));

