# EventCore adaptive implementation plan

Spec: docs/superpowers/specs/eventcore-adaptive.md
Baseline: e0725a3a97651a86eead39e8776cc2303b0af81f; working production source from 3cb92ef with the established Google patches.

Global constraints: incremental changes, no new projects, no destructive data operations, no exposure of credentials or private documents, no reapplication of the nine existing adaptive migrations. Authorized continuation includes validation and publication in the existing project.

## Task 1: Recover a reviewable source and deterministic build

Files: app/, lib/, public/, configs, package.json, scripts/, workflows.
Restore the verified production baseline, preserve Google server modules byte-for-byte, replace the corrupt packed-source build with directly tracked source. Retain original archives in Git history. Pin reproducible dependency resolution with a lockfile. Run the old corrupt integrity guard and observe its failure before changing the pipeline.
Expected: source is reviewable; npm run build reaches compilation without binary reconstruction. Commit after successful build with adaptive sources integrated.

## Task 2: Central profile and dashboard domain logic

Interfaces: ProfileType and capabilitiesFor/navigationFor are consumed by Task 4; document validation and dashboard aggregates match Task 3 rules.
Write failing tests for profile navigation, forged business/staff eligibility, document validation, paid/upcoming income and valid hiring denominator. Implement lib/capabilities.ts, lib/identity.ts and lib/dashboard.ts.
Expected: node --test tests/domain.test.mjs passes. Commit with Task 4 frontend after integration.

## Task 3: Complete the incremental database security and workflow

Interfaces produced: complete_profile(jsonb), get_event_opportunities(), apply_for_opportunity(uuid,text), hire_application(uuid), record_assignment_attendance(uuid,text,numeric,numeric), submit_assignment_rating(uuid,integer,text), get_professional_directory() and get_professional_reputation(uuid).
Audit actual policies/grants first. Write rollback-only flow tests exposing recursive policies and forged identity/status/reputation. Apply one additive hardening migration with transaction-safe profile completion/hiring, sanitized opportunity reads, valid rating/attendance, manager/client isolation and least-privilege grants. Mirror all already-applied migration SQL without reapplying it.
Expected: database tests pass, no test rows persist, existing admin/coordinator retains operations; advisors show no new security regressions.

## Task 4: Integrate the existing application

Consume Task 2 capabilities and Task 3 RPCs. Reuse readable controller code recovered before the corruption, correcting non-atomic writes and loading only authorized data. Add signup/profile editor, personalized home, separate real dashboard, organization selection, opportunities/applications, hiring and reputation. Keep existing clients, events, staffing, attendance, payments and Google routes. Add responsive styles without unrelated redesign.
Expected: domain tests, TypeScript and npm run build pass; browser renders login/signup and desktop/mobile pages without errors.

## Task 5: Review, deploy and verify

Run fresh whole-branch review, fix material findings with regression tests, publish the existing feature branch preview, verify build and rendered app; integrate into the existing production branch only after checks. Verify eventcore.space and PWA/Google route behavior. Document any unavailable authenticated checks precisely.
Expected: deployment READY at the validated commit and official domain serves the update, or a concrete external blocker is reported without a false completion claim.

## Review focus

Cross-organization access, RLS recursion, forged onboarding/role/rating/earnings, concurrent overbooking, accepted application consistency, atomic profile/hire/attendance operations, freelancer privacy, no forced registration for old users, Google regressions, mobile overflow, empty real-data dashboards.
