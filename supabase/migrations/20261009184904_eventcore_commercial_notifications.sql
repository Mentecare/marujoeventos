-- Additive commercial alerts. No backfill, scheduler activation or external delivery.
-- Recovery: disable notify_contract_request / notify_sent_sale_quote and dispatcher;
-- retain nullable references, queue and receipts. Roll forward after repair; never
-- drop historical events or reinterpret existing opportunity/assignment/contract sources.
alter table private.notification_events
 add column request_id uuid references public.contract_requests(id),
 add column proposal_id uuid references public.proposals(id);
create index notification_events_request_idx on private.notification_events(request_id) where request_id is not null;
create index notification_events_proposal_idx on private.notification_events(proposal_id) where proposal_id is not null;
alter table private.notification_events drop constraint notification_events_kind_check;
alter table private.notification_events add constraint notification_events_kind_check
 check(kind in ('opportunity','assignment','contract','request','proposal'));

-- Equivalent to the existing commercial workspace finance gate, for an explicit
-- recipient rather than the dispatcher/auth.uid(). Operational membership alone
-- never grants access to a request, proposal or its alert.
create function private.eventcore_commercial_alert_member(p_organization uuid,p_profile uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations o join public.profiles p on p.id=p_profile
 where o.id=p_organization and o.active and p.active and
 (o.owner_profile_id=p_profile or exists(select 1 from public.organization_members m
 where m.organization_id=o.id and m.profile_id=p_profile and m.active and m.finance_authorized)));
$$;
revoke all on function private.eventcore_commercial_alert_member(uuid,uuid) from public,anon,authenticated;

create or replace function private.eventcore_notification_allowed(p_source uuid,p_profile uuid,p_channel text default 'center') returns boolean language plpgsql stable security definer set search_path='' as $$
declare ev private.notification_events; pref public.notification_preferences; s public.event_services; e public.events; allowed boolean:=false;
begin
 if not exists(select 1 from public.profiles where id=p_profile and active) then return false; end if;
 select * into ev from private.notification_events where id=p_source;
 if ev.kind='opportunity' then
  allowed:=private.eventcore_alert_eligible(p_profile,ev.service_id);
 elsif ev.kind='assignment' then
  allowed:=exists(select 1 from public.assignments a join public.freelancers f on f.id=a.freelancer_id join public.event_services es on es.id=a.event_service_id join public.events we on we.id=es.event_id where a.id=ev.assignment_id and f.profile_id=p_profile and f.active and a.status not in ('cancelled','no_show') and we.status not in ('cancelled','completed') and coalesce(we.end_at,we.start_at)>now());
 elsif ev.kind='contract' then
  allowed:=exists(select 1 from public.commercial_contracts c join public.organizations o on o.id in (c.provider_organization_id,c.buyer_organization_id) where c.id=ev.contract_id and o.active and (o.owner_profile_id=p_profile or exists(select 1 from public.organization_members m where m.organization_id=o.id and m.profile_id=p_profile and m.active and m.finance_authorized)));
 elsif ev.kind='request' then
  allowed:=exists(select 1 from public.contract_requests r join public.organizations o on o.id=r.provider_organization_id join public.organizations b on b.id=r.buyer_organization_id
  where r.id=ev.request_id and r.status in ('requested','quoted') and o.active and o.market_role='provider' and b.active and b.market_role='buyer'
  and private.eventcore_commercial_alert_member(o.id,p_profile));
 elsif ev.kind='proposal' then
  allowed:=exists(select 1 from public.proposals q join public.organizations o on o.id=q.organization_id join public.organizations b on b.id=q.buyer_organization_id
  where q.id=ev.proposal_id and q.status in ('sent','accepted') and o.active and o.market_role='provider' and b.active and b.market_role='buyer'
  and private.eventcore_commercial_alert_member(b.id,p_profile)
  and not exists(select 1 from public.contract_requests r where r.id=q.request_id and r.status='cancelled')
  and (p_channel='center' or (q.status='sent' and q.valid_until>=private.eventcore_business_today()
  and (q.request_id is null or exists(select 1 from public.contract_requests r where r.id=q.request_id and r.status='quoted')))));
 end if;
 if not allowed or p_channel='center' then return allowed; end if;
 select * into pref from public.notification_preferences where profile_id=p_profile;
 if pref.profile_id is null or pref.paused_until>now() or (p_channel='email' and not pref.email_enabled) or (p_channel='push' and not pref.push_enabled) then return false; end if;
 if p_channel='email' and not exists(select 1 from auth.users where id=p_profile and email_confirmed_at is not null and email is not null) then return false; end if;
 if ev.kind='opportunity' and pref.mode='relevant' then
  select * into s from public.event_services where id=ev.service_id; select * into e from public.events where id=s.event_id;
  if cardinality(pref.specialty_ids)>0 and not coalesce(s.specialty_id=any(pref.specialty_ids),false) then return false; end if;
  if cardinality(pref.regions)>0 and not coalesce(e.public_region,'')=any(pref.regions) then return false; end if;
  if pref.date_from is not null and private.eventcore_business_date(e.start_at)<pref.date_from or pref.date_to is not null and private.eventcore_business_date(e.start_at)>pref.date_to then return false; end if;
 end if;
 return true;
end $$;

create or replace function private.eventcore_notification_dto(p_source uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case ev.kind when 'opportunity' then jsonb_build_object('title','Nova oportunidade disponível','link','/?opportunity='||ev.service_id,'opportunity',public.get_public_opportunity(ev.service_id))
 when 'assignment' then jsonb_build_object('title','Atualização do seu convite ou contrato de trabalho','link','/?assignment='||ev.assignment_id)
 when 'contract' then jsonb_build_object('title','Atualização do seu contrato comercial','link','/?contract='||ev.contract_id)
 when 'request' then jsonb_build_object('title','Nova solicitação de contratação','link','/?request='||ev.request_id)
 when 'proposal' then jsonb_build_object('title','Nova proposta disponível','link','/?proposal='||ev.proposal_id) end from private.notification_events ev where ev.id=p_source;
$$;
create or replace function private.eventcore_enqueue_notification(p_key text,p_kind text,p_reference uuid) returns void language plpgsql security definer set search_path='' as $$
declare source uuid; recipient record; notification uuid; cadence text; due timestamptz;
begin
 insert into private.notification_events(event_key,kind,service_id,assignment_id,contract_id,request_id,proposal_id)
 values(p_key,p_kind,case when p_kind='opportunity' then p_reference end,case when p_kind='assignment' then p_reference end,case when p_kind='contract' then p_reference end,case when p_kind='request' then p_reference end,case when p_kind='proposal' then p_reference end)
 on conflict(event_key) do nothing returning id into source;
 if source is null then return; end if;
 for recipient in select id from public.profiles p where p.active and private.eventcore_notification_allowed(source,p.id) loop
  insert into public.notifications(source_id,profile_id) values(source,recipient.id) returning id into notification;
  select coalesce(np.cadence,'immediate') into cadence from public.notification_preferences np where np.profile_id=recipient.id;
  cadence:=coalesce(cadence,'immediate');
  due:=case when cadence='daily' then ((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo' else now() end;
  insert into private.notification_outbox(notification_id,channel,available_at) values(notification,'email',due),(notification,'push',due) on conflict do nothing;
 end loop;
end $$;
create or replace function private.eventcore_notification_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='event_services' then
  if new.visibility='open' and new.application_enabled and (tg_op='INSERT' or old.visibility is distinct from new.visibility or old.application_enabled is distinct from new.application_enabled) then perform private.eventcore_enqueue_notification('opportunity:'||new.id,'opportunity',new.id); end if;
 elsif tg_table_name='assignments' then
  if tg_op='INSERT' or new.status is distinct from old.status then perform private.eventcore_enqueue_notification('assignment:'||new.id||':'||new.status,'assignment',new.id); end if;
 elsif tg_table_name='assignment_terms' then
  if new.revision>1 then perform private.eventcore_enqueue_notification('terms:'||new.id,'assignment',new.assignment_id); end if;
 elsif tg_table_name='commercial_contracts' then
  perform private.eventcore_enqueue_notification('contract:'||new.id,'contract',new.id);
 elsif tg_table_name='contract_requests' then
  perform private.eventcore_enqueue_notification('request:'||new.id,'request',new.id);
 elsif tg_table_name='proposals' then
  if new.status='sent' and old.status is distinct from new.status and new.buyer_organization_id is not null then perform private.eventcore_enqueue_notification('proposal:'||new.id,'proposal',new.id); end if;
 end if;
 return new;
end $$;
create trigger notify_contract_request after insert on public.contract_requests for each row execute function private.eventcore_notification_trigger();
create trigger notify_sent_sale_quote after update of status on public.proposals for each row execute function private.eventcore_notification_trigger();
