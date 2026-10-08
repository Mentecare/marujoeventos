# EventCore final fix wave — scoped re-review

Status: COMPLETE. Exact base `43f2faf6aa53ea478745249d8b22e958d2d39ef2`; exact HEAD `2ae076261e948196671083824350ef490d28efcb` confirmed. Scope is I1–I8, M1–M8 and new breakage introduced by this fix range only. No fresh whole-branch review; no product/index/HEAD/branch mutation, external actions or subagents. Only this report is written. Controller progress.md is preserved.

Read re-review brief, final-fix brief, continuation and finalized report. Existing covering suites will not be rerun; commands/results will be assessed as reported evidence, with focused probes only for a concrete unanswered doubt. Hosted/physical activation gates and M6 upstream dependency follow-up remain explicit.

## Pass ledger
- Intake complete: exact HEAD and checkout state confirmed; fix report and binding constraints read.
- Pass 1 COMPLETE: original finding impacts/minor triage/declines, complete additive corrective migration, changed SQL fixtures and dependent authorization helpers inspected.
- Pass 2 COMPLETE: changed UI permissions/history/finance/notification and eligibility paths inspected against canonical SQL/fixtures.
- Pass 3 COMPLETE: PDF/runtime/font trace/CI/test changes and canonical documentation inspected; recorded final logs read; one narrow sale-source doubt ruled out by schema constraint.

Final verdicts and probe disposition are recorded below; early checkpoint assertions are superseded by the completed passes.

## Pass 1 — SQL authorization and immutable evidence

I1 ADDRESSED: corrective migration `supabase/migrations/20261008022315_eventcore_final_flow_corrections.sql:29,47,54–58` preserves live leased rows and requires nonempty, exact sorted claimed outbox membership plus token/expiry/cadence and every source authorization. The full/mixed digest interleavings in `tests/notifications-security.sql:113–130` check denied → second claim → still denied. This is stronger than EXISTS-only.

I5 ADDRESSED at SQL/lifecycle layer: immutable, unique resolution evidence, finance checks, row serialization, stable retry/conflict behavior (`...corrections.sql:60–64,80–93,112–127`); payment uses the effective amount and prevents overpayment (`:177–193`); projection counts the effective expense once (`:209–216`). UI amount-resolution/pay path is present in `app/components/work-finance.tsx:137–196`. Changed fixture tests unknown→known→paid, retry/conflict, original NULL evidence and raw/worker/tenant denials.

I7 ADDRESSED at SQL/lifecycle layer: finance-authorized append-only sale/receipt and matching late-contract links (`...corrections.sql:65–93,128–176,194–216`). Existing origin/ownership/contract fields remain immutable. Shared contract-row lock plus duplicate-link check (`:94–110,146–155`) preserve one-work-per-contract across original creation and later links. Changed workflow fixture tests external sale/receipt projection, late-link retry, immutable event, duplicate original insertion rejection, raw and tenant denials. UI sale/receipt/link forms are present in `app/components/work-finance.tsx:37–128`.

M1 ADDRESSED: revision 1 terms no longer enqueue a duplicate invitation (`...corrections.sql:8–11`); assignment source dedupe remains unchanged and subsequent revisions still enqueue. Fixture explicitly checks one initial invitation (`tests/notifications-security.sql:81`).

Reported evidence assessed, not rerun: disposable PostgreSQL17.5 chain34, notifications156, final workflows260 and interface70. No new Critical/Important/Minor SQL breakage confirmed in this pass. UI/async and runtime/CI passes remain in progress. No focused probes yet.

## Pass 2 — authorized UI reachability and eligibility

I2 ADDRESSED: `app/page.tsx:189–191` independently discovers remuneration through finance index; `:359` renders TeamPayments beside each authorized event. `app/components/work-finance.tsx:233–264` displays identified workers, accepted totals and payment history, with existing authorized pay RPC and no terms/operations controls. Interface70 proves two distinct wages, authorized pay, cross-tenant denial and unchanged operations denial; finance lifecycle browser evidence covers three widths and explicitly rejects operations RPC calls.

I3 ADDRESSED: `app/page.tsx:171,185–191,276–279,346–359` retains server-authorized creator history across buyer classification, including unowned-event finance/payment detail. Buyer status/calendar/new-event/hiring/publication controls are disabled/withheld (`:351–353`, `app/components/work-detail.tsx:30,66–70,166–176`). SQL interface classification regression retains original totals and denies hiring; legacy-buyer browser checks three widths and historical wage/payment evidence. This does not reassign historical organization/origin.

I8 ADDRESSED on reviewed scoped behavior: `app/components/notifications.tsx:5–65` account-binds polling to current session, limits overlapping requests, uses 10-second abort and visible 30-second/focus/read synchronization, clears failed/signout/account-mismatch data and cleans up on effect teardown. `app/page.tsx:140–141,326` provides accessible discreet unread status while center is closed. Explicit logout clears profile/center immediately (`:239`); permissions remain gesture-only (`notifications.tsx:103–135`). Actual notification fixture journey covers arrival in ordinary view, revoked-source removal, read/count synchronization, safe/stale deep targets, no boot Push and explicit logout cleanup. No fresh probing of unchanged auth architecture is inferred.

M3 ADDRESSED: canonical can_review plus unique/evidence checks (`...corrections.sql:221`, `work-detail.tsx:219–240`); worker completion eligibility excludes cancelled/reserve/no-show, unknown end and unaccepted conditions (`worker-work.tsx:60–65`); buyer reviewed/can_confirm states (`...corrections.sql:239`, `commercial-workspace.tsx:290–315`); sent draft editor cleared (`commercial-workspace.tsx:185–190`). Focused UI6, changed DTO fixture checks and provider browser evidence cover named states.

M4 ADDRESSED: named components' form/row/permission branches now readable multiline JSX; no behavior-changing redesign introduced. Some short handlers/page shell remain compressed, but the specific nested-form reviewability defect is addressed.

M7 ADDRESSED: `public/sw.js:41–43` navigates the matching allowlisted URL before focus; `tests/notification-sw.test.mjs:9–16` directly checks matching-document URL plus changed React view.

M8 ADDRESSED: `app/components/business-setup.tsx:53–64` defaults from actual organization_type, with company only for new setup. Provider/team and legacy-buyer/agency browser saves assert the submitted original type (`tests/aligned-flows.browser.mjs:98,133,139`).

No new Critical/Important/Minor UI breakage confirmed. Covering evidence is assessed without suite reruns. Remaining pass: PDF/runtime/CI/docs/evidence and final read-only state.

## Pass 3 — PDF, reproducible validation, diagnostics and documented limits

I4 ADDRESSED: `tests/runtime-tools.mjs:4–11` uses ordinary PATH tools or explicit EVENTCORE configuration for Poppler/Python/Playwright/Chromium, removing versioned Codex locations from changed drivers. `tests/quote-pdf.test.mjs:35–55,180,195` consumes that configuration. Required `EventCore CI / build` provisions Node24, Python3.12, Poppler, pinned PyMuPDF1.26.6, Playwright1.62.1 and Chromium, then runs actual units/type/build/font/native trace and PDF/browser/notifications integration (`.github/workflows/ci.yml:14–43`). The recorded npm80 execution explicitly unsets CODEX runtime tool variables while selecting installed executable overrides; this is configured reproducibility, not a claim that unprovisioned Python works. Hosted Actions success is not observed.

I6 ADDRESSED: renderer normalizes display strings on a copy to NFC and validates codepoints against both packaged regular/bold faces before producing the document (`lib/quote-pdf.ts:1–14,50–56`). Persisted snapshots are unchanged. Fontkit is a pinned direct dependency (`package.json:14`); licensed unmodified DejaVu assets are included with license and route trace (`lib/fonts/LICENSE-DejaVu.txt:1–51`, `next.config.ts:8–16`, `tests/pdf-deployment-trace.mjs:10`). Real text extraction verifies decomposed Portuguese and Cyrillic/Greek and rejects unsupported Japanese/emoji (`tests/quote-pdf.test.mjs:199–207`); actual route returns explicit422 (`lib/quote-pdf-route.ts:53–55`, `tests/quote-pdf.integration.mjs:97`), with actionable user feedback (`app/components/quote-pdf.tsx:39`). Existing sale-only DTO, measured tables/pagination, Brazilian totals/dates and every-page watermark/footer/URI remain intact. Recorded optimized route/trace/Poppler inspection supports local packaging/layout, not physical viewer proof.

M2 ADDRESSED at source: intended feature/main pushes plus pull_request/workflow_dispatch (`.github/workflows/ci.yml:3–7`) now select the meaningful provisioned `EventCore CI / build` job. `docs/superpowers/validation/2026-10-05-aligned-flows.md:220` names the intended check and explicitly reserves actual Actions execution/required branch-protection check verification for the controller. No hosted run/branch-protection state is inferred. The older adaptive-only workflow remains unrelated to this branch; it also receives the PDF prerequisites.

M5 ADDRESSED: actual photo-driver stderr is captured while remaining visible and exact2 fault-injected warnings are asserted (`tests/profile-photos.integration.mjs:10,78`). PDF shell fixture now answers privileged cleanup reads with the appropriate key and asserts zero cleanup warnings after terminating the server (`tests/quote-pdf.integration.mjs:73–76,135`). Recorded photo log has exactly2; optimized PDF server log has zero. Unexpected extra warnings fail the respective harness.

M6 NOT ADDRESSED — EXPLICITLY DEFERRED UPSTREAM, permitted nonblocking disposition by final-fix brief. `package.json:20` still pins web-push3.6.7 and `lib/notification-delivery.ts:3,38` still uses that SDK. Actual optimized log has one visible DEP0169; zero-network trace still identifies unchanged SDK generateRequestDetails/url.parse. `docs/superpowers/validation/2026-10-05-aligned-flows.md:151,195,236` and `docs/superpowers/validation/2026-10-06-notifications.md:47` preserve the dependency follow-up. No global suppression or vendor patch is introduced. The seven-scenario production integration still covers provider acknowledgment, missing acknowledgment/retry and410 expiry. This re-review does not establish availability/suitability of a newer maintained SDK; future modernization must repeat affected adapter checks and retain visible diagnostics.

Canonical docs accurately state29 hosted migrations remain applied and FIVE feature/corrective migrations are pending in dependency order (`docs/superpowers/validation/2026-10-05-aligned-flows.md:104–113`). Corrective migration adds only new evidence/lease membership and scoped function replacements; prior33 migration files remain unchanged in the fix range. Non-destructive recovery retains new and existing evidence/RLS, stops dependent callers/dispatch and uses saved definitions/ACLs plus reviewed roll-forward (`...commercial-api.md:262`; corrective migration header `:1–2`). No recorded local success is recast as live activation.

## Final per-finding verdicts

The full file for shorthand **SQL correction** below is `supabase/migrations/20261008022315_eventcore_final_flow_corrections.sql`.

| ID | Verdict | Final source evidence / practical boundary |
|---|---|---|
| I1 | ADDRESSED | SQL correction:29,47,54–58; exact lease membership and all source rechecks; notification race fixture:113–130. |
| I2 | ADDRESSED | app/page.tsx:189–191,359; work-finance.tsx:233–264; independent finance discovery and per-worker remuneration/history/pay without operations. |
| I3 | ADDRESSED | app/page.tsx:171,185–191,276–279,346–359; work-detail.tsx:30,66–70; historical creator views retained and buyer hiring withheld. |
| I4 | ADDRESSED | tests/runtime-tools.mjs:4–11; .github/workflows/ci.yml:14–43; configured/PATH validation with provisioned required job. Hosted result unobserved. |
| I5 | ADDRESSED | SQL correction:60–64,112–127,177–216; work-finance.tsx:137–196; append-only effective resolution→payment without rewriting/double counting. |
| I6 | ADDRESSED | lib/quote-pdf.ts:7–14,50–56; quote-pdf-route.ts:53–55; next.config.ts:8–16; quote-pdf.test.mjs:199–207; NFC/font fidelity and explicit unsupported rejection. |
| I7 | ADDRESSED | SQL correction:65–110,128–176,194–216; work-finance.tsx:37–128; append-only later sale/receipt/link, matching authorization and one-contract/work invariant. |
| I8 | ADDRESSED | notifications.tsx:5–65; app/page.tsx:140–141,239,326; bounded authenticated unread refresh/read synchronization and cleanup, without Push consent. |
| M1 | ADDRESSED | SQL correction:8–11; tests/notifications-security.sql:81; one initial invitation, later terms notices retained. |
| M2 | ADDRESSED | .github/workflows/ci.yml:3–7,14–43; validation doc:220; intended PR/feature check now configured; actual hosted/required-check proof pending. |
| M3 | ADDRESSED | SQL correction:221,239; work-detail.tsx:219–240; worker-work.tsx:60–65; commercial-workspace.tsx:185–190,290–315; canonical eligibility and cleared sent draft. |
| M4 | ADDRESSED | commercial-workspace.tsx:82–126,175–210,285–315; work-detail.tsx:96–156,179–243; work-finance.tsx:37–230; named nested branches/forms expanded. |
| M5 | ADDRESSED | tests/profile-photos.integration.mjs:10,78; quote-pdf.integration.mjs:73–76,135; exact expected diagnostic counts and complete cleanup boundary. |
| M6 | NOT ADDRESSED — DEFERRED | package.json:20; notification-delivery.ts:3,38; validation docs:151,195,236; SDK warning visible, unchanged vendor, repeated adapter evidence retained. |
| M7 | ADDRESSED | public/sw.js:41–43; tests/notification-sw.test.mjs:9–16; navigate matching safe target before focus. |
| M8 | ADDRESSED | business-setup.tsx:53–64; aligned-flows.browser.mjs:98,133,139; actual team/agency type default and submitted value preserved. |

## New fix-range breakage

- Critical: **0 confirmed**.
- Important: **0 confirmed**.
- Minor: **0 confirmed new**. Existing M6 remains deferred above.

One concrete doubt was investigated rather than promoted to a finding: SQL correction:201,211 prefers historical-source labeling when a legacy financial row exists. A supposedly unknown legacy row with NULL gross could have mislabeled a new sale, but `supabase/migrations/20261004211654_eventcore_event_revenues.sql:5` requires gross_amount NOT NULL, and record_work_sale rejects an existing known gross (`SQL correction:139`). The attempted fixture violated that existing constraint. The suspected product state is invalid; no defect is established.

## Evidence assessed / exact focused commands

Read finalized report, changed tests and recorded final logs in `/workspace/scratch/0d27d86074e8/eventcore-final-fix-evidence/`; did not rerun their suites. Log endings substantiate npm80/80 pass/0fail/0skip; typecheck; complete optimized8/8 build and route table; deployment trace; disposable chain34/workflows260, notifications156 and interface70; finance3+legacy-buyer3+provider1+coordinator1+arrival1 =9 role/viewport journeys; optimized PDF/dispatcher7 scenarios; photo exactly2 cleanup warnings and optimized PDF0; SDK trace/optimized DEP0169 visible. Preliminary failed logs remain explicitly excluded by final-fix-report. Final executable TS/JS evidence preceded only the last SQL duplicate-link guard, whose changed workflow fixture was rerun; no unsupported broad-freshness claim is made.

Only a focused in-memory SQL probe was attempted. First transport attempt used spawnSync to run the existing validator with `/dev/stdin`, providing the SQL shown below as input; chain34 loaded but `/dev/stdin` failed ENXIO before executing the fixture. This is a probe transport failure, not behavioral evidence. Exact first transport wrapper was `node --input-type=module -` with the same setup/SQL payload below and:

```sh
node --input-type=module - <<'JS'
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
const file=fs.readFileSync('tests/interface-finance-security.sql','utf8');
const setup=file.split('set local session_replication_role=origin;')[0];
const probe=setup+`
update public.event_financials set gross_amount=null where event_id='94000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.record_work_sale('94000000-0000-4000-8000-000000000001',1000,'New sale evidence');
select pg_temp.check_true((public.get_work_finance('94000000-0000-4000-8000-000000000001')->>'sale_contracted')::numeric=1000,'sale total is correct');
select pg_temp.check_true(public.get_work_finance('94000000-0000-4000-8000-000000000001')->>'sale_source'='recorded_sale','new sale source is recorded_sale, not legacy gross');
rollback;
`;
const r=spawnSync(process.execPath,['/workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs',process.cwd(),'/dev/stdin'],{input:probe,encoding:'utf8'});
process.stdout.write(r.stdout);process.stderr.write(r.stderr);process.exitCode=r.status??1;
JS
```

Second command evaluated the unchanged validator source in memory with only package-specifier resolution and fixture-read transport substituted; no product/test file was written:

```sh
node --input-type=module - <<'JS'
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const runner='/workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs';
const require=createRequire(runner);
const setup=fs.readFileSync('tests/interface-finance-security.sql','utf8').split('set local session_replication_role=origin;')[0];
globalThis.eventcoreFocusedSql=setup+`
update public.event_financials set gross_amount=null where event_id='94000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.record_work_sale('94000000-0000-4000-8000-000000000001',1000,'New sale evidence');
select pg_temp.check_true((public.get_work_finance('94000000-0000-4000-8000-000000000001')->>'sale_contracted')::numeric=1000,'sale total is correct');
select pg_temp.check_true(public.get_work_finance('94000000-0000-4000-8000-000000000001')->>'sale_source'='recorded_sale','new sale source is recorded_sale, not legacy gross');
rollback;
`;
let code=fs.readFileSync(runner,'utf8');
for(const spec of ['@electric-sql/pglite','@electric-sql/pglite/contrib/pgcrypto'])code=code.replace("'"+spec+"'",JSON.stringify(pathToFileURL(require.resolve(spec)).href));
code=code.replace("await fs.readFile(path.resolve(repo,fixture),'utf8')","globalThis.eventcoreFocusedSql");
process.argv=[process.execPath,runner,process.cwd(),'focused-sale-source-in-memory'];
await import('data:text/javascript,'+encodeURIComponent(code));
JS
```

Result exit1: chain34 loaded; fixture setup rejected with PostgreSQL23502, `null value in column "gross_amount" of relation "event_financials" violates not-null constraint`. No behavioral claim is based on this failed setup. Source constraint settles the doubt; no further probe or covered-suite rerun warranted.

Fresh read-only `sha256sum` comparison also confirms both committed DejaVu faces exactly match the installed unmodified assets: regular `ae7b7855e115a5966d8b1b3f80f254ccc117ec86f9965e202ee2940453837280`, bold `5c1247acef7f2b8522a31742c76d6adcb5569bacc0be7ceaa4dc39dd252ce895`.

Fresh read-only verification command: `git diff 43f2faf6aa53ea478745249d8b22e958d2d39ef2 2ae076261e948196671083824350ef490d28efcb --check`, exit0. `git rev-parse HEAD`, `git status --short`, `git diff --name-only`, `git diff --cached --name-only` confirm exact HEAD, no staged/product changes and only pre-existing controller progress.md modified.

## Out-of-scope observations and activation limits

No unchanged source observation is promoted to a new whole-branch finding. Existing short handlers/page shell formatting and older adaptive-workflow trigger remain outside the named fixed defects; intended feature/PR check exists independently. Prior complete review's declined judgments remain limits, not waivers:

- Hosted platform: all five migrations remain pending; fresh customer-record/count/hash baseline and post-apply equality, actual Auth/JWT/PostgREST/RLS/ACL and advisor checks, compatible callers, real tenant/finance journeys, operational recovery and live workload/queue behavior are unproved. Local PostgreSQL shims do not establish hosted behavior.
- Publication/integration: exact final remote commit/PR/preview and HTTPS flows, observed required Actions check/branch protection, merge/domain/production activation remain controller-owned. No remote/ref/deployment action occurred in this review.
- Delivery: private VAPID pair/dispatcher/Resend destination authorization and configuration, verified sender/confirmed recipient/provider acknowledgment and inbox/bounce behavior, real scheduler timing/authorization and consenting physical iOS/Android subscription/click/expiry/key rotation are pending. Earlier automatic-review rejection of private VAPID storage is not bypassed; plain subject metadata is not configured delivery. No live mass alerts or real sends were performed.
- Physical/account integrations: mobile PDF viewer/download behavior, live Google OAuth/Calendar account/scopes, hosted private-photo Storage upload/sign/signature/cleanup, real registration/email confirmation and alphanumeric-CNPJ hosted journey remain unproved. Document entry is not identity verification.
- Universal exactly-once mutation delivery, actual bank/Pix settlement/tax/fiscal certification, live identity verification or automatic historical backfill and a new CRM/scheduling redesign are not newly inferred promises. Unknown historic values and ownership stay preserved.

## Final verdict and readiness

**Spec compliance: PASS for the scoped source corrections, with activation limits.** All I1–I8 are addressed by reviewed implementation and meaningful covering evidence. Binding privacy, tenant/role authority, independent sale/wage arithmetic, historical evidence, private-by-default work, document privacy, no fabricated relationship/attendance metrics, authorized notices/PDFs and non-destructive recovery remain intact in this fix diff. This is source/local correctness assessment, not live production proof.

**Code quality: PASS WITH CONCERNS.** No new Critical/Important/Minor breakage confirmed; M1–M5/M7–M8 addressed. M6 remains NOT ADDRESSED, explicitly deferred upstream and permitted as a nonblocking dependency follow-up; no warning suppression or vendor patch.

**Source review readiness: READY for controller integration, with M6 accepted as deferred.** No remaining scoped Important source blocker is established. **Actual merge/hosted activation: NOT YET PROVEN READY** until controller-owned exact-commit publication/required hosted checks and applicable hosted/physical gates are satisfied. Do not claim real delivery, live schema/privacy journeys or physical PDF correctness from local evidence.

Review completed once, read-only, without subagents or external changes. Only this report was written; product/index/HEAD/branch and controller progress.md remained untouched.
