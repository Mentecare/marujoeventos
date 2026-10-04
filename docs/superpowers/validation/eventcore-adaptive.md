# EventCore adaptive validation

The interrupted build failed on the adaptive overlay checksum. The archive was damaged, including its gzip payload. The existing production source and Google patches were recovered and materialized as tracked source; the damaged reconstruction step was removed. The original archive remains in Git history.

## Verified implementation

- Four profile types and completion of existing accounts; private identity and database specialties.
- Personalized home, separate dashboards using real payments/assignments/ratings, tenant-scoped management and sanitized opportunities/schedules.
- Transactional application, selection, hire, presence, payment and actual completed-work reviews.
- Existing Google server modules/routes are byte-identical to the recovered production baseline. Existing projects, environment names and data are preserved.

## Regression evidence

`npm test`: 6 passing domain cases. TypeScript passes. Production build is checked locally and by the existing GitHub/Vercel workflows.

`tests/database-flow.sql`: five profile fixtures and real authenticated RLS/RPC calls, all in a transaction followed by rollback. Covers cross-organization reads/writes/hiring/selection denial; forged onboarding, reputation and accepted-application denial; capacity; hire idempotency; professional decline; cancellation of unpaid obligations; reapplication and reuse of the unique assignment; contractor cancellation/rejection; historical paid-record preservation; sanitized hired/declined schedule reads; actual presence/validation; completed-event review and duplicate-review denial.

The final review identified four material gaps. Cancellation failed with `decline_kept_application_accepted`; hired event privacy failed with `assigned_event_internal_data_leaked`; selection failed because `review_application` was absent; organization selection failed because the owned-organization helper was absent. After the consolidated corrections, all targeted regression checks pass. Remaining test users after rollback: zero.

## Verification boundaries

The connected browser checks the real preview and official domain's public authentication screens and profile-specific signup fields. No genuine customer credentials, Google account or device location are used. Authenticated browser workflows, real Google synchronization and device-specific mobile behavior remain unexercised. Database workflows are verified with rollback fixtures; overbooking is checked sequentially and locking reviewed, rather than a genuine two-connection race.

## Decision

Replace the corrupt binary overlay with directly tracked source while retaining the recovered production behavior. This makes the build reproducible and changes reviewable without recreating infrastructure or data.
