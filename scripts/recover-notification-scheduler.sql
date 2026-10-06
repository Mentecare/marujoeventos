-- Controller recovery: stops scheduler only; preserves every preference, outbox and receipt.
\set ON_ERROR_STOP on
begin;
select cron.unschedule(jobid) from cron.job where jobname='eventcore-notifications';
revoke all on function private.eventcore_schedule_notification_dispatch() from public,anon,authenticated,service_role;
commit;
-- To resume after endpoint verification, rerun setup with configured environment inputs.
-- Do not delete batches. Leases expire after five minutes and receipts survive retry.
-- Failed batches require a scoped controller repair after investigating the provider error:
-- update private.notification_batches set status='queued',attempts=0,available_at=now(),
-- lease_token=null,lease_until=null where id=:reviewed_batch_id and status='failed';
-- update private.notification_outbox set status='queued' where batch_id=:reviewed_batch_id
-- and status='failed';
-- Existing Resend idempotency applies for 24 hours; a later replay can duplicate a send.
