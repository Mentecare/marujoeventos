# Task 2 report — external work, immutable remuneration, private teams and real histories

Date: 2026-10-06. Status: DONE_WITH_CONCERNS (integration/hosted proof gates below). Worktree: `/workspace/scratch/0d27d86074e8/eventcore-aligned-flows`. Task base: `326f77847bbe4cb0e4ae9324572b4aaa1bbdd025`. Task 1 remained complete and unchanged. This continuation preserved the interrupted implementer's uncommitted migration, API, server, adapters and fixtures; it did not restart the feature or discard their edits. Commit ID is supplied by the final handoff because this report is part of that commit.

## Delivered behavior and requirements assessment

- External clients without accounts belong to an identified provider organization. New event origin (`platform|whatsapp|referral|other`, default `other`) is independent of per-function publication. Prior events retain NULL origin. A linked commercial contract must belong to the same provider/client, including raw event INSERT guards; one work event can link to a contract.
- Initial functions/quantities/days/hours/conditions are stored only through event creation. A private transaction-bound creation-session record permits the canonical RPC's function INSERT and is removed before return. Raw INSERT, post-creation identity/quantity/rate changes and DELETE reject. Only publication/application flags can change for open work. Owner raw UPDATE/DELETE and privileged bypass probes cover review I2; Task 1's canonical authorization helpers are reused.
- New daily remuneration uses an explicit basis: R$220 × 2 days = R$440 **per worker**, independently of sale rates or worker quantity. Service remuneration is rate plus additions minus deductions. Omitted basis/rate preserves legacy supplied total meaning. Creation copies function conditions into append-only assignment term revision 1. Availability acceptance explicitly accepts the current term; revised offers require the same worker to accept the latest revision before becoming payable. Days/hours cannot change in a revision. Closed/ended/cancelled/paid evidence cannot receive a new accepted revision. No historical assignments/payment amounts are rewritten. Review I3's completed historical setter and raw amount probes reject while original R$440 agreement/payment remain R$440.
- New payments use latest accepted term totals and append-only `workforce_payments`. Old `payments` amounts and legacy agreement totals stay intact. Worker/provider finance DTOs merge the two ledgers without copying/recalculating historical values. `assignments.agreed_amount` is the original amount, not a revised accepted payable.
- Private provider base and reusable teams have actual provider-owner writes and explicit membership; manager reads are tenant scoped. Base/team membership never allocates, accepts, completes work or earns reputation. Selected-recipient invitations use canonical hiring. Existing published application → authorized hire → invitation → worker acceptance → payment path is exercised. Removal/deletion of reusable membership leaves work history/reviews intact. General directory discovery is separate and returns measured review/job values rather than cached/default stars.
- Operational DTOs expose roles/team/status/hours and omit rates/benefits/sales. Worker assignment DTOs return only the actual worker's conditions and payment evidence. Provider remuneration/expense/finance reads require canonical finance permission. Buyers receive the sale snapshot, actual receipts and limited linked execution status, without identities/wages/costs. Exact output keys are asserted in SQL.
- Opportunity projection is explicitly sanitized: neutral function title, date-only Brazilian calendar timestamps, opted-in public region/description only; no private event name, exact venue/client, benefits, briefing/requirements or team fallback. Eligible workers see advertised **initial** terms; non-workers receive NULL remuneration/amount. No notification/channel dispatch is implemented here.
- Finance uses independent accepted-sale/customer-receipt, accepted/legacy labor/payment, and other-expense/payment sources. Legacy gross is contracted sale, received/receivable unknown. Unknown labor/expense amounts remain NULL, not zero. Legacy extras have no settlement source, so other paid/payable stay unknown when those extras exist. Estimate is explicitly before unresolved expenses/taxes. Existing `businessRevenue` totals remain compatible; canonical contracted/received/receivable/estimated additions do not fabricate receipts or known complete-period amounts.
- Full SQL example: contracted sale 5600, received 1000, receivable 4600; labor contracted 4400, actual paid 440, payable 3960; each of ten workers sees own 440. Initial estimate 1200; a 200 transport expense paid 50 gives other payable 150 and estimate 1000. Unknown extra expense restores NULL contracted-other/payable/result. Receipt and expense settlement retry/overpayment checks are distinct.
- Completed status alone, availability acceptance, registered work and base/team membership produce no history. Worker history needs ended completed work plus ordered validated check-in/out or explicit actual worker completion confirmation. Participant confirmation never fabricates punctuality. Buyer/provider history needs the actual buyer participant to confirm completed linked work. External customers without accounts do not become fabricated buyer reviewers. Stars, job/review counts and measured punctuality are separate; absent values are NULL. Sorting is deterministic as documented below.
- Worker/provider reviews require real evidence, authorized counterparty, bounded stars/comments and uniqueness. Dual-role worker/provider self-reviews reject. Existing valid rating rows remain stored; the migration does not synthesize evidence or rewrite cached profile metrics. Completed event dates/status/tolerance and completed assignment statuses cannot be reopened; recorded attendance also freezes its schedule, preserving punctuality evidence.
- Worker reputation/portfolio requires own identity or an actual canonical operating/finance event relationship. Buyer provider presentation/portfolio requires its actual request/contract relationship; unrelated staff/base membership is insufficient. Existing upload/storage/cleanup behavior is retained. Organization photo GET uses the authenticated caller's SQL authorization, then privileged signing of only returned stored paths, expiry 1200 seconds, private/no-store response. Invalid/mixed targets reject 404 before target RPC/signing.
- Business DATE validity uses the private São Paulo date helper; no stored DATE values are converted/re-written. Fixed `2026-10-07T00:54Z → 2026-10-06` regression is asserted. Quote save/submit/accept and customer/expense date checks use the canonical business day. Existing fixture-only completed-state resets are explicitly postgres-local in rolled-back transactions.

## Exact implemented interfaces for next task

The canonical signatures, complete DTO key lists and permissions are in `docs/superpowers/validation/2026-10-05-commercial-api.md`; `lib/commercial.ts` is the typed caller contract. Always pass the authenticated browser client or `commercialActor(request).db`, never a service client, to `workflowApi`.

Creation: `buildEventCreation(formData, functionKeys)` returns `EventCreationInput`; call `workflowApi(db).createWork(input.event, input.services)` → `CreatedWork`. Extended event fields: organization, origin, commercial contract and public region. Extended service fields: remuneration basis/rate, planned hours, benefits, additions, deductions, public description. Creation output is the compatible full database-row JSON for that authorized finance creator; subsequent reads must use scoped DTOs.

Workflow methods and public RPCs:

| Typed method | Public RPC |
| --- | --- |
| `createWork`, `createExternalClient`, `publishFunction`, `opportunities` | `create_event_with_services`, `create_external_work_client`, `publish_work_function`, `get_work_opportunities` |
| `inviteSelected`, `createAssignment`, `applyOpportunity`, `hireApplication`, `respond` | `invite_selected_workers`, `create_event_assignment`, `apply_for_opportunity`, `hire_application`, `respond_to_assignment` |
| `proposeTerms`, `acceptTerms`, `pay`, `workerAssignments`, `eventRemunerations` | `propose_assignment_terms`, `accept_assignment_terms`, `mark_assignment_paid`, `get_my_work_assignments`, `get_event_remunerations` |
| `people`, `setBaseMember`, `saveTeam`, `deleteTeam`, `setTeamMember` | `get_provider_people`, `set_provider_base_member`, `save_provider_team`, `delete_provider_team`, `set_provider_team_member` |
| `finance`, `recordExpense`, `payExpense` | `get_work_finance`, `record_work_expense`, `record_work_expense_payment` |
| `recordAttendance`, `validateAttendance`, `completeEvent`, `confirmWorkerCompletion`, `confirmContractCompletion` | retained attendance RPCs, `complete_work_event`, `confirm_assignment_completion`, `confirm_contract_completion` |
| `rateWorker`, `rateProvider`, `workerHistory`, `providerHistory`, `buyerWork`, `providerPresentation` | `submit_assignment_rating`, `submit_provider_rating`, `get_provider_worker_history`, `get_buyer_provider_history`, `get_buyer_work_status`, `get_provider_presentation` |

Retained `set_assignment_amount` validates authorization/cent input then rejects historical rewriting/new revision bypass. `createAssignment` accepts `invited|reserve`; it omits amount/application to use canonical SQL defaults. `applyOpportunity` sends `p_service_id,p_message`; `hireApplication` sends `p_application_id`; attendance sends `p_assignment_id,p_kind,p_lat,p_lng` (SQL timestamps only). `getEventOperations` and `getWorkerSchedule` adapters remain available. Other exact args are the API table and source.

Required output types: `CreatedWork`, `WorkRemuneration`, `AssignmentTerms`, `WorkerWorkAssignment`, `WorkOpportunity`, `ProviderPeople`, `WorkFinance`, `WorkerHistory`, `ProviderHistory`, `BuyerWorkStatus`, `ProviderPresentation`. All eight `WorkRemuneration` keys are required, nullable unknown values explicit. Opportunity benefits are always NULL. Worker payment rows include term ID (NULL for legacy). Accepted/offered terms are independent. Input optional fields do not imply missing SQL output keys.

Portfolio: `GET /api/profile/photos?organization_id=UUID` → existing `ProfilePhotoCollection` signed shape (`avatar`, `portfolio`). Retained `freelancer_id` and own-profile requests remain; supplying both organization/freelancer IDs rejects. SQL `get_provider_photo_collection(p_organization_id)` returns allowlisted photo metadata solely for this signing path, not private documents or finances.

History order: workers descending punctuality NULLS LAST, stars NULLS LAST, distinct actual event count, ascending name/id; providers descending stars NULLS LAST, review count, real contract count, ascending name/id. A worker with measured 0% punctuality precedes unmeasured NULL, as the fixture demonstrates.

## Files changed

New additive migration `supabase/migrations/20261006082244_eventcore_workflows_history.sql`; new `tests/workflows-security.sql` and `tests/profile-portfolio.test.mjs`; updated `lib/commercial.ts`, `lib/event-creation.ts`, `lib/finance.ts`, `lib/profile-photo-server.ts`, `app/api/profile/photos/route.ts`, `tests/commercial.test.mjs`, `tests/event-creation.test.mjs`, `tests/finance.test.mjs`, `tests/commercial-security.sql`, `tests/profile-photos.sql`, canonical API document and this report. No old migration, package/dependency, product UI, alerts/PDF code, Calendar integration or infrastructure was changed.

Continuation's narrow finishing changes: typed creation input/result instead of `Record`/ID-only output; required nullable remuneration output fields instead of optional-input reuse; adapters/tests for retained creation/application/hire/attendance workflow; exact SQL DTO allowlists, expense retry/conflict/unknown coverage; corrected documentation/actual verification claims. Migration behavior from the interrupted implementation was preserved.

## Fresh actual validation evidence

Baseline checks were rerun instead of trusting interrupted API prose (baseline units 43/43 and workflow 193). Final covering evidence after continuation changes:

```text
node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs /workspace/scratch/0d27d86074e8/eventcore-aligned-flows tests/workflows-security.sql tests/commercial-security.sql tests/profile-photos.sql tests/database-read.sql
Migration chain passed: 31 files; engine: PostgreSQL 17.5 on aarch64-unknown-linux-gnu ... Emscripten ... 32-bit
FIXTURE PASSED tests/workflows-security.sql statements=212
FIXTURE PASSED tests/commercial-security.sql statements=176
FIXTURE PASSED tests/profile-photos.sql statements=8
FIXTURE PASSED tests/database-read.sql statements=8
Disposable SQL validation complete; no hosted database was changed.
exit 0

node --experimental-strip-types --test tests/commercial.test.mjs tests/event-creation.test.mjs tests/finance.test.mjs tests/profile-portfolio.test.mjs
28 tests, 28 pass, 0 fail, 0 cancelled, 0 skipped, 0 todo
exit 0

npm test
44 tests, 44 pass, 0 fail, 0 cancelled, 0 skipped, 0 todo
exit 0

npm run typecheck
> tsc --noEmit
(no diagnostics)
exit 0
```

`git diff --check` passed (no output, exit 0). npm reports the existing environment-config `http-proxy` deprecation warning; it did not fail any check. SQL uses isolated fixture auth/org IDs, real PL/pgSQL/RLS with authenticated roles, exact-error/deny/allowlist checks, and rolls every fixture back. Unit portfolio checks run transpiled actual route/server code with mocked auth/storage boundaries and prove signing is not reached after authorization denial. Units also cover Brazilian dates, cent arithmetic, legacy total interpretation, unknown finance, independent creation terms and stable named RPC arguments/error propagation.

## Self-review

Read the binding spec, brief/continuation/handoff, Task 1 I2/I3 probes, entire new workflow interfaces/migration and touched server/adapter diffs. Checked additive/no-backfill behavior, canonical permission reuse, new RLS/grants/helper revocation, definer search paths, SQL immutable evidence triggers, private creation-session ownership, explicit output allowlists and money/date bounds. Term/payment paths serialize through existing service → event → assignment locks; expense settlements lock their expense before totals/idempotency; contract/quote paths retain foundation lock/revision behavior. No multi-session concurrency experiment was run, so locks are inspected, not hosted-race proof.

Confirmed I2/I3 closure by actual covering SQL, not hidden forms. Corrected the observed creation/output typing and required-key mismatch; added fixture assertions instead of relying on TypeScript casts. Found no remaining concrete Task 2 requirement gap after these corrections. Actual live preservation and compatible UI acceptance remain external gates below, not claims made from local tests.

## Recovery and application gates

No hosted DDL/deployment/credentials/messages, Storage/Calendar calls or browser baseline reruns occurred in this Task 2 continuation. The disposable runner's auth/storage shims do not prove actual hosted Auth/JWT/PostgREST grants, platform default privileges/advisors, private Storage signing or concurrent production sessions. Controller owns hosted compatible review/application/validation; do not apply this migration from the implementer worktree.

Controller reported a fresh read-only hosted inventory still has 29 applied migrations and existing event/assignment/payment hashes differ from discovery (updated around 00:02–00:06Z); service hash is unchanged. This was controller-supplied information, not observed by this implementer. Do not restore discovery rows or infer migration-caused drift. Take a fresh actual pre-application row/count/hash and definition/policy/ACL baseline preserving **current** records, while retaining the older discovery snapshot as history.

Before application, Task 3 must consume accepted terms/new merged payroll and canonical finance DTOs, handle creation-only/closed-event errors and intentional acceptance workflow, and respect scoped photo permissions. Existing raw amount-edit forms, old payroll-only assumptions and event/function editing are incompatible with the strengthened rules. Existing `businessRevenue` gross/net fields remain for compatibility and cannot be presented as actual received money/net profit. Alerts/public share/PDF flows belong to later tasks and must respect the documented sale-only/sanitized boundaries. Build/browser integration verification belongs with those UI changes; no backend-only baseline rerun was requested here.

Recovery is feature deactivation/additive restoration, not destructive schema rollback:

1. Disable the new workflow UI and revoke authenticated EXECUTE from new mutating creation/client/base/team/invitation/terms/expense/completion/review/publication entry points as needed. Stop dependent new flows while preserving reads/evidence and tighter privacy.
2. Retain new columns, all append-only terms/acceptances/workforce payments/expenses/settlements/completion confirmations/reviews, existing historical rows and tighter canonical ownership/finance/photo access. Do not drop data, reclassify organizations, recalculate historical totals, reopen completed events or restore broad worker/portfolio access.
3. Keep `a_workflow_*` creation/evidence guards and `workflow_immutable` evidence triggers. Restoring creation requires the saved canonical RPC, its private transaction-session mechanism and compatible ACLs together; removing its guard alone is not recovery.
4. If needed, prepare a separately reviewed additive recovery migration restoring individually captured compatible functions/policies/ACLs. Do not restore unrestricted historical amount setters/service edits/deletes or cross-tenant/generic-staff finance/photo reads. Preserve Brazilian DATE validity if restoring quote/receipt definitions, or explicitly review the UTC-midnight regression.
5. Rerun tenant/history/creation/accepted-payment fixtures and actual hosted baseline comparisons after a reviewed restoration. Recovery execution itself has not been run or claimed.

Migration filename generation: no local `supabase` CLI executable was available (`command -v supabase` returned no path). Renamed the interrupted future-dated `20261006103000_eventcore_workflows_history.sql` to `20261006082244_eventcore_workflows_history.sql` using Python `datetime.now(timezone.utc)` at the actual current UTC timestamp. SQL bytes were retained. This order-preserving rename follows Task 1 and allows later CLI-created migration dependencies to sort after Task 2; it was not falsely described as CLI-generated. Functional evidence above used the identical SQL under the prior filename before this rename.

## Fix round 1 — review I1 legacy NULL scheduled end preservation

Base `463afd6dcabb2b8c13a0aef615a7a2bc1c10dddd`, 2026-10-06. The scoped review confirmed a preservation defect: a real pre-Task2 rating accepted for completed checked-out work with ordered validated attendance became invisible when its scheduled `end_at` was NULL. Storing the old review was insufficient because the new actual-completed predicate filtered it out of every usable projection. Supplying an invented scheduled end or weakening completion to status/availability alone would violate the approved contract.

Changed only `private.eventcore_actual_completed_assignment` in the still-unapplied Task2 migration. Its normal/new-work evidence branch is unchanged. Its narrow preservation branch requires completed status, checked-out assignment, NULL scheduled end, NULL legacy origin, no new assignment terms, past scheduled start, ordered non-NULL actual check-in/check-out, actual check-out at or before now, and recorded validator/time. No data is updated, no scheduled date fabricated, and no confirmation operation relaxed. New events (non-NULL origin) and newly offered assignments on old events (terms present) cannot use this fallback. Original completed-date/assignment/pay immutability and creation-only guards, including review I2/I3 closures, are untouched. A valid prior review now remains visible to its actual worker and legitimate provider; attendance supplies real metrics independently from the review count.

Added `tests/legacy-review-preservation-before.sql` and `tests/legacy-review-preservation-after.sql`. These are paired fixtures, not standalone full-chain fixtures: BEFORE opens a transaction after the pre-Task2 migration chain, seeds only isolated historical records with temporary user-trigger suppression, restores normal triggers, and invokes the actual prior public rating RPC as the authenticated provider. The actual Task2 migration is applied inside that same disposable transaction. AFTER compares original review/assignment/payment/attendance JSON snapshots exactly, retains both NULL scheduled end/origin fields, checks actual worker/provider reputation and work history/directory, denies unrelated actor history/reputation, preserves duplicate-review/end-time/amount restrictions, and rolls the transaction back. Two actual legacy jobs with one four-star review and early/late attendance yield distinct metrics: job count 2, review count 1, average stars 4, punctuality count 2, punctuality 50%. Worker projection retains both NULL end times and original R$440 totals. Participant confirmation still rejects an unknown scheduled end because actual attendance already supplies the preserved evidence; no repair is needed.

Extended `tests/workflows-security.sql` with a nine-case disposable NULL-end evidence matrix: one legitimate legacy case is admitted; absent attendance, unvalidated attendance, reversed times, future check-out, new-work origin, new assignment terms, future scheduled start, and availability-only/confirmed status are excluded. Updated the canonical API document with the narrow legacy exception and accurately attributed validation. No TypeScript, app/server handler, UI, alerts/PDF or commercial calculation code changed; no unit/build rerun was needed for this SQL-only fix and the commercial fixture's outcomes/prerequisites were unaffected.

Actual red/green evidence:

```text
# Export the old committed SQL without modifying the worktree migration.
git show HEAD:supabase/migrations/20261006082244_eventcore_workflows_history.sql > /workspace/scratch/0d27d86074e8/eventcore-sql-validator/task2-before-i1.sql
EVENTCORE_SQL_THROUGH=20261006082243 node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs /workspace/scratch/0d27d86074e8/eventcore-aligned-flows tests/legacy-review-preservation-before.sql /workspace/scratch/0d27d86074e8/eventcore-sql-validator/task2-before-i1.sql tests/legacy-review-preservation-after.sql
Migration chain passed: 30 files; engine PostgreSQL 17.5
FIXTURE PASSED tests/legacy-review-preservation-before.sql statements=25
FIXTURE PASSED /workspace/scratch/0d27d86074e8/eventcore-sql-validator/task2-before-i1.sql statements=108
FIXTURE FAILED tests/legacy-review-preservation-after.sql FAIL: both validated actual legacy jobs remain admissible code=P0001
exit 1 (expected regression against pre-fix Task2)

EVENTCORE_SQL_THROUGH=20261006082243 node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs /workspace/scratch/0d27d86074e8/eventcore-aligned-flows tests/legacy-review-preservation-before.sql supabase/migrations/20261006082244_eventcore_workflows_history.sql tests/legacy-review-preservation-after.sql
Migration chain passed: 30 files; engine PostgreSQL 17.5
FIXTURE PASSED tests/legacy-review-preservation-before.sql statements=25
FIXTURE PASSED supabase/migrations/20261006082244_eventcore_workflows_history.sql statements=108
FIXTURE PASSED tests/legacy-review-preservation-after.sql statements=21
Disposable SQL validation complete; no hosted database was changed.
exit 0

node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs /workspace/scratch/0d27d86074e8/eventcore-aligned-flows tests/workflows-security.sql
Migration chain passed: 31 files; engine PostgreSQL 17.5
FIXTURE PASSED tests/workflows-security.sql statements=220
Disposable SQL validation complete; no hosted database was changed.
exit 0

git diff --check
(no output)
exit 0
```

Self-review: compared the unchanged actual prior rating admissibility, existing NULL schema permissions and review read filters; confirmed all relevant worker/provider/reputation/directory paths share the corrected predicate. Examined the fallback against mutable legacy markers: clients cannot set a new event's origin NULL or rewrite origin, and new assignments get terms, so canonical new work cannot opt into legacy admissibility. Trigger suppression is disposable seed-only and never used for public rating acceptance or post-migration authorization tests. The red run establishes that the regression detects I1 rather than simply validating its own seed. No other requirement or protection was weakened, and independent metrics are asserted rather than inferred from stars/status.

Recovery remains feature deactivation/reviewed additive restoration preserving current records and all accepted evidence, as above. Since Task2 has never been hosted-applied, this fix edits its unapplied migration rather than adding a misleading second hosted patch. If restoration is later necessary, retain this legacy predicate exception alongside immutable scheduled dates/history; reverting only to the old Task2 predicate would hide accepted historical reviews again. No live operations, messages, concurrent hosted proof or recovery execution occurred. Controller owns scoped re-review and later hosted preservation/JWT/integration gates.

Review M1: this required SQL invocation uses `node`, so no npm warning occurs and no needless npm suite rerun/config patch was made. At the next required npm validation, remove the obsolete environment setting for that process with `env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm test` (and the corresponding required npm command), rather than changing product code or exposing proxy values.
