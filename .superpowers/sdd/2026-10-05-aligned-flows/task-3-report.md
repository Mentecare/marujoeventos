# Task 3 — aligned commercial/work interfaces

Status: completed locally on 2026-10-06 for controller review. BASE `e25e798947878bff10af8ce3c080385dad7bd5cc`. No hosted migration, publication/deployment, live Calendar/Storage/DB operation, external message or secret read was performed. Existing uncommitted Task3 work was preserved and completed rather than restarted. The implementation commit containing this report is the deliverable.

## Contracts and scope

Read the exact task brief, continuation, handoff, binding `docs/superpowers/specs/2026-10-05-aligned-flows.md`, and complete canonical Tasks1–2 API contract at `docs/superpowers/validation/2026-10-05-commercial-api.md`. Tasks1–2 backend definitions were not modified. Product code uses caller-session RPCs/DTOs; fixtures remain under tests.

- Retained the existing white/green shell, desktop navigation, five business mobile tabs, account menu, existing event detail view replacing the event list/creation form, six authorized detail panes, profile/portfolio gallery, staff Google controls, and legacy event access.
- Registration/profile use one CPF ou CNPJ field with inferred type, numeric/alphanumeric CNPJ validation, CPF permitted, CNPJ/MEI recommendation, private/masked identification and no verified badge. Business setup explicitly distinguishes provider from agency/scenography buyer. Undocumented unclassified historic admin retains historical operations/finance and can configure a new business without updating old event ownership.
- Buyer discovery/request → submitted sale-only quote → acceptance → own contract/charge/receipt/status → completion confirmation/review is reachable in existing tabs. Provider requests, editable draft lines/real sale totals, failure-retained drafts, submission, external acceptance evidence and customer receipt forms use commercial adapters. Owner finance-member authorization is reachable from Meu perfil.
- Work creation selects source, external owned client or accepted contract; quantities/days/hours/basis/rate/conditions/publication remain creation-only. Initial private publication and independent sale/remuneration are retained. Selected base/habitual workers are invited explicitly, candidature hiring creates invitations, worker accepts exact remuneration/availability and records own attendance. Payroll reads accepted-term DTOs and untouched legacy totals, never multiplies old totals by days or uses legacy agreement as an accepted new revision.
- Provider base, reusable teams, actual allocations and real histories are separate. Histories consume backend evidence/order/counts without an end_at-only client filter, invented stars, punctuality or past-hire claims. Completion/review calls remain authoritative server checks.
- Finance uses authorized operations/remuneration/work-finance DTOs and own worker DTOs. Buyer receives sale/limited delivery values only. Coordinator without explicit finance gets no finance pane, monetary operations output or financial RPC. Contracted/received/receivable and contracted/paid/payable are independent; unknown amounts stay unknown; result copy states estimated before unresolved expenses/taxes. Removed the invalid raw freelancer ownership rebinding action.
- Mutations use a synchronous lock in shared workflow hook; creation has its own submission lock. Receipt/expense payment keys persist across retries; forms retain drafts on domain failure. Loading/error/empty feedback and labelled HTML controls remain reachable.

## Files

Modified: `app/page.tsx`, `app/globals.css`, `lib/capabilities.ts`, `app/components/event-creation.tsx`, `app/components/event-finance.tsx`, `app/components/profile-photos.tsx`, `tests/finance-ui.test.mjs`.

Added: `app/components/business-setup.tsx`, `commercial-workspace.tsx`, `provider-people.tsx`, `relationship-history.tsx`, `work-detail.tsx`, `work-finance.tsx`, `worker-work.tsx`, `workflow-ui.tsx`; `lib/work-presentation.ts`; `tests/aligned-flows.browser.mjs`, `tests/work-presentation.test.mjs`, `tests/workflow-ui.test.mjs`; this report. Component names in the added list are under `app/components/` unless otherwise stated.

## Continuation findings and corrections

The truncated-browser problem was already repaired before this continuation. Actual `file /workspace/scratch/0d27d86074e8/eventcore-browser-runtime/chromium` output:

```text
ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=64d21de483d659a760a54ed98da9b0be77ce9a8b, stripped
```

Actual Chromium launched; no browser-runtime patch was needed. Each browser run launches Next and Chromium in the same Node driver on a random application port and blocks service workers.

Self-review corrected these concrete UI permission/consent issues with tests:

1. Owner-only provider base/team mutation controls incorrectly used can_operate. Coordinator browser red: `Only owner can change provider base`, actual1 versus expected0. Controls now use is_owner; final coordinator browser passes.
2. Publication requires the canonical identified provider/operator/finance permission. Coordinator browser red: `Coordinator without finance cannot publish`, actual1 versus expected0. Publication now uses operations.can_hire plus the existing identity/open checks; final coordinator browser passes.
3. Commercial finance members can quote without operations management. Real-component red: `Quote editor must follow canonical finance permission`; now follows can_finance. Tests pass.
4. Unknown expenses incorrectly offered settlement, although canonical settlement requires a known contracted amount. Real-component red showed the forbidden settlement button on null; now only known unpaid amounts offer settlement. Tests pass.
5. Pending revised conditions showed only the new total alongside the old accepted benefits. Real-component red: `The pending offer must disclose benefits and deductions before consent`; worker UI now displays the full offered rate/basis/days/hours/benefits/additions/deductions alongside the accepted conditions. The final unit/type/build run was repeated because this was a subsequent actual product correction, not to repeat already-passing unchanged checks.

Browser fixture corrections, with observed causes (no product behavior was replaced to satisfy fixtures):

- First run reached buyer mutations then timed out expecting a photo button/modal. Existing approved gallery uses an `Ampliar: Trabalho real` anchor with `_blank`; fixture now verifies that actual gallery contract.
- Provider invitation timed out on exact `getByLabel('Função')`: diagnostic DOM contained the full invite form and selected worker, while the wrapped select's label includes its option text. Fixture now selects its named service control.
- Worker assertion initially saw the accepted R$440 while waiting on the success notice for accepting R$460: the notice is set before DTO refresh. Fixture now waits on the actual refreshed accepted payable before asserting.
- Legacy setup notice disappears when new organization context changes the BusinessSetup React key; the saved masked identity remains visible. Fixture now waits for `Identificação privada CPF · final 4725.` and asserts that no raw old-event PATCH occurred.
- One exploratory Next dev run timed out because `<nextjs-portal>` intercepted mobile clicks. It is not claimed as passing evidence. Final browser evidence uses the actual optimized production build and has no page errors.
- First attempt to load new render tests needed a missing alias mapping for the real profile-photos helper; after fixing test module loading, actual production assertions failed as described above before product corrections.

## Actual browser journeys and evidence

`node tests/aligned-flows.browser.mjs` final exit0: 15 journeys, buyer/provider/worker/coordinator/legacy each at360/390/1280px. Every sidebar route is reached using the real mobile/account/desktop controls:102 route/viewport combinations. Geometry checks assert no document horizontal overflow, white header, preserved light-green background and visible mobile navigation. Provider verifies all six detail panes and creation-only absence of function edit fields; coordinator gets five panes without finance. All scenarios assert no browser page errors and caller bearer token on product RPC transport. The fixture rejects unexpected broad raw tables/RPCs.

| Actor | Actual UI path and browser assertions |
|---|---|
| Buyer | Clientes → provider selection/request → authorized provider presentation/portfolio → sent quote acceptance → contract tracking → buyer completion confirmation/review. No workforce finance or event creation calls. |
| Provider | Clientes → edit draft → injected save failure retains title → successful save/submission → receipt; Equipe → reusable team creation/history unknown metrics; Eventos → external WhatsApp work with10×2×R$220 remuneration=R$440 per worker, private default → six detail panes → select habitual workers/send specific invites → professional gallery → candidature hiring → offered revision leaves accepted R$440 unchanged → actual payment RPC; Meu perfil → owner finance-member permission. |
| Worker | Minha escala → accept revision2 → actual refreshed accepted R$460 → confirm invitation → geolocated check-in/check-out; Eventos → sanitized date07/10/2026/public function/region preview with no private name/address/briefing/requirements → apply. Full offered and accepted conditions covered additionally by actual component rendering. |
| Coordinator | Equipe → owner mutations absent; Início → historic authorized detail → no publication/no finance button/no money/no remuneration, work-finance or commercial-workspace RPC. Operational shell/history remains reachable. |
| Legacy undocumented admin | Início → old event detail/payment history → contracted historical sale, unknown received/receivable → back to events → new business complement → allowed CPF/provider → saved masked identity; no assigning/reclassifying the old event through raw update. |

Scratch evidence: `/workspace/scratch/0d27d86074e8/eventcore-task3-evidence/results.json`, `browser.log`, `unit.log`, `typecheck.log`, `build.log`. Screenshots use `${role}-${width}.png` for profile/gallery, plus `buyer-${width}-commercial.png`, `provider-${width}-work-finance.png`, `worker-${width}-own-work.png`, `worker-${width}-public-opportunities.png`, `coordinator-${width}-operations-without-finance.png`, `legacy-${width}-historical-finance.png`. These are local execution artifacts; the committed driver and report are reproducible evidence. Provider390 financial screenshot was visually inspected; its split numeric values were then corrected through the focused layout verification recorded below. The general15-journey evidence precedes that typography-only correction; affected surfaces were rerun afterward.

### Full final browser command/output

```text
$ node tests/aligned-flows.browser.mjs
{"role":"buyer","width":360,"routes":7,"mutations":["create_contract_request","accept_sale_quote","confirm_contract_completion","submit_provider_rating"],"status":"PASS"}
{"role":"buyer","width":390,"routes":7,"mutations":["create_contract_request","accept_sale_quote","confirm_contract_completion","submit_provider_rating"],"status":"PASS"}
{"role":"buyer","width":1280,"routes":7,"mutations":["create_contract_request","accept_sale_quote","confirm_contract_completion","submit_provider_rating"],"status":"PASS"}
{"role":"provider","width":360,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
{"role":"provider","width":390,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
{"role":"provider","width":1280,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
{"role":"worker","width":360,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
{"role":"worker","width":390,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
{"role":"worker","width":1280,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
{"role":"coordinator","width":360,"routes":6,"mutations":[],"status":"PASS"}
{"role":"coordinator","width":390,"routes":6,"mutations":[],"status":"PASS"}
{"role":"coordinator","width":1280,"routes":6,"mutations":[],"status":"PASS"}
{"role":"legacy","width":360,"routes":7,"mutations":["configure_business_identity"],"status":"PASS"}
{"role":"legacy","width":390,"routes":7,"mutations":["configure_business_identity"],"status":"PASS"}
{"role":"legacy","width":1280,"routes":7,"mutations":["configure_business_identity"],"status":"PASS"}
PASS: 15 role/viewport journeys

exit_code=0
```

## Actual checks

Focused command (after permission fixes, before the last full offered-conditions correction):

```text
node --experimental-strip-types --test tests/workflow-ui.test.mjs tests/work-presentation.test.mjs tests/event-creation.test.mjs tests/commercial.test.mjs tests/finance-ui.test.mjs tests/profile-portfolio.test.mjs tests/google-sync.test.mjs
ℹ tests 30
ℹ suites 0
ℹ pass 30
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 742.826257
exit_code=0
```

The targeted last correction command and actual output:

```text
node --experimental-strip-types --test tests/workflow-ui.test.mjs
✔ explicit finance members can prepare commercial quotes without an operations role (227.560847ms)
✔ unknown contracted expense does not offer a settlement that requires a known amount (20.55996ms)
✔ workers see each offered change before accepting a revision alongside the accepted conditions (15.299985ms)
ℹ tests 3
ℹ suites 0
ℹ pass 3
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 676.131083
exit_code=0
```

Actual HTTP integration (real Next production route and Sharp; only external Auth/PostgREST/Storage boundaries stubbed):

```text
node tests/profile-photos.integration.mjs
profile_photo_cleanup_deferred
profile_photo_cleanup_deferred
PASS: real Next API and Sharp; auth, declaration, invalid/large files, normalization, avatar replacement, quota/cleanup, deletion retry/idempotency, owner isolation, contractor gallery and private signing
exit_code=0
```

Those two cleanup lines are deliberately injected storage-cleanup failures exercised by the integration, not live storage warnings. Last product correction touched worker condition presentation only; photo integration was not repeated needlessly.

The final full suite, typecheck and optimized build below are fresh actual commands/results after the last logic change (full offered conditions). The subsequent scoped currency layout correction and its affected checks are recorded below. Obsolete npm_config_http_proxy/NPM_CONFIG_HTTP_PROXY were omitted as the Task2 handoff directs; valid proxy settings were retained. Public build variables are test fixture values, not live secrets. No prior implementation prose was treated as a pass.

### Full final unit command/output

```text
$ env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm test

> eventcore@1.0.0 test
> node --experimental-strip-types --test tests/*.test.mjs

✔ unified document input infers CPF and both CNPJ formats without claiming verification (2.170408ms)
✔ invalid documents and punctuation cannot be silently normalized into a valid identity (0.288012ms)
✔ sale line totals use quantity and days once, independent of worker remuneration (9.233459ms)
✔ sale totals reject overflow and bounds while preserving zero and cent precision (0.418778ms)
✔ commercial adapter preserves caller client and canonical revision/evidence/receipt arguments (1.407362ms)
✔ server actor rejects missing/empty caller JWT before database access (44.966862ms)
✔ daily remuneration uses cent-safe per-worker totals independently from sale pricing (1.671199ms)
✔ workflow adapter uses stable revision/completion/base/team/finance DTO endpoints (1.065549ms)
✔ workflow caller carries built creation conditions and retained candidature/attendance arguments unchanged (8.172557ms)
✔ freelancer and incomplete business accounts cannot open client or team management (1.939291ms)
✔ all completed business profiles retain clients/events while Google stays staff-only (0.280791ms)
✔ profile editing selects the first active owned organization regardless of the operational selection (7.820248ms)
✔ private identity checks reject forged check digits and support numeric and alphabetic CNPJ (0.882906ms)
✔ earnings use paid records and separate future confirmed income without invitations/cancellations (14.958432ms)
✔ empty dashboards show absent averages/rates rather than invented performance (8.84152ms)
✔ event creation includes all requested functions and preserves absent versus zero costs (7.185374ms)
✔ each function defaults to one day when omitted and preserves the supplied financial amount (0.485309ms)
✔ invalid day counts reject the entire event with the affected function identified (3.197469ms)
✔ removed draft functions are excluded and an event can be created without functions (0.337967ms)
✔ an invalid function prevents any creation payload from being submitted (2.436697ms)
✔ event creation rejects missing details and invalid date ranges before requesting a save (0.785679ms)
✔ new daily conditions, origin and provider context are passed separately from legacy total costs (0.728123ms)
✔ unavailable and refreshing revenue do not claim zero receipts (11.794683ms)
✔ loaded revenue offers gross/net cards and two date fields capped at today (6.257802ms)
✔ the missing contracted cost form requires an explicit value rather than defaulting to zero (2.306282ms)
✔ the default revenue period runs from the first day of the current Brazilian month through today (2.269887ms)
✔ periods accept historical ranges but reject future dates, reversed ranges and impossible dates (0.662655ms)
✔ net revenue deducts recorded obligations, extras and deductions once, using the event date (0.921933ms)
✔ empty periods show zero while unpriced events are excluded and clearly reported as incomplete (0.435764ms)
✔ zero is a real recorded price and negative net revenue is preserved (0.431297ms)
✔ unpaid reserves are excluded, while a real paid reserve still counts as a cost (0.272959ms)
✔ a missing contracted cost keeps net revenue unknown instead of inventing profit (0.337086ms)
✔ legacy contracted gross exposes no fabricated receipt and labels the result as estimated (0.231768ms)
✔ an incomplete contracted-sale period keeps the canonical estimated result unknown (0.300601ms)
✔ Google sync rejects unrelated staff before privileged reads, token lookup, export or state update (7.155811ms)
✔ Google sync fails closed for missing permission rows, permission failures and mismatched verified actors (1.377298ms)
✔ authorized staff operator retains create/update Calendar behavior without requiring finance (4.075582ms)
✔ real image decoding normalizes accepted formats and preserves orientation without metadata (22.947723ms)
✔ uploaded photos are bounded and MIME labels cannot substitute for valid bytes (700.546047ms)
✔ a real-photo declaration is required for avatar and portfolio, with bounded captions (1.298639ms)
✔ actual multipart stream is capped before parsing, even without Content-Length (11.243647ms)
✔ provider portfolio signs only paths from the caller-authorized provider RPC (1.850808ms)
✔ provider portfolio authorization rejection happens before privileged storage signing (0.781593ms)
✔ photo GET supports provider organizations and rejects ambiguous or invalid targets (36.820856ms)
✔ presentation preserves historic totals and ignores unaccepted revised payable amounts (0.857727ms)
✔ generic staff and business labels do not authorize finance; explicit canonical organization grants do (0.295393ms)
✔ ended, completed and cancelled work suppress remuneration revisions (0.214943ms)
✔ explicit finance members can prepare commercial quotes without an operations role (222.385798ms)
✔ unknown contracted expense does not offer a settlement that requires a known amount (14.889388ms)
✔ workers see each offered change before accepting a revision alongside the accepted conditions (14.628387ms)
ℹ tests 50
ℹ suites 0
ℹ pass 50
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 977.600675

exit_code=0
```

### Full final typecheck command/output

```text
$ env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm run typecheck

> eventcore@1.0.0 typecheck
> tsc --noEmit


exit_code=0
```

### Full final build command/output

```text
$ env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview-publishable-key NEXT_TELEMETRY_DISABLED=1 npm run build

> eventcore@1.0.0 build
> next build

   ▲ Next.js 15.5.27

   Creating an optimized production build ...
 ✓ Compiled successfully in 2.9s
   Linting and checking validity of types ...
   Collecting page data ...
   Generating static pages (0/8) ...
   Generating static pages (2/8)
   Generating static pages (4/8)
   Generating static pages (6/8)
 ✓ Generating static pages (8/8)
   Finalizing page optimization ...
   Collecting build traces ...

Route (app)                                 Size  First Load JS
┌ ○ /                                    94.9 kB         198 kB
├ ○ /_not-found                            992 B         104 kB
├ ƒ /api/google/callback                   138 B         103 kB
├ ƒ /api/google/connect                    138 B         103 kB
├ ƒ /api/google/disconnect                 138 B         103 kB
├ ƒ /api/google/sync                       138 B         103 kB
├ ƒ /api/profile/photos                    138 B         103 kB
└ ƒ /api/specialties                       138 B         103 kB
+ First Load JS shared by all             103 kB
  ├ chunks/255-ce8c7c75002f810b.js       46.5 kB
  ├ chunks/4bd1b696-c023c6e3521b1417.js  54.2 kB
  └ other shared chunks (total)           1.9 kB


○  (Static)   prerendered as static content
ƒ  (Dynamic)  server-rendered on demand


exit_code=0
```

## Self-review, caveats and recovery

Self-review covered the binding task checklist, diff/permission paths, no broad raw workforce-finance reads in new flows, immutable accepted remuneration versus offers/legacy totals, no linked-worker identity rebinding, historical-null-day labels, backend evidence history consumption, public date-only/privacy display, owner/team permission, coordinator finance absence, creation-only controls, live product RPC adapters and preserved photos/Google handler tests. The full suite includes the three real Google-handler cases for fail-closed unrelated staff, denied/mismatched actor and authorized operational Calendar create/update behavior without finance. Browser exercises the preserved staff Google control surface but does not call live OAuth or Calendar. There is no Task3 schema change and no hosted ACL/DDL proof is claimed here.

No blocking local check remains. External hosted Supabase/RLS/auth/Calendar/Storage, migrated real records, email/notification delivery and publication require controller homologation; these local browser tests stub external boundaries and therefore do not prove live credentials, hosted migration/application or external delivery. Task4 PDF/sharing/notification delivery is outside this Task3 interface scope. Completion/review mutation endpoints remain the final evidence/uniqueness authority; the current operational DTO does not expose an assignment-specific review-eligibility flag, so a completed checked-out row can still surface a review form whose submission the backend rejects if validation/evidence is missing. No review stars or completion is invented by the UI. Finance-member authorization accepts an active member's profile UUID rather than providing a member picker, and server validates membership. API timeouts before an acknowledged non-idempotent mutation response still require checking authoritative refreshed records before retry; this UI does not claim exactly-once network delivery.

Recovery is source/UI-only here: retain the compatible canonical context/DTO adapters and historic access; hide new mutation controls while investigating, or revert this implementation only together with a controller-reviewed compatible UI/backend recovery. Do not run the previous broad-finance/raw amount-edit/identity-rebinding UI against the strengthened Task1–2 backend. Preserve accepted quotes/contracts, append-only terms/acceptances/payments/completions/reviews, existing documents and all tighter ownership/tenant/finance policies. Follow Task1–2 additive recovery instructions for any backend rollback; do not drop evidence, recalculate historical totals, disable guards or restore generic staff financial/identity bypasses. No recovery action was executed.

Final `git diff --cached --check` is run after staging this report; implementation commit and clean status are returned to the controller. Browser/runtime/server processes are closed by driver finally blocks. Report/check logs contain only fixture data and explicit test build values.

## Controller-requested focused currency layout correction

After inspection of the actual provider390 screenshot, controller requested correcting numbers split inside financial metric cards. A browser Range assertion measures each numeric substring's rendered line rectangles, rather than checking source CSS or inferring readability from document overflow. Red command `EVENTCORE_CHECK_ROLE=provider EVENTCORE_CHECK_WIDTH=390 node tests/aligned-flows.browser.mjs` failed with `BRL numeric values must stay on one line`; actual split amounts included R$5.600,00, R$440,00, R$0,00 and R$5.160,00, expected none.

The correction is scoped to the new `workFinanceMetrics` grid: one column below600px, readable font size, nowrap on its currency values, and the existing approved `currencyValue` typography. Palette, shell/navigation, other metrics, data and calculations remain intact. First focused run passed360/390 then revealed pre-existing split decimals at1280; the existing currencyValue typography plus scoped nowrap resolved those too. No unrelated functionality was added.

Current optimized build (including lint/type validation) passed. Affected actual provider journeys passed360/390/1280 with every monetary numeric substring on one rendered line and no document horizontal overflow. The affected legacy360 finance surface, including unknown historical receipt values, also passed navigation/geometry/history preservation. The refreshed390 screenshot was visually inspected and shows intact R$5.600,00, R$440,00 and R$5.160,00. The50-test full suite/typecheck above follows the last logic change; these additional checks cover the subsequent presentation-only correction without repeating unchanged unit/HTTP suites.

Corrected evidence paths: `/workspace/scratch/0d27d86074e8/eventcore-task3-evidence/currency-provider/provider-390-work-finance.png`, corresponding360/1280 screenshots and provider `results.json`; `/workspace/scratch/0d27d86074e8/eventcore-task3-evidence/currency-legacy/legacy-360-historical-finance.png` and legacy `results.json`. Root `results.json` retains the earlier complete15-journey matrix. Current commands/outputs:

```text
$ env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview-publishable-key NEXT_TELEMETRY_DISABLED=1 npm run build

> eventcore@1.0.0 build
> next build

   ▲ Next.js 15.5.27

   Creating an optimized production build ...
 ✓ Compiled successfully in 2.7s
   Linting and checking validity of types ...
   Collecting page data ...
   Generating static pages (0/8) ...
   Generating static pages (2/8)
   Generating static pages (4/8)
   Generating static pages (6/8)
 ✓ Generating static pages (8/8)
   Finalizing page optimization ...
   Collecting build traces ...

Route (app)                                 Size  First Load JS
┌ ○ /                                    94.9 kB         198 kB
├ ○ /_not-found                            992 B         104 kB
├ ƒ /api/google/callback                   138 B         103 kB
├ ƒ /api/google/connect                    138 B         103 kB
├ ƒ /api/google/disconnect                 138 B         103 kB
├ ƒ /api/google/sync                       138 B         103 kB
├ ƒ /api/profile/photos                    138 B         103 kB
└ ƒ /api/specialties                       138 B         103 kB
+ First Load JS shared by all             103 kB
  ├ chunks/255-ce8c7c75002f810b.js       46.5 kB
  ├ chunks/4bd1b696-c023c6e3521b1417.js  54.2 kB
  └ other shared chunks (total)           1.9 kB


○  (Static)   prerendered as static content
ƒ  (Dynamic)  server-rendered on demand


exit_code=0
```

```text
$ env EVENTCORE_CHECK_ROLE=provider EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-evidence/currency-provider node tests/aligned-flows.browser.mjs
{"role":"provider","width":360,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
{"role":"provider","width":390,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
{"role":"provider","width":1280,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
PASS: 3 role/viewport journeys

exit_code=0
$ env EVENTCORE_CHECK_ROLE=legacy EVENTCORE_CHECK_WIDTH=360 EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-evidence/currency-legacy node tests/aligned-flows.browser.mjs
{"role":"legacy","width":360,"routes":7,"mutations":["configure_business_identity"],"status":"PASS"}
PASS: 1 role/viewport journeys

exit_code=0
```

Embedded terminal output has trailing line-ending whitespace removed so the report passes diff whitespace checks; raw scratch logs retain the original bytes. Initial staged report check identified only the Next progress-line trailing spaces copied into the report; those formatting spaces were removed. Final staged whitespace check is run again before commit; no product change was made for that report-only warning.


## Task 3 fix round 1 — three Important review findings (2026-10-06)

Correction base `1a5ab867618c54bf02760f1d4177c2258c80af37`; finished Task3 work is retained. Read the task brief, binding global constraints, handoff, actual report, three Important findings in the review and exact canonical API/SQL. This correction addresses only: **Draft edits erase stored date, location, and item hours**; **Finance permission cannot independently unlock the work-finance interface**; **Worker dashboard counts are always zero**. The three Minor findings remain deferred to controller final triage. No subagents, hosted DDL/migration/deploy, Calendar calls, external messages or secret reads occurred.

### Changes and contract

- QuoteEditor copies each stored `planned_hours` into editable line state and supplies stored `event_date`/`venue` explicitly on save. Existing sale calculations and accepted quote behavior remain unchanged; a title-only edit cannot erase those metadata values. New lines explicitly carry unknown hours as NULL. The browser quote starts with non-null date/location/hours and models replacement (omitted fields become NULL), rather than merging omitted properties. It asserts all three values survive the failed-save/retry/title-only save.
- Pinned official CLI 2.119.0: read `supabase migration --help` and `supabase migration new --help`, then ran `/workspace/scratch/0d27d86074e8/eventcore-cli-tools/node_modules/.bin/supabase migration new eventcore_work_finance_index`. Actual CLI result: `Migration created`, path `supabase/migrations/20261006203715_eventcore_work_finance_index.sql`, chronologically after existing dependencies. No login/link or product dependency changes.
- New read-only `get_work_finance_index()` uses unchanged canonical `private.eventcore_can_finance_event`, returning exactly `{event_id,event_name,organization_id}[]`, ordered by stored start then ID. It exposes no operational address/schedule/personnel or financial values. Authenticated EXECUTE only; PUBLIC/anon revoked. Typed `WorkFinanceIndex` and caller-session `workflowApi(db).financeIndex()` are documented in the SAME canonical API document. Existing event RLS, operations RPC, ownership and financial meaning are untouched.
- The page discovers finance work through that index independently from operations, reads existing `get_work_finance` for authorized IDs, and scopes finance panels by the selected organization. Legacy NULL-organization creator finance stays reachable. Event remuneration remains restricted to already-accessible finance-authorized operations. Finance-only browser fixture has `can_finance=true, can_operate=false, is_owner=false`, no raw events/clients/applications, and asserts index/finance transport plus no operations/remuneration RPC.
- Worker dashboard uses only its own authorized assignment DTO: distinct active invited/confirmed/checked-in work, distinct completed work explicitly confirmed by that worker (and eligible assignment status), and actual own paid-payment amounts. Labels explain the completion evidence; unchecked completion, reserve/cancelled/no-show and provider event counters do not inflate results. Units assert duplicates/exclusions/unknown absence/empty state; the real page asserts 1 active, 1 confirmed completed, R$440 received, then 0 active after check-out with completed/received unchanged. Backend attendance/reputation semantics are not recreated or changed.

### RED evidence before product correction

Focused units command:
`node --experimental-strip-types --test tests/workflow-ui.test.mjs tests/work-presentation.test.mjs`

Actual expected failures:
```text
SyntaxError: The requested module '../lib/work-presentation.ts' does not provide an export named 'workerDashboardMetrics'
TypeError: api.financeIndex is not a function
ℹ tests 5
ℹ pass 3
ℹ fail 2
```

Each browser RED used the existing production build and the new boundary regression before product edits:
`EVENTCORE_CHECK_ROLE=<provider|worker|finance> EVENTCORE_CHECK_WIDTH=390 EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/red-<role> node tests/aligned-flows.browser.mjs`

Actual output excerpts (Node failed):
```text
provider: AssertionError [ERR_ASSERTION]: Title edit preserves event date
+ null
- '2099-10-07'
worker: locator.innerText: Timeout 30000ms exceeded.
  waiting for locator('.metric').filter({ has: getByText('Trabalhos ativos', { exact: true }) }).locator('strong')
finance: locator.waitFor: Timeout 30000ms exceeded.
  waiting for getByText('Venda contratada', { exact: true }) to be visible
```
The worker lacked worker-specific indicators and rendered provider zeros; the finance-only page lacked any financial work. The quote fixture now detects actual NULL replacement.

SQL RED command:
`node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs "$PWD" tests/interface-finance-security.sql`

Actual output:
```text
Migration chain passed: 31 files; engine: PostgreSQL 17.5 on aarch64-unknown-linux-gnu
FIXTURE FAILED tests/interface-finance-security.sql function public.get_work_finance_index() does not exist code=42883
```

### GREEN commands and actual output

`node --experimental-strip-types --test tests/workflow-ui.test.mjs tests/work-presentation.test.mjs`:
```text
✔ presentation preserves historic totals and ignores unaccepted revised payable amounts (0.765518ms)
✔ generic staff and business labels do not authorize finance; explicit canonical organization grants do (0.288996ms)
✔ ended, completed and cancelled work suppress remuneration revisions (0.147097ms)
✔ worker dashboard uses own distinct work, confirmed completion and paid evidence (0.848981ms)
✔ explicit finance members can prepare commercial quotes without an operations role (185.69169ms)
✔ unknown contracted expense does not offer a settlement that requires a known amount (13.832551ms)
✔ workers see each offered change before accepting a revision alongside the accepted conditions (18.085217ms)
✔ finance discovery adapter uses the caller RPC independently from event operations (1.498247ms)
ℹ tests 8
ℹ suites 0
ℹ pass 8
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 548.069492
```

`env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm test` (full unit suite):
```text
✔ workers see each offered change before accepting a revision alongside the accepted conditions (20.266497ms)
✔ finance discovery adapter uses the caller RPC independently from event operations (1.408365ms)
ℹ tests 52
ℹ suites 0
ℹ pass 52
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1093.496738
```

`env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm run typecheck`:
```text
> eventcore@1.0.0 typecheck
> tsc --noEmit
```
Typecheck passed. Initial build omitted required public preview environment and failed prerender with `Error: supabaseUrl is required.` This was an execution setup failure; no product patch was made for it. Re-ran the report's documented public test-fixture command:
`env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview-publishable-key NEXT_TELEMETRY_DISABLED=1 npm run build`

Actual passing production build output:
```text
> eventcore@1.0.0 build
> next build

   ▲ Next.js 15.5.27

   Creating an optimized production build ...
 ✓ Compiled successfully in 4.5s
   Linting and checking validity of types ...
   Collecting page data ...
   Generating static pages (0/8) ...
   Generating static pages (2/8)
   Generating static pages (4/8)
   Generating static pages (6/8)
 ✓ Generating static pages (8/8)
```
Production Next from that build served all final browser journeys.

`node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs "$PWD" tests/interface-finance-security.sql`:
```text
Migration chain passed: 32 files; engine: PostgreSQL 17.5 on aarch64-unknown-linux-gnu, compiled by emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 3.1.74 (1092ec30a3fb1d46b1782ff1b4db5094d3d06ae5), 32-bit
FIXTURE PASSED tests/interface-finance-security.sql statements=58
Disposable SQL validation complete; no hosted database was changed.
```
Actual PostgreSQL 17.5 applies all 32 migrations. All 58 fixture statements roll back. Coverage includes exact minimal index projection/tenant scope, independent finance allow, unchanged raw events RLS and denied operations, denied operations-only finance, unrelated provider isolation, buyer exclusion, undocumented legacy creator and unchanged historical amount/unknown receipts, revoked/inactive member/actor/organization, anon ACL and unchanged unowned history.

Final scoped browser commands:
```text
EVENTCORE_CHECK_ROLE=worker EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/green-worker-final node tests/aligned-flows.browser.mjs
EVENTCORE_CHECK_ROLE=finance EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/green-finance-final node tests/aligned-flows.browser.mjs
EVENTCORE_CHECK_ROLE=provider EVENTCORE_CHECK_WIDTH=390 EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/green-provider-final node tests/aligned-flows.browser.mjs
EVENTCORE_CHECK_ROLE=coordinator EVENTCORE_CHECK_WIDTH=390 EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/green-coordinator node tests/aligned-flows.browser.mjs
EVENTCORE_CHECK_ROLE=legacy EVENTCORE_CHECK_WIDTH=390 EVENTCORE_BROWSER_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence/green-legacy node tests/aligned-flows.browser.mjs
```
Actual passing outputs:
```text
{"role":"worker","width":360,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
{"role":"worker","width":390,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
{"role":"worker","width":1280,"routes":7,"mutations":["accept_assignment_terms","respond_to_assignment","record_assignment_attendance","record_assignment_attendance","apply_for_opportunity"],"status":"PASS"}
PASS: 3 role/viewport journeys
{"role":"finance","width":360,"routes":7,"mutations":[],"status":"PASS"}
{"role":"finance","width":390,"routes":7,"mutations":[],"status":"PASS"}
{"role":"finance","width":1280,"routes":7,"mutations":[],"status":"PASS"}
PASS: 3 role/viewport journeys
{"role":"provider","width":390,"routes":7,"mutations":["save_sale_quote","save_sale_quote","submit_sale_quote","record_customer_receipt","save_provider_team","create_event_with_services","invite_selected_workers","hire_application","propose_assignment_terms","mark_assignment_paid","set_organization_finance_member"],"status":"PASS"}
PASS: 1 role/viewport journeys
{"role":"coordinator","width":390,"routes":6,"mutations":[],"status":"PASS"}
PASS: 1 role/viewport journeys
{"role":"legacy","width":390,"routes":7,"mutations":["configure_business_identity"],"status":"PASS"}
PASS: 1 role/viewport journeys
```
Final evidence: 9 affected role/viewport journeys, all no page errors, caller bearer transport, preserved shell/navigation and no horizontal overflow; worker/finance at360/390/1280, provider/coordinator/legacy at390. The browser's default roles now include finance so future full runs exercise the regression. No unchanged full Calendar/photo integration matrix was rerun.

The first worker GREEN attempt reached/passed new dashboard assertions but an old unscoped amount locator found three rows: newly added past/cancelled fixtures were being rebuilt from the mutable active-worker record after acceptance. Corrected test-only fixtures to stable past/cancelled DTOs and genuinely past completed schedule dates; product did not change to accommodate this. The final three-width worker run above passes both before and after check-out metric assertions.

### Self-review, files and recovery

Read the full correction diff and new SQL fixture, checked `git diff --check` (clean), and applied the React component checklist (caller auth boundary, dependent ID discovery before finance read, parallel independent reads, derived indicators, stable React keys, existing accessible controls, no new CSS/dependency shell). Visually inspected worker390 dashboard and independent-finance390 screenshots: metrics and BRL amounts are readable in the approved shell. No additional product defect was found within the authorized Important scope. Existing large/compressed JSX and review-control eligibility remain deferred Minor work.

Changed files: `app/components/commercial-workspace.tsx`, `app/page.tsx`, `lib/commercial.ts`, `lib/work-presentation.ts`, `tests/workflow-ui.test.mjs`, `tests/work-presentation.test.mjs`, `tests/aligned-flows.browser.mjs`, new `tests/interface-finance-security.sql`, new `supabase/migrations/20261006203715_eventcore_work_finance_index.sql`, the canonical API document, and this same report. Evidence logs/results/screenshots remain under `/workspace/scratch/0d27d86074e8/eventcore-task3-fix1-evidence`.

Recovery: disable dependent index-based finance UI, then revoke authenticated EXECUTE on `get_work_finance_index()`. Keep every existing row/helper/ACL/RLS and historical/append-only financial evidence. A reviewed additive recovery migration can drop the read-only index only after callers stop using it. No ownership restoration or recalculation is needed because this migration writes no data.

Pending external proof: controller must apply the additive migration before activating the new page contract and validate actual hosted JWT/PostgREST/ACL/RLS for independent member finance. Disposable PG shims and browser boundary stubs do not prove hosted activation. Existing live auth, Storage/Calendar, delivery/publication and exactly-once transport gates from the original report remain unchanged. No hosted operation or external delivery is claimed.
