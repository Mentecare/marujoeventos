-- Additive commercial foundation. Existing amounts/documents/organizations are not reinterpreted.
alter table public.organizations add column market_role text not null default 'unclassified'
 check(market_role in ('provider','buyer','unclassified'));
alter table public.organizations add column buyer_subtype text check(buyer_subtype in ('agency','scenography'));
alter table public.organizations add constraint organization_buyer_subtype check
 ((market_role='buyer' and buyer_subtype is not null) or (market_role<>'buyer' and buyer_subtype is null));
alter table public.organization_members add column finance_authorized boolean not null default false;

create or replace function private.eventcore_active_actor() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active);
$$;
create or replace function private.eventcore_org_owner(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.organizations where id=p_org and active and owner_profile_id=auth.uid());
$$;
create or replace function private.eventcore_org_member(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.organizations o where o.id=p_org and o.active and
 (o.owner_profile_id=auth.uid() or exists(select 1 from public.organization_members m where m.organization_id=o.id and m.profile_id=auth.uid() and m.active)));
$$;
create or replace function private.eventcore_org_manager(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_org_owner(p_org) or (private.eventcore_org_member(p_org) and exists(select 1 from public.organization_members where organization_id=p_org and profile_id=auth.uid() and active and member_role='manager'));
$$;
create or replace function private.eventcore_org_finance(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_org_owner(p_org) or (private.eventcore_org_member(p_org) and exists(select 1 from public.organization_members where organization_id=p_org and profile_id=auth.uid() and active and finance_authorized));
$$;
create or replace function private.eventcore_has_identity() returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.profile_private_identity where profile_id=auth.uid() and private.eventcore_document_valid(document_type,document_number));
$$;
create or replace function private.eventcore_can_manage_event(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.events e where e.id=p_event and
 (e.organization_id is null or exists(select 1 from public.organizations o where o.id=e.organization_id and o.active and o.market_role<>'buyer')) and
 ((e.organization_id is null and e.created_by_profile_id=auth.uid()) or e.coordinator_id=auth.uid() or private.eventcore_org_manager(e.organization_id)));
$$;
create or replace function private.eventcore_can_finance_event(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_active_actor() and exists(select 1 from public.events e where e.id=p_event and
 (e.organization_id is null or exists(select 1 from public.organizations o where o.id=e.organization_id and o.active and o.market_role<>'buyer')) and
 ((e.organization_id is null and e.created_by_profile_id=auth.uid()) or private.eventcore_org_finance(e.organization_id)));
$$;
create or replace function private.eventcore_can_hire_event(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_has_identity() and private.eventcore_can_manage_event(p_event) and exists(
 select 1 from public.events e where e.id=p_event and
 ((e.organization_id is not null and exists(select 1 from public.organizations o where o.id=e.organization_id and o.active and o.market_role='provider')) or
 (e.organization_id is null and e.created_by_profile_id=auth.uid() and exists(select 1 from public.organizations o where o.owner_profile_id=auth.uid() and o.active and o.market_role='provider'))));
$$;
create or replace function private.eventcore_finances_assignment(p_assignment uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id where a.id=p_assignment and private.eventcore_can_finance_event(s.event_id));
$$;
-- Participant reads may expose contacts only within an authorized event, never by generic staff status.
create function private.eventcore_operates_freelancer(p_freelancer uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id
 where a.freelancer_id=p_freelancer and (private.eventcore_can_manage_event(s.event_id) or private.eventcore_can_finance_event(s.event_id)));
$$;
-- The RLS ownership predicates trust this link: authenticated callers cannot rebind it.
create function private.eventcore_guard_freelancer_owner() returns trigger
language plpgsql set search_path='' as $$
begin
 if auth.uid() is not null then
  if tg_op='INSERT' and new.profile_id is not null and new.profile_id is distinct from auth.uid() then raise exception 'freelancer_ownership_is_immutable'; end if;
  if tg_op='UPDATE' and (new.id is distinct from old.id or new.profile_id is distinct from old.profile_id) then raise exception 'freelancer_ownership_is_immutable'; end if;
 end if;
 return new;
end $$;
create trigger commercial_freelancer_owner before insert or update on public.freelancers for each row execute function private.eventcore_guard_freelancer_owner();

-- New remuneration writes require provider classification; historical finance reads remain available.
create function private.eventcore_can_pay_assignment(p_assignment uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_finances_assignment(p_assignment) and private.eventcore_has_identity() and exists(
 select 1 from public.assignments a join public.event_services s on s.id=a.event_service_id join public.events e on e.id=s.event_id
 where a.id=p_assignment and
 ((e.organization_id is not null and exists(select 1 from public.organizations o where o.id=e.organization_id and o.active and o.market_role='provider')) or
 (e.organization_id is null and e.created_by_profile_id=auth.uid() and exists(select 1 from public.organizations o where o.owner_profile_id=auth.uid() and o.active and o.market_role='provider'))));
$$;
create or replace function private.eventcore_valid_event_tenant(p_org uuid,p_client uuid,p_creator uuid,p_coordinator uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.eventcore_has_identity() and p_creator=auth.uid() and p_coordinator=auth.uid() and private.eventcore_org_manager(p_org)
 and exists(select 1 from public.organizations where id=p_org and active and market_role='provider')
 and exists(select 1 from public.clients where id=p_client and organization_id=p_org and active);
$$;

create function public.configure_business_identity(p_payload jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare org uuid:=nullif(p_payload->>'organization_id','')::uuid; doc text:=upper(regexp_replace(p_payload->>'document','[./\s-]','','g')); kind text; role_name text:=p_payload->>'market_role'; subtype text:=nullif(p_payload->>'buyer_subtype','');
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 kind:=case when length(doc)=11 then 'cpf' else 'cnpj' end;
 if doc is null or not private.eventcore_document_valid(kind,doc) then raise exception 'invalid_private_document'; end if;
 if role_name is null or role_name not in ('provider','buyer') or (role_name='buyer' and (subtype is null or subtype not in ('agency','scenography'))) or (role_name='provider' and subtype is not null) then raise exception 'invalid_market_role'; end if;
 if length(trim(coalesce(p_payload->>'display_name','')))<2 or length(p_payload->>'display_name')>150 or coalesce(p_payload->>'organization_type','') not in ('team','company','agency') then raise exception 'invalid_organization'; end if;
 if org is not null then
  perform 1 from public.organizations where id=org for update;
  if not private.eventcore_org_owner(org) then raise exception 'forbidden'; end if;
  if exists(select 1 from public.organizations where id=org and market_role not in ('unclassified',role_name)) then raise exception 'market_role_locked'; end if;
 end if;
 insert into public.profile_private_identity(profile_id,document_type,document_number) values(auth.uid(),kind,doc)
 on conflict(profile_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,updated_at=now();
 if org is null then
  insert into public.organizations(owner_profile_id,organization_type,display_name,market_role,buyer_subtype)
  values(auth.uid(),p_payload->>'organization_type',trim(p_payload->>'display_name'),role_name,subtype) returning id into org;
  insert into public.organization_members(organization_id,profile_id,member_role) values(org,auth.uid(),'owner');
 else
  update public.organizations set display_name=trim(p_payload->>'display_name'),market_role=role_name,buyer_subtype=subtype,updated_at=now() where id=org;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'business_identity_configured','organization',org,jsonb_build_object('market_role',role_name));
 return org;
exception when unique_violation then raise exception 'private_document_conflict';
end $$;
create function public.set_organization_finance_member(p_organization_id uuid,p_profile_id uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.eventcore_org_owner(p_organization_id) or p_enabled is null then raise exception 'forbidden'; end if;
 update public.organization_members set finance_authorized=p_enabled where organization_id=p_organization_id and profile_id=p_profile_id and active;
 if not found then raise exception 'member_not_found'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'finance_permission_changed','organization',p_organization_id,jsonb_build_object('profile_id',p_profile_id,'enabled',p_enabled));
end $$;

-- Replace every permissive finance policy rather than layering another OR predicate.
do $$ declare p record; begin
 for p in select tablename,policyname from pg_policies where schemaname='public' and tablename in
 ('proposals','proposal_items','event_financials','payments','assignments','event_services','events','organizations','organization_members','profile_private_identity','audit_logs','documents','attendance','absence_records','clients','freelancers') loop
 execute format('drop policy %I on public.%I',p.policyname,p.tablename); end loop;
end $$;
-- Linked workers are created/updated through verified self-onboarding, not a generic staff write.
create policy freelancers_read on public.freelancers for select to authenticated using(private.eventcore_owns_freelancer(id) or private.eventcore_operates_freelancer(id) or (profile_id is null and private.eventcore_is_staff()));
create policy freelancers_legacy_insert on public.freelancers for insert to authenticated with check(profile_id is null and private.eventcore_is_staff());
create policy freelancers_legacy_update on public.freelancers for update to authenticated using(profile_id is null and private.eventcore_is_staff()) with check(profile_id is null and private.eventcore_is_staff());
create policy freelancers_legacy_delete on public.freelancers for delete to authenticated using(profile_id is null and private.eventcore_is_staff());
create policy identity_self on public.profile_private_identity for select to authenticated using(profile_id=auth.uid());
create policy org_read on public.organizations for select to authenticated using(private.eventcore_org_member(id));
create policy members_read on public.organization_members for select to authenticated using(private.eventcore_org_member(organization_id));
-- Membership/role/finance writes only through the owner RPCs.
revoke insert,update,delete on public.organizations,public.organization_members from authenticated;
create policy clients_read on public.clients for select to authenticated using(private.eventcore_org_manager(organization_id) or exists(select 1 from public.events e where e.client_id=clients.id and e.organization_id is null and e.created_by_profile_id=auth.uid()));
create policy clients_insert on public.clients for insert to authenticated with check(private.eventcore_org_manager(organization_id));
create policy clients_update on public.clients for update to authenticated using(private.eventcore_org_manager(organization_id)) with check(private.eventcore_org_manager(organization_id));
create policy events_read on public.events for select to authenticated using(private.eventcore_can_manage_event(id) or private.eventcore_assigned_event(id));
create policy events_insert on public.events for insert to authenticated with check(private.eventcore_valid_event_tenant(organization_id,client_id,created_by_profile_id,coordinator_id));
create policy events_update on public.events for update to authenticated using(private.eventcore_can_manage_event(id)) with check(private.eventcore_can_manage_event(id));
-- Raw services/assignments contain financial amounts. Operators consume get_event_operations.
create policy services_read on public.event_services for select to authenticated using(private.eventcore_can_finance_event(event_id));
create policy services_update on public.event_services for update to authenticated using(private.eventcore_can_hire_event(event_id) and private.eventcore_can_finance_event(event_id)) with check(private.eventcore_can_hire_event(event_id) and private.eventcore_can_finance_event(event_id));
create policy services_delete on public.event_services for delete to authenticated using(private.eventcore_can_hire_event(event_id) and private.eventcore_can_finance_event(event_id));
create policy assignments_read on public.assignments for select to authenticated using(private.eventcore_finances_assignment(id) or private.eventcore_owns_freelancer(freelancer_id));
create policy assignments_own_response on public.assignments for update to authenticated using(private.eventcore_owns_freelancer(freelancer_id)) with check(private.eventcore_owns_freelancer(freelancer_id));
revoke insert,delete on public.assignments from authenticated;
create policy attendance_read on public.attendance for select to authenticated using(private.eventcore_manages_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
revoke insert,update,delete on public.attendance from authenticated;
create policy payments_read on public.payments for select to authenticated using(private.eventcore_finances_assignment(assignment_id) or private.eventcore_owns_assignment(assignment_id));
revoke insert,update,delete on public.payments from authenticated;
create policy financials_read on public.event_financials for select to authenticated using(private.eventcore_can_finance_event(event_id));
create policy financials_insert on public.event_financials for insert to authenticated with check(private.eventcore_can_finance_event(event_id));
create policy financials_update on public.event_financials for update to authenticated using(private.eventcore_can_finance_event(event_id)) with check(private.eventcore_can_finance_event(event_id));
create policy absences_read on public.absence_records for select to authenticated using(private.eventcore_can_manage_event(event_id) or private.eventcore_owns_freelancer(freelancer_id));
revoke insert on public.absence_records from authenticated;
-- Audit/doc metadata may contain financial/private payloads; no generic staff shortcut.
create policy audit_self on public.audit_logs for select to authenticated using(actor_id=auth.uid());
revoke insert on public.audit_logs from authenticated;
create policy documents_self on public.documents for select to authenticated using(uploaded_by=auth.uid());
revoke insert,update,delete on public.documents from authenticated;

create table public.contract_requests (
 id uuid primary key default gen_random_uuid(), provider_organization_id uuid not null references public.organizations(id),
 buyer_organization_id uuid not null references public.organizations(id), created_by uuid not null references public.profiles(id),
 title text not null, description text not null, event_date date, venue text,
 status text not null default 'requested' check(status in ('requested','quoted','contracted','cancelled')),
 created_at timestamptz not null default now(), check(provider_organization_id<>buyer_organization_id)
);
alter table public.proposals add column organization_id uuid references public.organizations(id),
 add column request_id uuid references public.contract_requests(id), add column buyer_organization_id uuid references public.organizations(id),
 add column valid_until date, add column payment_terms text, add column show_unit_prices boolean not null default true,
 add column revision integer not null default 1, add column submitted_at timestamptz;
-- Default 1 preserves existing quantity x unit-price semantics; never multiply historical totals.
alter table public.proposal_items add column contract_days integer not null default 1 check(contract_days between 1 and 366);
create table public.commercial_contracts (
 id uuid primary key default gen_random_uuid(), proposal_id uuid not null unique references public.proposals(id),
 request_id uuid unique references public.contract_requests(id), provider_organization_id uuid not null references public.organizations(id),
 buyer_organization_id uuid references public.organizations(id), client_id uuid not null references public.clients(id),
 sale_total numeric(12,2) not null check(sale_total>=0), quote_snapshot jsonb not null,
 accepted_by uuid not null references public.profiles(id), accepted_at timestamptz not null default now(),
 acceptance_method text not null check(acceptance_method in ('platform','external_recorded')), external_evidence text
);
alter table public.proposals add column contract_id uuid unique references public.commercial_contracts(id);
create table public.customer_receipts (
 id uuid primary key default gen_random_uuid(), contract_id uuid not null references public.commercial_contracts(id),
 amount numeric(12,2) not null check(amount>0 and amount<=9999999999.99), method text not null check(method in ('pix','transfer','cash','other')),
 received_on date not null, recorded_by uuid not null references public.profiles(id), idempotency_key text not null,
 created_at timestamptz not null default now(), unique(contract_id,idempotency_key)
);
create index contract_requests_provider_idx on public.contract_requests(provider_organization_id);
create index contract_requests_buyer_idx on public.contract_requests(buyer_organization_id);
create index proposals_org_idx on public.proposals(organization_id);
create index proposals_request_idx on public.proposals(request_id);
create index proposals_buyer_idx on public.proposals(buyer_organization_id);
create index commercial_contracts_provider_idx on public.commercial_contracts(provider_organization_id);
create index commercial_contracts_buyer_idx on public.commercial_contracts(buyer_organization_id);
create index commercial_contracts_client_idx on public.commercial_contracts(client_id);
create index commercial_contracts_actor_idx on public.commercial_contracts(accepted_by);
create index contract_requests_actor_idx on public.contract_requests(created_by);
create index customer_receipts_actor_idx on public.customer_receipts(recorded_by);
alter table public.contract_requests enable row level security;
alter table public.commercial_contracts enable row level security;
alter table public.customer_receipts enable row level security;
revoke all on public.contract_requests,public.commercial_contracts,public.customer_receipts from public,anon,authenticated;
grant select on public.contract_requests,public.commercial_contracts,public.customer_receipts to authenticated;
grant all on public.contract_requests,public.commercial_contracts,public.customer_receipts to service_role;
revoke insert,update,delete on public.proposals,public.proposal_items from authenticated;
create policy requests_read on public.contract_requests for select to authenticated using(private.eventcore_org_finance(provider_organization_id) or private.eventcore_org_finance(buyer_organization_id));
create policy contracts_read on public.commercial_contracts for select to authenticated using(private.eventcore_org_finance(provider_organization_id) or private.eventcore_org_finance(buyer_organization_id));
create policy receipts_read on public.customer_receipts for select to authenticated using(exists(select 1 from public.commercial_contracts c where c.id=contract_id and (private.eventcore_org_finance(c.provider_organization_id) or private.eventcore_org_finance(c.buyer_organization_id))));
create policy proposals_read on public.proposals for select to authenticated using(private.eventcore_org_finance(organization_id) or (organization_id is null and created_by=auth.uid() and private.eventcore_active_actor()));
create policy proposal_items_read on public.proposal_items for select to authenticated using(exists(select 1 from public.proposals p where p.id=proposal_id and (private.eventcore_org_finance(p.organization_id) or (p.organization_id is null and p.created_by=auth.uid() and private.eventcore_active_actor()))));

create function private.eventcore_require_commercial(p_org uuid,p_role text) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_org_finance(p_org) then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.organizations where id=p_org and active and market_role=p_role) then raise exception 'forbidden'; end if;
 if not private.eventcore_has_identity() then raise exception 'identity_required'; end if;
end $$;
create function public.create_contract_request(p_buyer_organization_id uuid,p_provider_organization_id uuid,p_title text,p_description text,p_event_date date default null,p_venue text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform private.eventcore_require_commercial(p_buyer_organization_id,'buyer');
 if not exists(select 1 from public.organizations where id=p_provider_organization_id and active and market_role='provider') then raise exception 'provider_required'; end if;
 if length(trim(coalesce(p_title,'')))<2 or length(p_title)>200 or length(coalesce(p_description,''))>5000 or p_buyer_organization_id=p_provider_organization_id then raise exception 'invalid_request'; end if;
 insert into public.contract_requests(provider_organization_id,buyer_organization_id,created_by,title,description,event_date,venue)
 values(p_provider_organization_id,p_buyer_organization_id,auth.uid(),trim(p_title),coalesce(p_description,''),p_event_date,left(p_venue,500)) returning id into result;
 return result;
end $$;

create function public.save_sale_quote(p_quote jsonb,p_items jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare org uuid:=nullif(p_quote->>'organization_id','')::uuid; rid uuid:=nullif(p_quote->>'request_id','')::uuid; pid uuid:=nullif(p_quote->>'id','')::uuid;
 client uuid:=nullif(p_quote->>'client_id','')::uuid; req public.contract_requests; old_quote public.proposals; item jsonb;
 qty integer; days integer; price numeric; cost numeric; hours numeric; total numeric:=0; validity date:=(p_quote->>'valid_until')::date;
begin
 perform private.eventcore_require_commercial(org,'provider');
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'invalid_quote_items'; end if;
 if length(trim(coalesce(p_quote->>'title','')))<2 or length(p_quote->>'title')>200 or validity is null or not isfinite(validity) or validity<current_date
 or length(coalesce(p_quote->>'payment_terms',''))>3000 then raise exception 'invalid_quote'; end if;
 -- Lock the request before the quote, consistently with submit/accept.
 if rid is not null then
  select * into req from public.contract_requests where id=rid for update;
  if req.id is null or req.provider_organization_id<>org or req.status in ('contracted','cancelled') then raise exception 'forbidden'; end if;
 end if;
 if pid is not null then
  select * into old_quote from public.proposals where id=pid for update;
  if old_quote.id is null or old_quote.organization_id is distinct from org or old_quote.request_id is distinct from rid then raise exception 'forbidden'; end if;
  if old_quote.status<>'draft' or old_quote.contract_id is not null then raise exception 'quote_immutable'; end if;
  if (p_quote->>'expected_revision')::integer is distinct from old_quote.revision then raise exception 'stale_quote'; end if;
  client:=old_quote.client_id;
 end if;
 if rid is not null and pid is null then
  -- Buyer identifier and customer display name are derived only from the authorized request.
  insert into public.clients(trade_name,organization_id) select display_name,org from public.organizations where id=req.buyer_organization_id returning id into client;
 elsif not exists(select 1 from public.clients where id=client and organization_id=org and active) then raise exception 'forbidden'; end if;
 if pid is null then
  insert into public.proposals(client_id,title,event_date,venue,created_by,organization_id,request_id,buyer_organization_id,valid_until,payment_terms,show_unit_prices)
  values(client,trim(p_quote->>'title'),nullif(p_quote->>'event_date','')::date,left(p_quote->>'venue',500),auth.uid(),org,rid,req.buyer_organization_id,validity,p_quote->>'payment_terms',coalesce((p_quote->>'show_unit_prices')::boolean,true)) returning id into pid;
 else
  update public.proposals set title=trim(p_quote->>'title'),event_date=nullif(p_quote->>'event_date','')::date,venue=left(p_quote->>'venue',500),valid_until=validity,payment_terms=p_quote->>'payment_terms',show_unit_prices=coalesce((p_quote->>'show_unit_prices')::boolean,true),revision=revision+1,updated_at=now() where id=pid;
  delete from public.proposal_items where proposal_id=pid;
 end if;
 for item in select value from jsonb_array_elements(p_items) loop
  qty:=(item->>'quantity')::integer; days:=(item->>'contract_days')::integer; price:=(item->>'client_unit_price')::numeric;
  cost:=nullif(item->>'freelancer_unit_cost','')::numeric; hours:=nullif(item->>'planned_hours','')::numeric;
  if qty is null or qty not between 1 and 10000 or days is null or days not between 1 and 366 or price is null or price not between 0 and 9999999999.99 or price<>round(price,2)
   or (cost is not null and (cost not between 0 and 9999999999.99 or cost<>round(cost,2))) or (hours is not null and hours not between 0 and 9999.99)
   or length(trim(coalesce(item->>'label','')))<1 or length(item->>'label')>300 then raise exception 'invalid_quote_item'; end if;
  total:=total+qty*days*price;
  if total>9999999999.99 then raise exception 'invalid_quote_total'; end if;
  insert into public.proposal_items(proposal_id,service_type,label,quantity,contract_days,client_unit_price,freelancer_unit_cost,planned_hours)
  values(pid,coalesce(item->>'service_type','other'),trim(item->>'label'),qty,days,price,cost,hours);
 end loop;
 update public.proposals set client_total=total where id=pid;
 return pid;
end $$;

create function private.eventcore_sale_quote_dto(p_proposal_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'revision',p.revision,'status',p.status,'title',p.title,
 'issued_at',coalesce(p.submitted_at,p.created_at),'event_date',p.event_date,'venue',p.venue,'valid_until',p.valid_until,
 'payment_terms',p.payment_terms,'show_unit_prices',p.show_unit_prices,'client_total',p.client_total,
 'issuer',jsonb_build_object('id',o.id,'display_name',coalesce(o.display_name,'EventCore')),
 'client',jsonb_build_object('display_name',coalesce(b.display_name,c.trade_name)),
 'request_id',p.request_id,'contract_id',p.contract_id,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'label',i.label,'quantity',i.quantity,
 'contract_days',i.contract_days,'planned_hours',i.planned_hours,'client_unit_price',i.client_unit_price,
 'line_total',i.quantity*i.contract_days*i.client_unit_price) order by i.created_at,i.id) from public.proposal_items i where i.proposal_id=p.id),'[]'::jsonb))
 from public.proposals p join public.clients c on c.id=p.client_id left join public.organizations o on o.id=p.organization_id left join public.organizations b on b.id=p.buyer_organization_id where p.id=p_proposal_id;
$$;
create function public.get_sale_quote(p_proposal_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.proposals;
begin
 select * into p from public.proposals where id=p_proposal_id;
 if not private.eventcore_active_actor() or p.id is null or not (
 private.eventcore_org_finance(p.organization_id) or (p.organization_id is null and p.created_by=auth.uid()) or
 (p.status in ('sent','accepted') and private.eventcore_org_finance(p.buyer_organization_id))) then raise exception 'forbidden'; end if;
 if p.contract_id is not null then return (select quote_snapshot from public.commercial_contracts where id=p.contract_id); end if;
 return private.eventcore_sale_quote_dto(p.id);
end $$;
create function public.submit_sale_quote(p_proposal_id uuid,p_expected_revision integer) returns void
language plpgsql security definer set search_path='' as $$
declare p public.proposals; rid uuid;
begin
 select request_id into rid from public.proposals where id=p_proposal_id;
 perform 1 from public.contract_requests where id=rid for update;
 select * into p from public.proposals where id=p_proposal_id for update;
 perform private.eventcore_require_commercial(p.organization_id,'provider');
 if p.revision is distinct from p_expected_revision then raise exception 'stale_quote'; end if;
 if p.status<>'draft' or p.valid_until is null or p.valid_until<current_date or not exists(select 1 from public.proposal_items where proposal_id=p.id)
 or exists(select 1 from public.contract_requests where id=rid and status in ('contracted','cancelled')) then raise exception 'quote_not_available'; end if;
 update public.proposals set status='sent',submitted_at=now(),updated_at=now() where id=p.id;
 update public.contract_requests set status='quoted' where id=rid;
end $$;
create function public.accept_sale_quote(p_proposal_id uuid,p_expected_revision integer,p_external_evidence text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.proposals; rid uuid; cid uuid:=gen_random_uuid(); snapshot jsonb; total numeric;
begin
 select request_id into rid from public.proposals where id=p_proposal_id;
 perform 1 from public.contract_requests where id=rid for update;
 select * into p from public.proposals where id=p_proposal_id for update;
 if p.id is null then raise exception 'forbidden'; end if;
 if p.buyer_organization_id is null then
  perform private.eventcore_require_commercial(p.organization_id,'provider');
  if length(trim(coalesce(p_external_evidence,'')))<3 or length(p_external_evidence)>2000 then raise exception 'external_acceptance_evidence_required'; end if;
 else
  perform private.eventcore_require_commercial(p.buyer_organization_id,'buyer');
  if not exists(select 1 from public.contract_requests r where r.id=p.request_id and r.provider_organization_id=p.organization_id and r.buyer_organization_id=p.buyer_organization_id and r.status='quoted') then raise exception 'quote_not_available'; end if;
 end if;
 if p.revision is distinct from p_expected_revision then raise exception 'stale_quote'; end if;
 if p.status<>'sent' or p.contract_id is not null or p.valid_until is null or p.valid_until<current_date then raise exception 'quote_not_available'; end if;
 if not exists(select 1 from public.organizations where id=p.organization_id and active and market_role='provider') then raise exception 'provider_required'; end if;
 select sum(quantity*contract_days*client_unit_price) into total from public.proposal_items where proposal_id=p.id;
 if total is null or total<>p.client_total then raise exception 'invalid_quote_total'; end if;
 snapshot:=private.eventcore_sale_quote_dto(p.id)||jsonb_build_object('status','accepted','contract_id',cid);
 insert into public.commercial_contracts(id,proposal_id,request_id,provider_organization_id,buyer_organization_id,client_id,sale_total,quote_snapshot,accepted_by,acceptance_method,external_evidence)
 values(cid,p.id,p.request_id,p.organization_id,p.buyer_organization_id,p.client_id,total,snapshot,auth.uid(),case when p.buyer_organization_id is null then 'external_recorded' else 'platform' end,case when p.buyer_organization_id is null then trim(p_external_evidence) end);
 update public.proposals set status='accepted',accepted_at=now(),contract_id=cid,updated_at=now() where id=p.id;
 update public.contract_requests set status='contracted' where id=p.request_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'sale_quote_accepted','contract',cid,jsonb_build_object('proposal_id',p.id,'revision',p.revision));
 return cid;
end $$;
create function public.record_customer_receipt(p_contract_id uuid,p_amount numeric,p_method text,p_received_on date,p_idempotency_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.commercial_contracts; r public.customer_receipts; result uuid; received numeric;
begin
 select * into c from public.commercial_contracts where id=p_contract_id for update;
 if c.id is null then raise exception 'forbidden'; end if;
 perform private.eventcore_require_commercial(c.provider_organization_id,'provider');
 if p_amount is null or p_amount not between 0.01 and 9999999999.99 or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('pix','transfer','cash','other')
 or p_received_on is null or not isfinite(p_received_on) or p_received_on>current_date or length(trim(coalesce(p_idempotency_key,''))) not between 1 and 100 then raise exception 'invalid_receipt'; end if;
 select * into r from public.customer_receipts where contract_id=c.id and idempotency_key=p_idempotency_key;
 if r.id is not null then
  if r.amount<>p_amount or r.method<>p_method or r.received_on<>p_received_on then raise exception 'idempotency_conflict'; end if;
  return r.id;
 end if;
 select coalesce(sum(amount),0) into received from public.customer_receipts where contract_id=c.id;
 if received+p_amount>c.sale_total then raise exception 'receipt_exceeds_receivable'; end if;
 insert into public.customer_receipts(contract_id,amount,method,received_on,recorded_by,idempotency_key) values(c.id,p_amount,p_method,p_received_on,auth.uid(),p_idempotency_key) returning id into result;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'customer_receipt_recorded','receipt',result,jsonb_build_object('contract_id',c.id));
 return result;
end $$;

create function private.eventcore_guard_quote() returns trigger language plpgsql set search_path='' as $$
declare state text;
begin
 if tg_table_name='proposals' then
  if tg_op='DELETE' and old.status<>'draft' then raise exception 'quote_immutable'; end if;
  if tg_op='UPDATE' and old.status<>'draft' then
   if old.status<>'sent' or new.status<>'accepted' or new.contract_id is null or
    (to_jsonb(new)-array['status','accepted_at','contract_id','updated_at']) is distinct from (to_jsonb(old)-array['status','accepted_at','contract_id','updated_at']) then raise exception 'quote_immutable'; end if;
  end if;
 else
  select status into state from public.proposals where id=case when tg_op='DELETE' then old.proposal_id else new.proposal_id end for update;
  if state is distinct from 'draft' then raise exception 'quote_immutable'; end if;
  if tg_op='UPDATE' and new.proposal_id is distinct from old.proposal_id then raise exception 'quote_immutable'; end if;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
create trigger commercial_quote_immutable before update or delete on public.proposals for each row execute function private.eventcore_guard_quote();
create trigger commercial_quote_items_immutable before insert or update or delete on public.proposal_items for each row execute function private.eventcore_guard_quote();
create function private.eventcore_commercial_immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'commercial_record_immutable'; end $$;
create trigger commercial_contract_immutable before update or delete on public.commercial_contracts for each row execute function private.eventcore_commercial_immutable();
create trigger customer_receipt_immutable before update or delete on public.customer_receipts for each row execute function private.eventcore_commercial_immutable();

create function public.get_commercial_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 return jsonb_build_object('profile_id',auth.uid(),'identity_complete',private.eventcore_has_identity(),
 'document_type',(select document_type from public.profile_private_identity where profile_id=auth.uid()),
 'document_last4',(select document_last4 from public.profile_private_identity where profile_id=auth.uid()),
 'organizations',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'display_name',o.display_name,'organization_type',o.organization_type,'market_role',o.market_role,'buyer_subtype',o.buyer_subtype,
 'is_owner',private.eventcore_org_owner(o.id),'can_operate',private.eventcore_org_manager(o.id),'can_finance',private.eventcore_org_finance(o.id)) order by o.created_at,o.id) from public.organizations o where private.eventcore_org_member(o.id)),'[]'::jsonb));
end $$;
create function public.can_finance_event(p_event_id uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select private.eventcore_can_finance_event(p_event_id);
$$;
create function public.list_commercial_providers() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'display_name',o.display_name,'organization_type',o.organization_type,
 'specialties',coalesce((select jsonb_agg(s.name order by s.name) from public.organization_specialties os join public.specialties s on s.id=os.specialty_id where os.organization_id=o.id and s.active),'[]'::jsonb)) order by o.display_name,o.id)
 from public.organizations o where o.active and o.market_role='provider'),'[]'::jsonb);
end $$;
create function public.get_commercial_workspace(p_organization_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_org_finance(p_organization_id) then raise exception 'forbidden'; end if;
 return jsonb_build_object(
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id) from public.contract_requests r where r.provider_organization_id=p_organization_id or r.buyer_organization_id=p_organization_id),'[]'::jsonb),
 'quotes',coalesce((select jsonb_agg(public.get_sale_quote(p.id) order by p.created_at desc,p.id) from public.proposals p where p.organization_id=p_organization_id or (p.buyer_organization_id=p_organization_id and p.status in ('sent','accepted'))),'[]'::jsonb),
 'contracts',coalesce((select jsonb_agg((to_jsonb(c)-'external_evidence')||jsonb_build_object('received_total',coalesce((select sum(r.amount) from public.customer_receipts r where r.contract_id=c.id),0),
 'receivable_total',c.sale_total-coalesce((select sum(r.amount) from public.customer_receipts r where r.contract_id=c.id),0)) order by c.accepted_at desc,c.id) from public.commercial_contracts c where c.provider_organization_id=p_organization_id or c.buyer_organization_id=p_organization_id),'[]'::jsonb),
 'receipts',coalesce((select jsonb_agg(to_jsonb(r)-array['idempotency_key','recorded_by'] order by r.created_at desc,r.id) from public.customer_receipts r join public.commercial_contracts c on c.id=r.contract_id where c.provider_organization_id=p_organization_id or c.buyer_organization_id=p_organization_id),'[]'::jsonb));
end $$;
create function public.get_event_operations(p_event_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.eventcore_can_manage_event(p_event_id) then raise exception 'forbidden'; end if;
 return jsonb_build_object('event',(select jsonb_build_object('id',e.id,'name',e.name,'organization_id',e.organization_id,
 'status',e.status,'start_at',e.start_at,'end_at',e.end_at,'venue',e.venue,'arrival_tolerance_minutes',e.arrival_tolerance_minutes) from public.events e where e.id=p_event_id),
 'can_finance',private.eventcore_can_finance_event(p_event_id),
 'can_hire',private.eventcore_can_hire_event(p_event_id) and private.eventcore_can_finance_event(p_event_id) and exists(select 1 from public.events e where e.id=p_event_id and e.status not in ('completed','cancelled')),
 'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'event_id',s.event_id,'label',s.label,'service_type',s.service_type,
 'specialty_id',s.specialty_id,'quantity_needed',s.quantity_needed,'reserve_target',s.reserve_target,'contract_days',s.contract_days,
 'briefing',s.briefing,'requirements',s.requirements,'visibility',s.visibility,'application_enabled',s.application_enabled) order by s.created_at,s.id) from public.event_services s where s.event_id=p_event_id),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'event_service_id',a.event_service_id,'freelancer_id',a.freelancer_id,'status',a.status) order by a.created_at,a.id)
 from public.assignments a join public.event_services s on s.id=a.event_service_id where s.event_id=p_event_id),'[]'::jsonb));
end $$;

-- Preserve current signatures and business validations; tighten only authorization.
CREATE OR REPLACE FUNCTION public.complete_profile(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=(select auth.uid()); p public.profiles; kind text:=p_payload->>'profile_type'; doc_type text:=p_payload->>'document_type'; doc text:=upper(regexp_replace(coalesce(p_payload->>'document',p_payload->>'document_number'),'[./\s-]','','g')); ids uuid[]; org uuid; org_kind text;
begin
 select * into p from public.profiles where id=uid and active for update;
 if not found then raise exception 'unauthorized'; end if;
 if kind not in ('freelancer','team_lead','company','agency') or kind is null then raise exception 'invalid_profile_type'; end if;
 if p.onboarding_completed and p.profile_type is not null and p.profile_type<>kind then raise exception 'profile_type_locked'; end if;
 if length(trim(coalesce(p_payload->>'full_name','')))<2 or length(p_payload->>'full_name')>150 then raise exception 'invalid_full_name'; end if;
 if coalesce(doc,'')='' then select document_number,document_type into doc,doc_type from public.profile_private_identity where profile_id=uid; end if;
 doc_type:=case when length(doc)=11 then 'cpf' else 'cnpj' end;
 if doc is null or doc_type is null or not private.eventcore_document_valid(doc_type,doc) or (kind='freelancer' and doc_type<>'cpf') then raise exception 'invalid_private_document'; end if;
 select coalesce(array_agg(distinct value::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(coalesce(p_payload->'specialty_ids','[]'));
 if cardinality(ids)=0 or exists(select 1 from unnest(ids) x where not exists(select 1 from public.specialties where id=x and active)) then raise exception 'select_active_specialties'; end if;
 if kind<>'freelancer' and length(trim(coalesce(p_payload->>'organization_name','')))<2 then raise exception 'organization_name_required'; end if;
 insert into public.profile_private_identity(profile_id,document_type,document_number) values(uid,doc_type,doc) on conflict(profile_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,updated_at=now();
 update public.profiles set full_name=trim(p_payload->>'full_name'),phone=nullif(trim(p_payload->>'phone'),''),profile_type=kind,onboarding_completed=true,bio=left(p_payload->>'bio',1000),professional_status=case when p_payload->>'professional_status' in ('available','busy','unavailable') then p_payload->>'professional_status' else 'available' end,updated_at=now() where id=uid;
 delete from public.profile_specialties where profile_id=uid;
 insert into public.profile_specialties(profile_id,specialty_id) select uid,unnest(ids);
 if kind='freelancer' then
   insert into public.freelancers(profile_id,full_name,phone,city,active,rating,completed_jobs) values(uid,trim(p_payload->>'full_name'),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'city'),''),true,0,0)
   on conflict(profile_id) do update set full_name=excluded.full_name,phone=excluded.phone,city=coalesce(excluded.city,public.freelancers.city),updated_at=now();
 else
   org_kind:=case when kind='team_lead' then 'team' else kind end;
   select id into org from public.organizations where owner_profile_id=uid and active order by created_at limit 1 for update;
   if org is null then insert into public.organizations(owner_profile_id,organization_type,display_name,business_type) values(uid,org_kind,trim(p_payload->>'organization_name'),nullif(p_payload->>'business_type','')) returning id into org;
   else update public.organizations set display_name=trim(p_payload->>'organization_name'),business_type=nullif(p_payload->>'business_type',''),updated_at=now() where id=org; end if;
   insert into public.organization_members(organization_id,profile_id,member_role,active) values(org,uid,'owner',true) on conflict(organization_id,profile_id) do nothing;
   delete from public.organization_specialties where organization_id=org;
   insert into public.organization_specialties(organization_id,specialty_id) select org,unnest(ids);
 end if;
 if org is not null and p_payload ? 'market_role' then
   perform public.configure_business_identity(jsonb_build_object('organization_id',org,'display_name',trim(p_payload->>'organization_name'),'organization_type',org_kind,'document',doc,'market_role',p_payload->>'market_role','buyer_subtype',p_payload->>'buyer_subtype'));
 end if;
 return jsonb_build_object('completed',true,'organization_id',org);
exception when unique_violation then raise exception 'private_document_conflict';
end $function$
;
CREATE OR REPLACE FUNCTION private.eventcore_guard_tenant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin

  if tg_table_name='clients' then
    if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then raise exception 'tenant_is_immutable'; end if;
  end if;
  if tg_table_name='events' then
    if tg_op='UPDATE' and (new.organization_id is distinct from old.organization_id or new.created_by_profile_id is distinct from old.created_by_profile_id or new.coordinator_id is distinct from old.coordinator_id or new.client_id is distinct from old.client_id or new.proposal_id is distinct from old.proposal_id) then raise exception 'event_ownership_is_immutable'; end if;
    if tg_op='INSERT' and (new.proposal_id is not null or not private.eventcore_valid_event_tenant(new.organization_id,new.client_id,new.created_by_profile_id,new.coordinator_id)) then raise exception 'invalid_event_tenant'; end if;
    if new.status='completed' and (new.end_at is null or new.end_at>now()) then raise exception 'event_has_not_ended'; end if;
  end if;
  if tg_table_name='event_services' then
    if tg_op='UPDATE' and new.event_id is distinct from old.event_id then raise exception 'service_event_is_immutable'; end if;
    if new.quantity_needed<(select count(*) from public.assignments where event_service_id=old.id and status in ('invited','confirmed','checked_in','checked_out')) then raise exception 'capacity_below_assignments'; end if;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.create_event_assignment(p_service_id uuid, p_freelancer_id uuid, p_status text DEFAULT 'invited'::text, p_amount numeric DEFAULT NULL::numeric, p_application_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.event_services; ev public.events; a uuid; amount numeric; app public.job_applications; existing public.assignments;
begin
 select * into s from public.event_services where id=p_service_id for update; select * into ev from public.events where id=s.event_id for update;
 if s.id is null or not private.eventcore_can_hire_event(s.event_id) then raise exception 'forbidden'; end if;
 if not private.eventcore_can_finance_event(s.event_id) then raise exception 'forbidden'; end if;
 if ev.status in ('completed','cancelled') then raise exception 'event_closed'; end if;
 if not exists(select 1 from public.freelancers f where f.id=p_freelancer_id and f.active and (f.profile_id is null or exists(select 1 from public.profiles where id=f.profile_id and active and (profile_type='freelancer' or (profile_type is null and private.eventcore_is_staff()))))) then raise exception 'professional_unavailable'; end if;
 if p_status not in ('invited','confirmed','reserve') or p_status is null or (p_amount is not null and (p_amount not between 0 and 9999999999.99 or p_amount<>round(p_amount,2))) then raise exception 'invalid_assignment'; end if;
 amount:=coalesce(p_amount,s.freelancer_unit_cost);
 if p_application_id is not null then
  select * into app from public.job_applications where id=p_application_id for update;
  if app.id is null or app.event_service_id<>s.id or app.freelancer_id<>p_freelancer_id or app.status not in ('interested','shortlisted') or p_status='reserve' then raise exception 'application_unavailable'; end if;
 end if;
 select * into existing from public.assignments where event_service_id=s.id and freelancer_id=p_freelancer_id for update;
 if existing.id is not null then
  if existing.status<>'cancelled' then raise exception 'professional_already_assigned'; end if;
  if existing.application_id is not null and p_application_id is distinct from existing.application_id then raise exception 'application_requires_reapply'; end if;
  update public.assignments set status=p_status,agreed_amount=amount,application_id=p_application_id,invited_at=now(),confirmed_at=null where id=existing.id returning id into a;
 else
  insert into public.assignments(event_service_id,freelancer_id,status,agreed_amount,application_id) values(s.id,p_freelancer_id,p_status,amount,p_application_id) returning id into a;
 end if;
 if amount is not null then
  insert into public.payments(assignment_id,amount,status) values(a,amount,'pending')
  on conflict(assignment_id) do update set amount=excluded.amount,status='pending',method=null,paid_at=null,updated_at=now() where public.payments.status='cancelled';
 end if;
 if p_application_id is not null then update public.job_applications set status='accepted',updated_at=now() where id=p_application_id; end if;
 update public.events set calendar_sync_status=case when google_event_id is null then 'pending' else 'out_of_sync' end,updated_at=now() where id=ev.id;
 return a;
end $function$
;
CREATE OR REPLACE FUNCTION public.mark_assignment_paid(p_assignment_id uuid, p_method text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.assignments; amount numeric;
begin
 select * into a from public.assignments where id=p_assignment_id for update;
 if not private.eventcore_can_pay_assignment(a.id) then raise exception 'forbidden'; end if;
 if a.status in ('cancelled','reserve','no_show') or p_method is null or p_method not in ('pix','transfer','cash','other') then raise exception 'invalid_payment'; end if;
 select p.amount into amount from public.payments p where p.assignment_id=a.id;
 amount:=coalesce(amount,a.agreed_amount);
 if amount is null or amount not between 0.01 and 9999999999.99 or amount<>round(amount,2) then raise exception 'payment_amount_required'; end if;
 insert into public.payments(assignment_id,amount,status,method,paid_at) values(a.id,amount,'paid',p_method,now()) on conflict(assignment_id) do update set status='paid',method=excluded.method,paid_at=coalesce(public.payments.paid_at,excluded.paid_at),updated_at=now();
end $function$
;
CREATE OR REPLACE FUNCTION private.eventcore_set_assignment_amount(p_assignment_id uuid, p_amount numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare service_id uuid; event_id uuid; event_status text; a public.assignments; p public.payments;
begin
  if (select auth.uid()) is null or not private.eventcore_can_pay_assignment(p_assignment_id) then raise exception 'forbidden'; end if;
  if p_amount is null or not (p_amount between 0 and 9999999999.99) or p_amount<>round(p_amount,2) then raise exception 'invalid_payment_amount'; end if;
  select event_service_id into service_id from public.assignments where id=p_assignment_id;
  -- Match the hiring lock order before the assignment trigger locks the service.
  select s.event_id into event_id from public.event_services s where s.id=service_id for update;
  select * into a from public.assignments where id=p_assignment_id for update;
  if a.id is null or not private.eventcore_finances_assignment(a.id) then raise exception 'forbidden'; end if;
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
$function$
;
CREATE OR REPLACE FUNCTION private.guard_freelancer_assignment_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.event_services; f public.freelancers; n int; reopening boolean:=false; manager boolean;
begin
 select * into s from public.event_services where id=new.event_service_id for update;
 select * into f from public.freelancers where id=new.freelancer_id;
 manager:=private.eventcore_can_manage_event(s.event_id) or private.eventcore_can_finance_event(s.event_id);
 if tg_op='INSERT' then
  if not private.eventcore_can_hire_event(s.event_id) or not private.eventcore_can_finance_event(s.event_id) then raise exception 'forbidden'; end if;
  if not manager then raise exception 'forbidden'; end if;
  if f.profile_id=(select auth.uid()) then raise exception 'self_hiring_not_allowed'; end if;
  if new.status not in ('invited','confirmed','reserve') then raise exception 'invalid_initial_assignment_status'; end if;
  new.contractor_profile_id:=(select auth.uid()); new.hired_at:=now();
 else
  reopening:=old.status='cancelled' and new.status in ('invited','confirmed','reserve') and manager;
  if new.id is distinct from old.id or new.freelancer_id is distinct from old.freelancer_id or new.event_service_id is distinct from old.event_service_id or new.created_at is distinct from old.created_at then raise exception 'assignment_identity_is_immutable'; end if;
  if not reopening and (new.contractor_profile_id is distinct from old.contractor_profile_id or new.application_id is distinct from old.application_id or new.hired_at is distinct from old.hired_at) then raise exception 'assignment_identity_is_immutable'; end if;
  if reopening then
   if not private.eventcore_can_hire_event(s.event_id) or not private.eventcore_can_finance_event(s.event_id) then raise exception 'forbidden'; end if;
   if f.profile_id=(select auth.uid()) then raise exception 'self_hiring_not_allowed'; end if;
   if (old.application_id is not null and new.application_id is distinct from old.application_id) then raise exception 'assignment_identity_is_immutable'; end if;
   if exists(select 1 from public.attendance where assignment_id=old.id and check_in_at is not null) or exists(select 1 from public.ratings where assignment_id=old.id) or exists(select 1 from public.payments where assignment_id=old.id and status='paid') then raise exception 'historical_assignment_cannot_reopen'; end if;
   new.contractor_profile_id:=(select auth.uid()); new.hired_at:=now();
  end if;
  if new.agreed_amount is distinct from old.agreed_amount and not private.eventcore_can_pay_assignment(old.id) then raise exception 'forbidden'; end if;
  if not manager and (not private.eventcore_owns_freelancer(f.id) or new.agreed_amount is distinct from old.agreed_amount or new.invited_at is distinct from old.invited_at or new.confirmed_at is distinct from old.confirmed_at) then raise exception 'freelancer_may_only_change_status'; end if;
  if new.status is distinct from old.status and not private.eventcore_is_staff() and not (reopening or
   (old.status in ('invited','reserve') and new.status in ('confirmed','cancelled')) or
   (old.status='confirmed' and new.status in ('checked_in','cancelled')) or
   (old.status='checked_in' and new.status='checked_out')) then raise exception 'invalid_assignment_status_transition'; end if;
  if new.status='checked_in' and old.status<>'checked_in' and not private.eventcore_is_staff() and not exists(select 1 from public.attendance where assignment_id=old.id and check_in_at is not null) then raise exception 'attendance_required'; end if;
  if new.status='checked_out' and old.status<>'checked_out' and not private.eventcore_is_staff() and not exists(select 1 from public.attendance where assignment_id=old.id and check_out_at is not null) then raise exception 'attendance_required'; end if;
 end if;
 if new.application_id is not null and not exists(select 1 from public.job_applications where id=new.application_id and event_service_id=s.id and freelancer_id=f.id) then raise exception 'invalid_application_link'; end if;
 if new.status in ('invited','confirmed','checked_in','checked_out') and (tg_op='INSERT' or old.status not in ('invited','confirmed','checked_in','checked_out')) then
  select count(*) into n from public.assignments where event_service_id=s.id and id<>new.id and status in ('invited','confirmed','checked_in','checked_out');
  if n>=s.quantity_needed then raise exception 'vacancies_filled'; end if;
 end if;
 if new.status='confirmed' then new.confirmed_at:=coalesce(new.confirmed_at,now()); end if;
 new.updated_at:=now(); return new;
end $function$
;

-- Service creation/publication guarded even inside an existing SECURITY DEFINER RPC.
create function private.eventcore_guard_provider_service() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or (tg_op='UPDATE' and (new.visibility is distinct from old.visibility or new.application_enabled is distinct from old.application_enabled)) then
  if not private.eventcore_can_hire_event(new.event_id) or not private.eventcore_can_finance_event(new.event_id) then raise exception 'forbidden'; end if;
 end if;
 if tg_op='UPDATE' and new.freelancer_unit_cost is distinct from old.freelancer_unit_cost and not private.eventcore_can_finance_event(new.event_id) then raise exception 'forbidden'; end if;
 return new;
end $$;
create trigger commercial_provider_service before insert or update on public.event_services for each row execute function private.eventcore_guard_provider_service();

-- No implicit PUBLIC execute. Trigger-only/DTO internals are not client endpoints.
revoke all on function private.eventcore_sale_quote_dto(uuid),private.eventcore_require_commercial(uuid,text),
 private.eventcore_guard_quote(),private.eventcore_commercial_immutable(),private.eventcore_guard_provider_service(),private.eventcore_guard_freelancer_owner() from public,anon,authenticated;
revoke all on function private.eventcore_active_actor(),private.eventcore_org_owner(uuid),private.eventcore_org_member(uuid),private.eventcore_org_manager(uuid),
 private.eventcore_org_finance(uuid),private.eventcore_has_identity(),private.eventcore_can_manage_event(uuid),private.eventcore_can_finance_event(uuid),
 private.eventcore_can_hire_event(uuid),private.eventcore_finances_assignment(uuid),private.eventcore_can_pay_assignment(uuid),private.eventcore_operates_freelancer(uuid),private.eventcore_valid_event_tenant(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function private.eventcore_active_actor(),private.eventcore_org_owner(uuid),private.eventcore_org_member(uuid),private.eventcore_org_manager(uuid),
 private.eventcore_org_finance(uuid),private.eventcore_has_identity(),private.eventcore_can_manage_event(uuid),private.eventcore_can_finance_event(uuid),
 private.eventcore_can_hire_event(uuid),private.eventcore_finances_assignment(uuid),private.eventcore_can_pay_assignment(uuid),private.eventcore_operates_freelancer(uuid),private.eventcore_valid_event_tenant(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function public.configure_business_identity(jsonb),public.set_organization_finance_member(uuid,uuid,boolean),
 public.create_contract_request(uuid,uuid,text,text,date,text),public.save_sale_quote(jsonb,jsonb),public.get_sale_quote(uuid),
 public.submit_sale_quote(uuid,integer),public.accept_sale_quote(uuid,integer,text),public.record_customer_receipt(uuid,numeric,text,date,text),
 public.get_commercial_context(),public.can_finance_event(uuid),public.list_commercial_providers(),public.get_commercial_workspace(uuid),public.get_event_operations(uuid) from public,anon;
grant execute on function public.configure_business_identity(jsonb),public.set_organization_finance_member(uuid,uuid,boolean),
 public.create_contract_request(uuid,uuid,text,text,date,text),public.save_sale_quote(jsonb,jsonb),public.get_sale_quote(uuid),
 public.submit_sale_quote(uuid,integer),public.accept_sale_quote(uuid,integer,text),public.record_customer_receipt(uuid,numeric,text,date,text),
 public.get_commercial_context(),public.can_finance_event(uuid),public.list_commercial_providers(),public.get_commercial_workspace(uuid),public.get_event_operations(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.create_event_with_services(p_event jsonb, p_services jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  client uuid; organization uuid; starts timestamptz; ends timestamptz; tolerance integer;
  event_name text; venue_name text; event_status text;
  created_event public.events; created_service public.event_services; specialty public.specialties;
  draft jsonb; quantity integer; reserves integer; days integer; cost numeric; publish boolean;
  created_services jsonb := '[]'::jsonb;
begin
  if actor is null or not private.eventcore_active_actor() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_event) is distinct from 'object' then raise exception 'invalid_event_data'; end if;
  if jsonb_typeof(p_services) is distinct from 'array' then raise exception 'invalid_event_function'; end if;
  begin
    client := nullif(p_event->>'client_id','')::uuid;
    organization := nullif(p_event->>'organization_id','')::uuid;
    starts := (p_event->>'start_at')::timestamptz;
    ends := (p_event->>'end_at')::timestamptz;
    tolerance := coalesce(nullif(p_event->>'arrival_tolerance_minutes','')::integer,15);
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_event_data';
  end;
  event_name := btrim(p_event->>'name'); venue_name := btrim(p_event->>'venue');
  event_status := coalesce(p_event->>'status','planning');
  if coalesce(event_name,'')='' or coalesce(venue_name,'')='' or starts is null or ends is null
    or not isfinite(starts) or not isfinite(ends) or ends<=starts or tolerance<0 or tolerance>180
    or event_status not in ('planning','staffing','confirmed') then raise exception 'invalid_event_data'; end if;
  if not private.eventcore_org_finance(organization) then raise exception 'forbidden'; end if;
  if not private.eventcore_valid_event_tenant(organization,client,actor,actor)
    or not exists(select 1 from public.clients c where c.id=client and c.active) then raise exception 'forbidden'; end if;

  insert into public.events(client_id,name,venue,start_at,end_at,status,arrival_tolerance_minutes,
    coordinator_id,created_by_profile_id,organization_id,notes,calendar_sync_status)
  values(client,event_name,venue_name,starts,ends,event_status,tolerance,actor,actor,organization,
    nullif(btrim(p_event->>'notes'),''),'pending') returning * into created_event;

  for draft in select value from jsonb_array_elements(p_services) loop
    if jsonb_typeof(draft) is distinct from 'object' then raise exception 'invalid_event_function'; end if;
    -- Old cached clients omit this new field; new creations still default to one day.
    begin
      days := case when draft ? 'contract_days' then (draft->>'contract_days')::integer else 1 end;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'invalid_contract_days';
    end;
    if days is null or days < 1 then raise exception 'invalid_contract_days'; end if;
    begin
      select * into specialty from public.specialties where id=nullif(draft->>'specialty_id','')::uuid and active;
      quantity := (draft->>'quantity_needed')::integer;
      reserves := coalesce(nullif(draft->>'reserve_target','')::integer,0);
      cost := nullif(draft->>'freelancer_unit_cost','')::numeric;
      publish := coalesce((draft->>'open_marketplace')::boolean,false);
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'invalid_event_function'; end;
    if specialty.id is null then raise exception 'invalid_event_specialty'; end if;
    if quantity is null or quantity<1 or reserves<0
      or (cost is not null and (cost::text in ('NaN','Infinity','-Infinity') or cost<0 or cost>9999999999.99 or cost<>round(cost,2)))
      then raise exception 'invalid_event_function'; end if;
    insert into public.event_services(event_id,specialty_id,service_type,label,quantity_needed,reserve_target,contract_days,
      freelancer_unit_cost,briefing,requirements,visibility,application_enabled)
    values(created_event.id,specialty.id,case when specialty.slug in ('loader','security','waiter') then specialty.slug else 'other' end,
      specialty.name,quantity,reserves,days,cost,nullif(btrim(draft->>'briefing'),''),nullif(btrim(draft->>'requirements'),''),
      case when publish then 'open' else 'private' end,publish) returning * into created_service;
    created_services := created_services || jsonb_build_array(to_jsonb(created_service));
  end loop;
  return jsonb_build_object('event',to_jsonb(created_event),'services',created_services);
end $function$
;

CREATE OR REPLACE FUNCTION public.set_organization_member(p_organization_id uuid, p_profile_id uuid, p_active boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.eventcore_org_manager(p_organization_id) then raise exception 'forbidden'; end if;
 if exists(select 1 from public.organizations where id=p_organization_id and owner_profile_id=p_profile_id) then raise exception 'owner_membership_is_immutable'; end if;
 if exists(select 1 from public.organization_members where organization_id=p_organization_id and profile_id=p_profile_id and member_role='manager') and not private.eventcore_org_owner(p_organization_id) then raise exception 'owner_required_for_manager_changes'; end if;
 if exists(select 1 from public.organization_members where organization_id=p_organization_id and profile_id=p_profile_id and finance_authorized) and not private.eventcore_org_owner(p_organization_id) then raise exception 'forbidden'; end if;
 if not exists(select 1 from public.profiles where id=p_profile_id and active) then raise exception 'profile_unavailable'; end if;
 insert into public.organization_members(organization_id,profile_id,member_role,active) values(p_organization_id,p_profile_id,'member',p_active) on conflict(organization_id,profile_id) do update set active=excluded.active,finance_authorized=case when excluded.active then public.organization_members.finance_authorized else false end;
end $function$
;

-- Buyer/provider discovery is sanitized; only workers receive the advertised remuneration.
CREATE OR REPLACE FUNCTION public.get_event_opportunities()
 RETURNS TABLE(service_id uuid, event_id uuid, event_name text, start_at timestamp with time zone, end_at timestamp with time zone, venue text, function_name text, specialty_id uuid, vacancies integer, amount numeric, contractor_name text, requirements text, event_status text, compatible boolean, contract_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select s.id,e.id,e.name,e.start_at,e.end_at,e.venue,s.label,s.specialty_id,
 greatest(0,s.quantity_needed-(select count(*)::int from public.assignments a where a.event_service_id=s.id and a.status in ('invited','confirmed','checked_in','checked_out'))),case when private.eventcore_profile_type()='freelancer' then s.freelancer_unit_cost else null end,coalesce(o.display_name,p.full_name,'EventCore'),s.requirements,e.status,
 (s.specialty_id is null or exists(select 1 from public.profile_specialties ps where ps.profile_id=(select auth.uid()) and ps.specialty_id=s.specialty_id)),s.contract_days
 from public.event_services s join public.events e on e.id=s.event_id left join public.organizations o on o.id=e.organization_id left join public.profiles p on p.id=coalesce(e.created_by_profile_id,e.coordinator_id)
 where s.visibility='open' and s.application_enabled and e.status in ('planning','staffing','confirmed','in_progress') and coalesce(e.end_at,e.start_at)>now()
 and exists(select 1 from public.profiles where id=(select auth.uid()) and active and onboarding_completed)
 and (e.organization_id is null or o.active) order by e.start_at,s.label;
$function$;

revoke all on function public.get_event_opportunities() from public, anon;
grant execute on function public.get_event_opportunities() to authenticated, service_role;
