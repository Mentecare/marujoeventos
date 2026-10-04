-- Enter/correct an unpaid contracted cost without changing payment status/history.
create function private.eventcore_set_assignment_amount(p_assignment_id uuid, p_amount numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare service_id uuid; event_id uuid; event_status text; a public.assignments; p public.payments;
begin
  if (select auth.uid()) is null or not private.eventcore_manages_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
  if p_amount is null or not (p_amount between 0 and 9999999999.99) then raise exception 'invalid_payment_amount'; end if;
  select event_service_id into service_id from public.assignments where id=p_assignment_id;
  -- Match the hiring lock order before the assignment trigger locks the service.
  select s.event_id into event_id from public.event_services s where s.id=service_id for update;
  select e.status into event_status from public.events e where e.id=event_id for update;
  select * into a from public.assignments where id=p_assignment_id for update;
  if a.id is null or not private.eventcore_manages_assignment(a.id) then raise exception 'forbidden'; end if;
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
revoke all on function private.eventcore_set_assignment_amount(uuid,numeric) from public,anon;
grant execute on function private.eventcore_set_assignment_amount(uuid,numeric) to authenticated,service_role;

create function public.set_assignment_amount(p_assignment_id uuid,p_amount numeric)
returns uuid language sql security invoker set search_path = '' as $$
  select private.eventcore_set_assignment_amount(p_assignment_id,p_amount);
$$;
revoke all on function public.set_assignment_amount(uuid,numeric) from public,anon;
grant execute on function public.set_assignment_amount(uuid,numeric) to authenticated,service_role;
