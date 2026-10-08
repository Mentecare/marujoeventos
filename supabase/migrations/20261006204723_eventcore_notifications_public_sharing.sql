-- Additive Task 4. No historical backfill and no scheduler activation.
-- Recovery: unschedule eventcore-notifications; revoke dispatcher RPCs; retain queue/receipts
-- and user preferences for audit. Re-enable and reclaim leases to resume safely.
create table public.notification_preferences (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 mode text not null default 'relevant' check(mode in ('relevant','all_eligible')),
 specialty_ids uuid[] not null default '{}', regions text[] not null default '{}',
 date_from date, date_to date, cadence text not null default 'immediate' check(cadence in ('immediate','daily')),
 email_enabled boolean not null default false, push_enabled boolean not null default false,
 paused_until timestamptz, updated_at timestamptz not null default now(),
 check(date_to is null or date_from is null or date_to>=date_from),
 check(cardinality(specialty_ids)<=100 and cardinality(regions)<=30)
);
create table public.notification_devices (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete cascade,
 endpoint text not null unique, p256dh text not null, auth_key text not null,
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(length(endpoint)<=2000 and endpoint ~ '^https://(fcm[.]googleapis[.]com/fcm/send/|updates[.]push[.]services[.]mozilla[.]com/wpush/v2/|web[.]push[.]apple[.]com/|[a-z0-9-]+[.]notify[.]windows[.]com/w/)[A-Za-z0-9_/?=+%.-]+$'),
 check(p256dh ~ '^[A-Za-z0-9_-]{87}=?$' and auth_key ~ '^[A-Za-z0-9_-]{22}={0,2}$')
);
create index notification_devices_profile_idx on public.notification_devices(profile_id) where active;
create table private.notification_events (
 id uuid primary key default gen_random_uuid(), event_key text not null unique,
 kind text not null check(kind in ('opportunity','assignment','contract')),
 service_id uuid references public.event_services(id), assignment_id uuid references public.assignments(id),
 contract_id uuid references public.commercial_contracts(id), created_at timestamptz not null default now()
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), source_id uuid not null references private.notification_events(id),
 profile_id uuid not null references public.profiles(id) on delete cascade,
 read_at timestamptz, created_at timestamptz not null default now(), unique(source_id,profile_id)
);
create index notifications_profile_idx on public.notifications(profile_id,created_at desc);
create table private.notification_batches (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id),
 channel text not null check(channel in ('email','push')), cadence text not null,
 status text not null default 'queued' check(status in ('queued','leased','delivered','suppressed','failed','disabled')),
 attempts integer not null default 0, lease_token uuid, lease_until timestamptz,
 available_at timestamptz not null default now(), acknowledged_at timestamptz, reason text,
 created_at timestamptz not null default now()
);
create index notification_batches_due_idx on private.notification_batches(available_at) where status in ('queued','leased','disabled');
create table private.notification_outbox (
 id uuid primary key default gen_random_uuid(), notification_id uuid not null references public.notifications(id),
 channel text not null check(channel in ('email','push')), batch_id uuid references private.notification_batches(id),
 available_at timestamptz not null, status text not null default 'queued' check(status in ('queued','delivered','suppressed','failed')),
 unique(notification_id,channel)
);
create index notification_outbox_due_idx on private.notification_outbox(available_at) where status='queued';
create table private.notification_device_receipts (
 batch_id uuid not null references private.notification_batches(id), device_id uuid not null references public.notification_devices(id),
 acknowledged_at timestamptz not null default now(), primary key(batch_id,device_id)
);
alter table public.notification_preferences enable row level security;
alter table public.notification_devices enable row level security;
alter table public.notifications enable row level security;
alter table private.notification_events enable row level security;
alter table private.notification_batches enable row level security;
alter table private.notification_outbox enable row level security;
alter table private.notification_device_receipts enable row level security;
revoke all on public.notification_preferences,public.notification_devices,public.notifications from public,anon,authenticated;
grant select on public.notification_preferences,public.notification_devices,public.notifications to authenticated;
create policy notification_preferences_own on public.notification_preferences for select to authenticated using(profile_id=(select auth.uid()) and private.eventcore_active_actor());
create policy notification_devices_own on public.notification_devices for select to authenticated using(profile_id=(select auth.uid()) and private.eventcore_active_actor());
create policy notifications_own on public.notifications for select to authenticated using(profile_id=(select auth.uid()) and private.eventcore_active_actor());

-- Explicit public DTO: publication does not authorize private event/client/venue/pay data.
create function public.get_public_opportunity(p_service_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'title','Oportunidade: '||coalesce(sp.name,case s.service_type when 'loader' then 'Carregador' when 'security' then 'Segurança' when 'waiter' then 'Garçom' else 'Serviço' end),
 'provider',coalesce(o.display_name,'EventCore'),'role',coalesce(sp.name,case s.service_type when 'loader' then 'Carregador' when 'security' then 'Segurança' when 'waiter' then 'Garçom' else 'Serviço' end),
 'days',s.contract_days,'region',coalesce(e.public_region,'Região a confirmar'),'date',private.eventcore_business_date(e.start_at),'description',s.public_description)
 from public.event_services s join public.events e on e.id=s.event_id left join public.specialties sp on sp.id=s.specialty_id left join public.organizations o on o.id=e.organization_id
 where s.id=p_service_id and s.visibility='open' and s.application_enabled
 and e.status in ('planning','staffing','confirmed','in_progress') and coalesce(e.end_at,e.start_at)>now()
 and (e.organization_id is null or (o.active and o.market_role='provider'))
 and (select count(*) from public.assignments a where a.event_service_id=s.id and a.status in ('invited','confirmed','checked_in','checked_out'))<s.quantity_needed;
$$;
revoke all on function public.get_public_opportunity(uuid) from public;
grant execute on function public.get_public_opportunity(uuid) to anon,authenticated,service_role;

-- Matches apply_for_opportunity's active completed freelancer + specialty/capacity checks;
-- alert preferences NEVER affect get_work_opportunities or applications.
create function private.eventcore_alert_eligible(p_profile uuid,p_service uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.get_public_opportunity(p_service) is not null and exists(
 select 1 from public.profiles p join public.freelancers f on f.profile_id=p.id join public.event_services s on s.id=p_service join public.events e on e.id=s.event_id
 where p.id=p_profile and p.active and p.onboarding_completed and p.profile_type='freelancer' and f.active
 and (s.specialty_id is null or exists(select 1 from public.profile_specialties ps where ps.profile_id=p.id and ps.specialty_id=s.specialty_id))
 and p.id is distinct from e.created_by_profile_id and p.id is distinct from e.coordinator_id
 and not exists(select 1 from public.organizations o where o.id=e.organization_id and o.owner_profile_id=p.id)
 and not exists(select 1 from public.organization_members m where m.organization_id=e.organization_id and m.profile_id=p.id and m.active and m.member_role='manager'));
$$;
create function private.eventcore_notification_allowed(p_source uuid,p_profile uuid,p_channel text default 'center') returns boolean language plpgsql stable security definer set search_path='' as $$
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
create function private.eventcore_notification_dto(p_source uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case ev.kind when 'opportunity' then jsonb_build_object('title','Nova oportunidade disponível','link','/?opportunity='||ev.service_id,'opportunity',public.get_public_opportunity(ev.service_id))
 when 'assignment' then jsonb_build_object('title','Atualização do seu convite ou contrato de trabalho','link','/?assignment='||ev.assignment_id)
 when 'contract' then jsonb_build_object('title','Atualização do seu contrato comercial','link','/?contract='||ev.contract_id) end from private.notification_events ev where ev.id=p_source;
$$;
create function private.eventcore_enqueue_notification(p_key text,p_kind text,p_reference uuid) returns void language plpgsql security definer set search_path='' as $$
declare source uuid; recipient record; notification uuid; cadence text; due timestamptz;
begin
 insert into private.notification_events(event_key,kind,service_id,assignment_id,contract_id) values(p_key,p_kind,case when p_kind='opportunity' then p_reference end,case when p_kind='assignment' then p_reference end,case when p_kind='contract' then p_reference end) on conflict(event_key) do nothing returning id into source;
 if source is null then return; end if;
 for recipient in select id from public.profiles p where p.active and private.eventcore_notification_allowed(source,p.id) loop
  insert into public.notifications(source_id,profile_id) values(source,recipient.id) returning id into notification;
  select coalesce(np.cadence,'immediate') into cadence from public.notification_preferences np where np.profile_id=recipient.id;
  cadence:=coalesce(cadence,'immediate');
  due:=case when cadence='daily' then ((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo' else now() end;
  -- Persist possible channels now, then recheck preference/confirmation/eligibility immediately before dispatch.
  insert into private.notification_outbox(notification_id,channel,available_at) values(notification,'email',due),(notification,'push',due) on conflict do nothing;
 end loop;
end $$;
create function private.eventcore_notification_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='event_services' then
  if new.visibility='open' and new.application_enabled and (tg_op='INSERT' or old.visibility is distinct from new.visibility or old.application_enabled is distinct from new.application_enabled) then perform private.eventcore_enqueue_notification('opportunity:'||new.id,'opportunity',new.id); end if;
 elsif tg_table_name='assignments' then
  if tg_op='INSERT' or new.status is distinct from old.status then perform private.eventcore_enqueue_notification('assignment:'||new.id||':'||new.status,'assignment',new.id); end if;
 elsif tg_table_name='assignment_terms' then
  perform private.eventcore_enqueue_notification('terms:'||new.id,'assignment',new.assignment_id);
 elsif tg_table_name='commercial_contracts' then
  perform private.eventcore_enqueue_notification('contract:'||new.id,'contract',new.id);
 end if;
 return new;
end $$;
create trigger notify_published_function after insert or update of visibility,application_enabled on public.event_services for each row execute function private.eventcore_notification_trigger();
create trigger notify_assignment after insert or update of status on public.assignments for each row execute function private.eventcore_notification_trigger();
create trigger notify_assignment_terms after insert on public.assignment_terms for each row execute function private.eventcore_notification_trigger();
create trigger notify_commercial_contract after insert on public.commercial_contracts for each row execute function private.eventcore_notification_trigger();

create function public.get_notification_center() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 return jsonb_build_object('preferences',coalesce((select to_jsonb(p)-'profile_id' from public.notification_preferences p where p.profile_id=auth.uid()),jsonb_build_object('mode','relevant','specialty_ids','[]'::jsonb,'regions','[]'::jsonb,'date_from',null,'date_to',null,'cadence','immediate','email_enabled',false,'push_enabled',false,'paused_until',null)),
 'email_confirmed',exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null),
 'notifications',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'read_at',n.read_at,'created_at',n.created_at)||private.eventcore_notification_dto(n.source_id) order by n.created_at desc) from (select * from public.notifications where profile_id=auth.uid() and private.eventcore_notification_allowed(source_id,auth.uid()) order by created_at desc limit 100) n),'[]'::jsonb),
 'devices',coalesce((select jsonb_agg(jsonb_build_object('id',id,'endpoint',endpoint,'active',active,'created_at',created_at)) from public.notification_devices where profile_id=auth.uid()),'[]'::jsonb));
end $$;
create function public.save_notification_preferences(p_preferences jsonb) returns void language plpgsql security definer set search_path='' as $$
declare ids uuid[]; regions text[];
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 select coalesce(array_agg(x::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(p_preferences->'specialty_ids','[]')) x;
 select coalesce(array_agg(trim(x)),'{}') into regions from jsonb_array_elements_text(coalesce(p_preferences->'regions','[]')) x;
 if exists(select 1 from unnest(ids) i where not exists(select 1 from public.specialties where id=i and active)) or exists(select 1 from unnest(regions) r where length(r) not between 1 and 150) then raise exception 'invalid_preferences'; end if;
 if coalesce((p_preferences->>'email_enabled')::boolean,false) and not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'confirmed_email_required'; end if;
 insert into public.notification_preferences(profile_id,mode,specialty_ids,regions,date_from,date_to,cadence,email_enabled,push_enabled,paused_until)
 values(auth.uid(),coalesce(p_preferences->>'mode','relevant'),ids,regions,nullif(p_preferences->>'date_from','')::date,nullif(p_preferences->>'date_to','')::date,coalesce(p_preferences->>'cadence','immediate'),coalesce((p_preferences->>'email_enabled')::boolean,false),coalesce((p_preferences->>'push_enabled')::boolean,false),nullif(p_preferences->>'paused_until','')::timestamptz)
 on conflict(profile_id) do update set mode=excluded.mode,specialty_ids=excluded.specialty_ids,regions=excluded.regions,date_from=excluded.date_from,date_to=excluded.date_to,cadence=excluded.cadence,email_enabled=excluded.email_enabled,push_enabled=excluded.push_enabled,paused_until=excluded.paused_until,updated_at=now();
end $$;
create function public.mark_notification_read(p_notification_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification_id and profile_id=auth.uid();
end $$;
create function public.register_notification_device(p_subscription jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 if exists(select 1 from public.notification_devices where endpoint=p_subscription->>'endpoint' and profile_id<>auth.uid()) then raise exception 'device_already_owned'; end if;
 if (select count(*) from public.notification_devices where profile_id=auth.uid() and active)>=10 and not exists(select 1 from public.notification_devices where endpoint=p_subscription->>'endpoint' and profile_id=auth.uid()) then raise exception 'device_limit'; end if;
 insert into public.notification_devices(profile_id,endpoint,p256dh,auth_key) values(auth.uid(),p_subscription->>'endpoint',p_subscription->'keys'->>'p256dh',p_subscription->'keys'->>'auth')
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth_key=excluded.auth_key,active=true,updated_at=now() where public.notification_devices.profile_id=auth.uid() returning id into result;
 return result;
end $$;
create function public.remove_notification_device(p_device_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 update public.notification_devices set active=false,updated_at=now() where id=p_device_id and profile_id=auth.uid();
end $$;
revoke all on function public.get_notification_center(),public.save_notification_preferences(jsonb),public.mark_notification_read(uuid),public.register_notification_device(jsonb),public.remove_notification_device(uuid) from public,anon;
grant execute on function public.get_notification_center(),public.save_notification_preferences(jsonb),public.mark_notification_read(uuid),public.register_notification_device(jsonb),public.remove_notification_device(uuid) to authenticated;

-- Service-role only bounded worker. Batch identity survives retries (Resend idempotency).
create function public.claim_notification_batches(p_limit integer default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_batch private.notification_batches; j record; item jsonb; result jsonb:='[]'; counter integer:=0; cadence text; token uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 -- Changed cadence applies to already queued work without bypassing daily scheduling.
 update private.notification_outbox q set available_at=((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo'
 from public.notifications n join public.notification_preferences p on p.profile_id=n.profile_id
 where n.id=q.notification_id and q.status='queued' and q.batch_id is null and p.cadence='daily' and p.updated_at>n.created_at and q.available_at<=p.updated_at;
 update private.notification_batches b set cadence=p.cadence,available_at=case when p.cadence='daily' then ((now() at time zone 'America/Sao_Paulo')::date+1)::timestamp at time zone 'America/Sao_Paulo' else now() end
 from public.notification_preferences p where p.profile_id=b.profile_id and b.cadence<>p.cadence and b.status in ('queued','disabled');
 -- Serialize claims, not external sends. A crashed worker's 5-minute lease is reclaimed.
 if not pg_try_advisory_xact_lock(7400401) then return result; end if;
 update private.notification_outbox q set status='suppressed' from public.notifications n where n.id=q.notification_id and q.status='queued' and not private.eventcore_notification_allowed(n.source_id,n.profile_id,q.channel);
 for v_batch in select * from private.notification_batches where status in ('queued','disabled','leased') and available_at<=now() and (lease_until is null or lease_until<=now()) and attempts<6 order by available_at limit least(greatest(p_limit,1),20) for update skip locked loop
  if not exists(select 1 from private.notification_outbox where batch_id=v_batch.id and status='queued') then update private.notification_batches set status='suppressed',lease_until=null where id=v_batch.id; continue; end if;
  if v_batch.status='leased' then
   if v_batch.attempts>=5 then update private.notification_batches set status='failed',attempts=6,lease_until=null where id=v_batch.id; update private.notification_outbox set status='failed' where batch_id=v_batch.id and status='queued'; continue; end if;
   update private.notification_batches set attempts=attempts+1 where id=v_batch.id;
  end if;
  token:=gen_random_uuid(); update private.notification_batches set status='leased',lease_token=token,lease_until=now()+interval '5 minutes' where id=v_batch.id;
  result:=result||jsonb_build_array(jsonb_build_object('id',v_batch.id,'lease_token',token)); counter:=counter+1;
 end loop;
 for j in select n.profile_id,q.channel,min(q.available_at) as due from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.status='queued' and q.batch_id is null and q.available_at<=now() group by n.profile_id,q.channel order by due loop
  exit when counter>=least(greatest(p_limit,1),20);
  select p.cadence into cadence from public.notification_preferences p where p.profile_id=j.profile_id;
  if cadence='immediate' and (select count(*) from private.notification_batches where profile_id=j.profile_id and channel=j.channel and acknowledged_at>now()-interval '1 hour')>=5 then continue; end if;
  token:=gen_random_uuid(); insert into private.notification_batches(profile_id,channel,cadence,status,lease_token,lease_until) values(j.profile_id,j.channel,cadence,'leased',token,now()+interval '5 minutes') returning * into v_batch;
  update private.notification_outbox set batch_id=v_batch.id where id in (select q.id from private.notification_outbox q join public.notifications n on n.id=q.notification_id where n.profile_id=j.profile_id and q.channel=j.channel and q.status='queued' and q.batch_id is null and q.available_at<=now() order by q.available_at,q.id limit case when cadence='daily' then 100 else 1 end);
  result:=result||jsonb_build_array(jsonb_build_object('id',v_batch.id,'lease_token',token)); counter:=counter+1;
 end loop;
 -- Build only current allowed DTOs, authoritative confirmed address and remaining owned devices.
 select coalesce(jsonb_agg(x.claim||jsonb_build_object('channel',b.channel,'to',case when b.channel='email' then u.email end,'notifications',(select jsonb_agg(private.eventcore_notification_dto(n.source_id) order by n.created_at,n.id) from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.batch_id=b.id and q.status='queued'),
 'delivered_device_count',(select count(*) from private.notification_device_receipts where batch_id=b.id),'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'subscription',jsonb_build_object('endpoint',d.endpoint,'keys',jsonb_build_object('p256dh',d.p256dh,'auth',d.auth_key)))) from public.notification_devices d where d.profile_id=b.profile_id and d.active and not exists(select 1 from private.notification_device_receipts r where r.batch_id=b.id and r.device_id=d.id)),'[]'::jsonb))),'[]') into result
 from jsonb_array_elements(result) x(claim) join private.notification_batches b on b.id=(x.claim->>'id')::uuid left join auth.users u on u.id=b.profile_id and u.email_confirmed_at is not null;
 return result;
end $$;
create function public.recheck_notification_batch(p_batch_id uuid,p_lease_token uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 return exists(select 1 from private.notification_batches b where b.id=p_batch_id and b.status='leased' and b.lease_token=p_lease_token and b.lease_until>now() and b.cadence=(select cadence from public.notification_preferences where profile_id=b.profile_id)) and not exists(select 1 from private.notification_outbox q join public.notifications n on n.id=q.notification_id where q.batch_id=p_batch_id and q.status='queued' and not private.eventcore_notification_allowed(n.source_id,n.profile_id,q.channel));
end $$;
create function public.ack_notification_device(p_batch_id uuid,p_lease_token uuid,p_device_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 if not exists(select 1 from private.notification_batches b join public.notification_devices d on d.profile_id=b.profile_id where b.id=p_batch_id and b.channel='push' and b.status='leased' and b.lease_token=p_lease_token and b.lease_until>now() and d.id=p_device_id) then raise exception 'stale_lease'; end if;
 insert into private.notification_device_receipts(batch_id,device_id) values(p_batch_id,p_device_id) on conflict do nothing;
end $$;
create function public.disable_notification_device(p_batch_id uuid,p_lease_token uuid,p_device_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 update public.notification_devices d set active=false,updated_at=now() from private.notification_batches b where b.id=p_batch_id and b.profile_id=d.profile_id and b.status='leased' and b.lease_token=p_lease_token and b.lease_until>now() and d.id=p_device_id;
end $$;
create function public.finish_notification_batch(p_batch_id uuid,p_lease_token uuid,p_outcome text,p_reason text default null) returns void language plpgsql security definer set search_path='' as $$
declare v_batch private.notification_batches; v_attempts integer;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'forbidden'; end if;
 select * into v_batch from private.notification_batches where id=p_batch_id for update;
 if v_batch.id is null or v_batch.status<>'leased' or v_batch.lease_token is distinct from p_lease_token or v_batch.lease_until<=now() then raise exception 'stale_lease'; end if;
 if p_outcome not in ('acknowledged','retry','disabled','suppressed') then raise exception 'invalid_outcome'; end if;
 if p_outcome='acknowledged' and v_batch.channel='push' and exists(select 1 from public.notification_devices d where d.profile_id=v_batch.profile_id and d.active and not exists(select 1 from private.notification_device_receipts r where r.batch_id=v_batch.id and r.device_id=d.id)) then raise exception 'unacknowledged_devices'; end if;
 v_attempts:=v_batch.attempts+case when p_outcome='retry' then 1 else 0 end;
 update private.notification_batches set status=case p_outcome when 'acknowledged' then 'delivered' when 'retry' then case when v_attempts>=6 then 'failed' else 'queued' end else p_outcome end,
 attempts=v_attempts,lease_until=null,lease_token=null,acknowledged_at=case when p_outcome='acknowledged' then now() else acknowledged_at end,
 reason=case when p_reason in ('provider_unavailable','email_not_configured','push_not_configured','subscription_expired','no_devices','eligibility_changed','invalid_payload','provider_rejected') then p_reason else null end,
 available_at=now()+case when p_outcome='disabled' then interval '1 hour' else make_interval(secs=>least(3600,30*power(2,v_attempts)::integer)) end where id=v_batch.id;
 if p_outcome in ('acknowledged','suppressed') or v_attempts>=6 then update private.notification_outbox set status=case when p_outcome='acknowledged' then 'delivered' when v_attempts>=6 then 'failed' else 'suppressed' end where batch_id=v_batch.id and status='queued'; end if;
end $$;
revoke all on function public.claim_notification_batches(integer),public.recheck_notification_batch(uuid,uuid),public.ack_notification_device(uuid,uuid,uuid),public.disable_notification_device(uuid,uuid,uuid),public.finish_notification_batch(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.claim_notification_batches(integer),public.recheck_notification_batch(uuid,uuid),public.ack_notification_device(uuid,uuid,uuid),public.disable_notification_device(uuid,uuid,uuid),public.finish_notification_batch(uuid,uuid,text,text) to service_role;
revoke all on function private.eventcore_alert_eligible(uuid,uuid),private.eventcore_notification_allowed(uuid,uuid,text),private.eventcore_notification_dto(uuid),private.eventcore_enqueue_notification(text,text,uuid),private.eventcore_notification_trigger() from public,anon,authenticated;
