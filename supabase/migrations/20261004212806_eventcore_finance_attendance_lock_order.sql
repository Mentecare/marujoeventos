-- Keep service/assignment locking consistent across cost edits, responses and attendance.
-- Attendance validation/transitions remain unchanged; cost edits do not lock an event they do not mutate.
create or replace function private.eventcore_set_assignment_amount(p_assignment_id uuid, p_amount numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare service_id uuid; event_id uuid; event_status text; a public.assignments; p public.payments;
begin
  if (select auth.uid()) is null or not private.eventcore_manages_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
  if p_amount is null or not (p_amount between 0 and 9999999999.99) then raise exception 'invalid_payment_amount'; end if;
  select event_service_id into service_id from public.assignments where id=p_assignment_id;
  -- Match the hiring lock order before the assignment trigger locks the service.
  select s.event_id into event_id from public.event_services s where s.id=service_id for update;
  select * into a from public.assignments where id=p_assignment_id for update;
  if a.id is null or not private.eventcore_manages_assignment(a.id) then raise exception 'forbidden'; end if;
  select e.status into event_status from public.events e where e.id=event_id;
  if a.status='cancelled' or event_status='cancelled' then raise exception 'payment_cancelled'; end if;
  select * into p from public.payments where assignment_id=a.id for update;
  if p.status='paid' then raise exception 'payment_already_paid'; end if;
  if p.status='cancelled' then raise exception 'payment_cancelled'; end if;
  update public.assignments set agreed_amount=p_amount,updated_at=now() where id=a.id;
  insert into public.payments(assignment_id,amount,status) values(a.id,p_amount,'pending')
    on conflict(assignment_id) do update set amount=excluded.amount,updated_at=now();
  return a.id;
end;
$$;

create or replace function public.record_assignment_attendance(p_assignment_id uuid,p_kind text,p_lat numeric,p_lng numeric) returns void language plpgsql security definer set search_path='' as $$
declare a public.assignments; ev public.events; att public.attendance; manager boolean; service_id uuid;
begin
 if not (private.eventcore_manages_assignment(p_assignment_id) or private.eventcore_owns_assignment(p_assignment_id)) then raise exception 'forbidden'; end if;
 select event_service_id into service_id from public.assignments where id=p_assignment_id;
 perform 1 from public.event_services where id=service_id for update;
 select * into a from public.assignments where id=p_assignment_id for update;
 manager:=private.eventcore_manages_assignment(a.id);
 if a.id is null or not (manager or private.eventcore_owns_assignment(a.id)) then raise exception 'forbidden'; end if;
 select e.* into ev from public.events e join public.event_services s on s.event_id=e.id where s.id=a.event_service_id;
 if ev.status='cancelled' or now()<ev.start_at-interval '24 hours' then raise exception 'attendance_outside_event_window'; end if;
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'invalid_coordinates'; end if;
 select * into att from public.attendance where assignment_id=a.id for update;
 if p_kind='in' and a.status='confirmed' and att.check_in_at is null then
   insert into public.attendance(assignment_id,check_in_at,check_in_lat,check_in_lng,validated_by,validated_at) values(a.id,now(),p_lat,p_lng,case when manager then auth.uid() end,case when manager then now() end)
   on conflict(assignment_id) do update set check_in_at=excluded.check_in_at,check_in_lat=excluded.check_in_lat,check_in_lng=excluded.check_in_lng,validated_by=excluded.validated_by,validated_at=excluded.validated_at;
   update public.assignments set status='checked_in' where id=a.id;
 elsif p_kind='out' and a.status='checked_in' and att.check_in_at is not null and att.check_out_at is null then
   update public.attendance set check_out_at=now(),check_out_lat=p_lat,check_out_lng=p_lng,validated_by=case when manager then auth.uid() else validated_by end,validated_at=case when manager then now() else validated_at end where id=att.id;
   update public.assignments set status='checked_out' where id=a.id;
 else raise exception 'invalid_attendance_transition'; end if;
end $$;
