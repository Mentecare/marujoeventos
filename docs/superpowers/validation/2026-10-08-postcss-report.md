# Task2 — PostCSS incremental security patch

Status 2026-10-08: complete locally; dependency patch, focused GREEN, build/typecheck/trace, mobile journeys and full suite verified. Commit `1f0eaba8846ba4f9e09f1c20d2c0a1a18c81adff`. Base `776adf46fc89c58479957f773cdbfc9a2205296b`. No framework upgrade, feature changes, SQL, credential reading or real service delivery.

## Cause and focused change

The baseline effective tree was `next@15.5.27 → postcss@8.4.31`, with React/React DOM19.1.9. `npm audit --json` returned two affected nodes (Next moderate transitively; PostCSS high) and four PostCSS advisories, offering Next16.4.0 major. The dependency resolved by Next's CSS build is `require('postcss')` from `next/dist/build/webpack/config/blocks/css/index.js`; its parser auto-loaded uncontrolled source map comments, and its AST stringifier preserved raw HTML style terminators.

Added only `overrides.next.postcss = "8.5.23"` and regenerated lock with npm. Lock diff changes the PostCSS package version, registry URL, integrity and its three dependency constraints; existing dependency versions satisfy the new constraints. Next/React/React DOM pins remain unchanged. Tests use `createRequire(require.resolve('next/package.json'))('postcss')`, exercising the dependency Next actually resolves, rather than asserting version/config text.

## Registry and sources

`npm view postcss@8.5.23 version dist.tarball dist.integrity engines --registry=https://registry.npmjs.org` succeeded: version8.5.23; official tarball `https://registry.npmjs.org/postcss/-/postcss-8.5.23.tgz`; integrity `sha512-g50586zr4bZmwFiTlflMu8E0bDTb5I5gertgwAKmsdUlTQIhZtunzUlD1WSzwcVWPoAVpsrA6vlfCD7oXvRwgg==`; engines `^10 || ^12 || >=14`. `npm pack` fetched that tarball for read-only inspection in `/tmp`; no installed vendor files were edited.

Primary sources opened 2026-10-08:

- https://github.com/postcss/postcss/security/advisories/GHSA-qx2v-qp2m-jg93 — stringify XSS, affected<8.5.10.
- https://github.com/postcss/postcss/security/advisories/GHSA-6g55-p6wh-862q — uncontrolled file loading/information leak, affected<=8.5.11.
- https://github.com/postcss/postcss/security/advisories/GHSA-r28c-9q8g-f849 — traversal map disclosure, affected<=8.5.17, patch8.5.18.
- https://github.com/postcss/postcss/security/advisories/GHSA-fxqj-rqcc-2cmp — no-from residual, affected<=8.5.22, patch8.5.23.
- https://github.com/postcss/postcss/releases/tag/8.5.23 — maintainer signed immutable release, July24.
- https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#overrides — parent-scoped overrides.

GitHub source file pages failed browser retrieval; official npm tarball inspection supplied the code evidence:8.5.23 `PreviousMap.loadFile` rejects non-map files, rejects untrusted external maps without cssFile, and rejects paths escaping dirname(cssFile); `Stringifier` escapes HTML in CSS. Trust bypass options are not enabled by our tests or app.

## RED/GREEN behavioral evidence

New `tests/postcss-security.test.mjs` uses only generated temporary files under `os.tmpdir()`, cleaned with `t.after`. No real secrets, filesystem targets, production endpoints, mocks of PostCSS or dependency-version assertions. Reverting PostCSS to the baseline should fail four security tests; breaking CSS/plugin/map compatibility should fail the three legitimate controls.

The initial test draft used an empty plugin list. On this installed PostCSS, explicit map generation took a fast path without carrying previous content, producing false-green security checks and failed legitimate controls. Inspected `NoWorkResult`/`MapGenerator`, corrected tests BEFORE changing dependency to run a real minimal PostCSS plugin (like Next's pipeline). This is test correction, not a workaround for the patch.

`node --test tests/postcss-security.test.mjs` baseline final RED:7 tests,3 pass,4 fail. Exact failures:

1. `Next CSS processing does not disclose a source map outside the from directory`: `outside source content was disclosed` from `../outside.map`.
2. `Next CSS processing ignores an absolute source map URI when from is unset`: `absolute source content was disclosed` from a synthetic absolute temporary `.map` path (`from: undefined`).
3. `Next CSS processing does not surface out-of-tree non-JSON file bytes`: unwanted rejection `Unexpected token 'S', "SYNTHETIC_"... is not valid JSON` from `../outside.txt`.
4. `CSS AST stringify cannot close an embedding HTML style element`: raw `</style><script>synthetic()</script><style>` remains in result.

Controls passed baseline: literal ordinary CSS declarations with actual plugin `color:red → blue`, an adjacent relative `.map`, and an inline data URI map without from.

Commands after RED: `npm install --package-lock-only --ignore-scripts --registry=https://registry.npmjs.org`, `npm ci`, `node --test tests/postcss-security.test.mjs`, `npm ls next react react-dom postcss`. All succeeded; clean install added77 packages; GREEN7/7,0 failures. Effective tree shows `next@15.5.27 → postcss@8.5.23 overridden`, React/React DOM19.1.9. Log paths: `/tmp/eventcore-task2-{lock,ci,red,green,tree}.log`; baseline audit `/tmp/eventcore-task2-audit-before.json`.

## Checks and warnings (pending completion)

Runtime Node24.19.0/npm11.9.0. npm emits existing `Unknown env config "http-proxy"` warning. Actual Next dotenv filenames `.env`, `.env.local`, `.env.production`, `.env.production.local` do not exist (existence checked only); build/runtime will receive synthetic environment values. No credentials were opened.

Preparation is in progress preserving existing reviewed CI order: `npm ci` → `npm install --no-save --package-lock=false playwright@1.62.1` → `npx playwright install --with-deps chromium` → build. Recheck effective PostCSS and GREEN after preparation before build. Typecheck/build/tracing, provider390/finance390, audit and final `npm test` will be appended. No SQL or broad unrelated browser rerun.

## Scope and limits

The focused prior scan found PostCSS used for globals.css build, no observed user CSS entry in app/lib. That limits exposure evidence, does not establish absence of exploitation. No claim of real secret disclosure, universal safety or remote hosted CI success. Official patch behavior for these fixtures has been confirmed; full checks are still pending. Existing controller plan/validation docs are excluded from staging/commit. Report is ignored scratch handoff per brief; implementation/test changes will be committed separately with exact hash appended.

## Checkpoint: final dependency preparation and audit

- Playwright install succeeded: `added 3 packages, removed 3 packages, and changed 3 packages in 22s`; dependency preparation happens before build, retaining the reviewed CI order.
- `npx playwright install --with-deps chromium` failed locally (exit1; installation subprocess100): container APT cannot `setgroups`/`setegid`/`seteuid`; no changes to workflow or privilege escalation.
- `npx playwright install chromium` without APT started download but failed with `End of central directory record signature not found`/invalid downloaded ZIP. Download process stopped with SIGINT/exit130 after controller confirmed the previously verified local browser. No further provisioning retries.
- Reused `/workspace/scratch/0d27d86074e8/eventcore-browser-runtime/chromium`,209022176 bytes, `Chromium 153.0.8010.0`; real `playwright.chromium.launch({executablePath,...})` succeeded, reported153.0.8010.0. Exact Playwright1.62.1/default bundled Chromium provisioning remains for hosted CI to prove; this environment uses the preexisting supported executablePath seam.
- Post-preparation `npm ls next react react-dom postcss`: Next15.5.27→PostCSS8.5.23 overridden, React/React DOM19.1.9; `node --test tests/postcss-security.test.mjs`:7 passed,0 failed. Logs `/tmp/eventcore-task2-tree-final.log`, `/tmp/eventcore-task2-green-final.log`.
- `npm audit --json` after clean install AND again after final Playwright install both returned exit0, `vulnerabilities:{}`, all severity counts0; dependencies total104. Logs `/tmp/eventcore-task2-audit-after.json`, `/tmp/eventcore-task2-audit-final.json`. This audit uses lockfile scope; extraneous local browser packages are not a separate audited product dependency claim.
- Build running with the exact synthetic CI placeholders plus `NEXT_TELEMETRY_DISABLED=1`; no further npm installations after build. Full output saved `/tmp/eventcore-task2-build.log`.

Minor log-display command typo `tail -25` failed after provisioning; corrected to `tail -n 25`. It had no product or test effect and did not conceal the provisioning failure above.

## Build, deployment and affected browser checks

- `npm run build` with synthetic CI env: exit0, Next15.5.27, compilation3.9s, all8 static pages generated and build traces complete. No build warning beyond environmental npm proxy warning.
- `npm run typecheck`: exit0 (`tsc --noEmit`).
- `node tests/pdf-deployment-trace.mjs`: exit0. Actual optimized route includes PDFKit package, licensed DejaVu regular/bold/license, Helvetica/Helvetica-Bold AFMs and compiled fonts, native Sharp and libvips. Every path in the route trace exists. Build occurs after the final dependency install; no later npm install invalidated the trace.
- Finance390 `EVENTCORE_CHECK_ROLE=finance EVENTCORE_CHECK_WIDTH=390 EVENTCORE_CHROMIUM_EXECUTABLE=/workspace/scratch/0d27d86074e8/eventcore-browser-runtime/chromium EVENTCORE_PYTHON=/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3 EVENTCORE_BROWSER_OUTPUT=/tmp/eventcore-task2-finance390 node tests/aligned-flows.browser.mjs`: exit0,7 routes, mutation `mark_assignment_paid`, PASS1 journey. Log `/tmp/eventcore-task2-finance390.log`, screenshots/results in the output directory.
- Provider390 identical command with `provider` and output `/tmp/eventcore-task2-provider390` initially exited1 on the preexisting immediate `editor.count()` assertion `Submitting closes the stale draft editor` (1 expected0), after waiting for `Orçamento enviado.`. Concurrent finance passed. Inspected unchanged handler: it awaits `m.run(...)` before `setEdit(null)`, while success-message display can occur earlier. Repeated provider390 unchanged, sequentially, with output `/tmp/eventcore-task2-provider390-retry`: exit0,7 routes, PASS1 full journey, including save-error retention, quote submission/editor removal, receipt, team, event, staffing/remuneration/finance membership/profile transitions. Evidence consistent with asynchronous timing window, not proof of universal flake or product security. No existing app/browser test edited; initial failure retained here and in `/tmp/eventcore-task2-provider390.log`.

Browser tests exercise real built Next UI, local synthetic platform fixtures, route geometry/no overflow and no page errors. They do not send real payments, invite workers, write real business records or call production providers. Browser runtime153 differs from the CI Playwright managed Chromium; hosted CI verification is pending controller publication.

## Final suite and bounded browser correction

`npm test` executed once, at the end of product/dependency checks: exit0,87 tests passed,0 failed/cancelled/skipped,4081.9ms. Includes all7 new PostCSS regressions and existing domain/UI/security/PDF tests. Full output `/tmp/eventcore-task2-test.log`. Only warning is the npm environmental http-proxy warning; no test deprecation or experimental warnings observed.

Controller subsequently authorized the bounded correction for the demonstrated provider assertion race. Cause traced precisely to `app/components/workflow-ui.tsx`: `setNotice(message)` precedes `await refresh()`, whereas the submit handler in `commercial-workspace.tsx` clears edit only after `m.run` returns. Therefore the success-message wait alone was an incomplete browser barrier. Added `await editor.waitFor({state:'detached',timeout:5000})` immediately before the existing count0 assertion in `tests/aligned-flows.browser.mjs`, preserving both actual editor removal and a finite5s failure. No sleep, indiscriminate timing changes, weakened assertion or product edit. Initial RED from the first provider390 run remains preserved above. Full npm test was not repeated for this exclusive standalone-browser edit, per controller instruction; the changed standalone browser journey is being run with output `/tmp/eventcore-task2-provider390-final` and log `/tmp/eventcore-task2-provider390-final.log`.

Visual self-check opened provider work-finance and finance independent-finance screenshots from the successful runs: typography, stacked cards/forms/actions and mobile navigation present without horizontal clipping. Automated geometry and page-error assertions passed on these journeys. This is a limited CSS regression review, not a complete redesign/UI audit.

Final provider390 with bounded teardown wait: exit0,7 routes, full mutation journey PASS,0 page errors; `/tmp/eventcore-task2-provider390-final/results.json` and `/tmp/eventcore-task2-provider390-final.log`. No more reruns required. Finance390 unchanged remained PASS from the earlier complete run.

## Self-review, files and residual limits

Reviewed final diff and behavioral mutation expectations: reverting override should fail4 security checks; removing ordinary transform or legitimate map compatibility should fail controls. Parent-only scoped override correctly applies to the dependency resolved from Next; current installed tree and audit prove the regenerated lock took effect through both installs. No Next/React upgrade, framework config change, map disabling, unsafeMap bypass, manual vendor manipulation, audit suppression or force fix. Product CSS/UI/Auth/data/integration/infra code remains unchanged. Browser5s wait fixes only the demonstrated observation window and still fails if stale edit remains.

`git diff --check`: exit0. Files to commit:

1. `package.json` — parent-scoped Next/PostCSS override.
2. `package-lock.json` — minimal official PostCSS package update.
3. `tests/postcss-security.test.mjs` —7 behavioral regressions/compatibility controls.
4. `tests/aligned-flows.browser.mjs` — bounded editor detach wait plus preserved count0 assertion.

Ignored handoff report remains at `.superpowers/sdd/2026-10-08-ci-runtime-verification/task-2-report.md`. Controller-owned plans/validation/checkpoint files were neither modified nor staged. No subagents/helpers/reviewers invoked; self-review only. No remote push/publication by this worker.

Remaining concerns: hosted CI must prove package installation/default managed Chromium on its actual runner and all configured steps; local provisioning was limited as recorded. Audit0 is scoped to the current npm lock/advisory database and does not prove universal security. The reviewed source-map paths/AST output and legitimate controls are confirmed; user CSS exposure, additional attack variants or other consumers were not comprehensively assessed. No concrete patch/API/build incompatibility remains observed. Controller will review this diff and publish/confirm hosted CI.

Commit created: `1f0eaba8846ba4f9e09f1c20d2c0a1a18c81adff` (`fix: patch Next PostCSS and await provider editor teardown`),4 files,90 insertions/8 deletions. Review range `776adf46fc89c58479957f773cdbfc9a2205296b..1f0eaba8846ba4f9e09f1c20d2c0a1a18c81adff`. Cached diff check passed before commit. Post-commit status shows only controller-owned untracked documents/checkpoint; no unstaged worker code changes.
