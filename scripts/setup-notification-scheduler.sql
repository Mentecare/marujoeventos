-- Controller-only activation AFTER endpoint authentication + consenting test recipient proof.
-- psql -X --set=ON_ERROR_STOP=1 --file=scripts/setup-notification-scheduler.sql
-- Environment inputs (never echo or supply on argv):
-- EVENTCORE_NOTIFICATION_WORKER_URL: exact verified HTTPS endpoint
-- EVENTCORE_NOTIFICATION_DISPATCH_SECRET: same >=32-character server secret
-- EVENTCORE_NOTIFICATION_BYPASS_SECRET_NAME: optional existing Vault name, NOT its token
\set ON_ERROR_STOP on
\set ECHO none
\getenv worker_url EVENTCORE_NOTIFICATION_WORKER_URL
\getenv dispatch_secret EVENTCORE_NOTIFICATION_DISPATCH_SECRET
\getenv bypass_secret_name EVENTCORE_NOTIFICATION_BYPASS_SECRET_NAME
begin;
create extension if not exists pg_cron;
create extension if not exists pg_net;
-- Supabase Vault is already installed in this project. Do not expose its views.
create temporary table notification_activation_input(url text,secret text,bypass_name text) on commit drop;
insert into notification_activation_input values(:'worker_url',:'dispatch_secret',:'bypass_secret_name');
do $$
declare input record; existing uuid;
begin
 select * into input from notification_activation_input;
 if input.url !~ '^https://(eventcore[.]space|marujoeventos-[a-z0-9-]+[.]vercel[.]app)/api/internal/notifications$' or length(input.secret)<32 then raise exception 'Invalid verified worker URL or dispatcher secret'; end if;
 if coalesce(input.bypass_name,'')<>'' and not exists(select 1 from vault.secrets where name=input.bypass_name) then raise exception 'Optional deployment bypass Vault secret is missing'; end if;
 select id into existing from vault.secrets where name='eventcore_notification_dispatch_secret';
 if existing is null then perform vault.create_secret(input.secret,'eventcore_notification_dispatch_secret'); else perform vault.update_secret(existing,input.secret); end if;
 select id into existing from vault.secrets where name='eventcore_notification_worker_url';
 if existing is null then perform vault.create_secret(input.url,'eventcore_notification_worker_url'); else perform vault.update_secret(existing,input.url); end if;
 select id into existing from vault.secrets where name='eventcore_notification_bypass_name';
 if existing is null then perform vault.create_secret(coalesce(input.bypass_name,''),'eventcore_notification_bypass_name'); else perform vault.update_secret(existing,coalesce(input.bypass_name,'')); end if;
end $$;
create or replace function private.eventcore_schedule_notification_dispatch() returns bigint language plpgsql security definer set search_path='' as $$
declare url text; secret text; bypass_name text; bypass text; headers jsonb;
begin
 select decrypted_secret into url from vault.decrypted_secrets where name='eventcore_notification_worker_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='eventcore_notification_dispatch_secret';
 select decrypted_secret into bypass_name from vault.decrypted_secrets where name='eventcore_notification_bypass_name';
 if url !~ '^https://(eventcore[.]space|marujoeventos-[a-z0-9-]+[.]vercel[.]app)/api/internal/notifications$' or length(secret)<32 then raise exception 'Notification scheduler configuration missing'; end if;
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||secret);
 if coalesce(bypass_name,'')<>'' then
  select decrypted_secret into bypass from vault.decrypted_secrets where name=bypass_name;
  if bypass is null then raise exception 'Deployment bypass configuration missing'; end if;
  headers:=headers||jsonb_build_object('x-vercel-protection-bypass',bypass);
 end if;
 return net.http_post(url:=url,headers:=headers,body:='{}'::jsonb,timeout_milliseconds:=55000);
end $$;
revoke all on function private.eventcore_schedule_notification_dispatch() from public,anon,authenticated,service_role;
-- Named schedule is idempotent. No credentials appear in the cron command itself.
select cron.schedule('eventcore-notifications','* * * * *','select private.eventcore_schedule_notification_dispatch();');
commit;
