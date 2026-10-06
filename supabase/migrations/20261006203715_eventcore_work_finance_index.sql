-- Finance membership is independent from operations. Discover only finance-readable work;
-- never broaden events RLS, operations grants, ownership or historical financial meaning.
create function public.get_work_finance_index() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'event_id',e.id,'event_name',e.name,'organization_id',e.organization_id
 ) order by e.start_at,e.id),'[]'::jsonb)
 from public.events e where private.eventcore_can_finance_event(e.id);
$$;
revoke all on function public.get_work_finance_index() from public,anon;
grant execute on function public.get_work_finance_index() to authenticated;
-- Recovery: disable the dependent discovery UI, then revoke authenticated EXECUTE on
-- this read-only RPC. Keep all data, existing grants and event RLS unchanged. A reviewed
-- additive recovery may drop this function after all callers stop using it.
