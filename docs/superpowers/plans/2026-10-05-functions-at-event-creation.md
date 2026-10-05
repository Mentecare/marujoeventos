# Functions at Event Creation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan in the current session. Steps use checkbox syntax.

**Goal:** Configure functions while creating an event and remove every later function insertion path.

**Architecture:** A dedicated creation form collects optional function rows and submits the event and rows through one authenticated PostgreSQL RPC. The database creates a new event and its functions in one transaction; a separate enforcement migration removes direct function insertion without affecting existing records or staffing operations.

**Tech Stack:** Existing Next.js 15.5.27, React 19.1.9, Supabase JavaScript 2.117.2 and PostgreSQL 17.

**Spec:** The user's current request and attached video `upload/1000598858.mp4`: move the existing specialty, vacancies, reserves, cost, briefing, requirements and marketplace option into event creation; allow insertion there only. Preserve the approved interface, navigation, dashboard, hiring, finance and Google integration.

## Global Constraints

- Keep all existing event and function records.
- Preserve creation without functions; explain that functions cannot be added later.
- Accept multiple functions, removable before submission.
- Derive creator, coordinator, function names and legacy service types on the server.
- Keep current organization authorization and existing function publication management.
- Do not upgrade product dependencies.

## Review Focus

- Invalid second function: no partial event or first function must remain.
- Foreign organization or client: reject creation without leaking or changing records.
- Blank cost versus explicit zero: preserve the distinction.
- Failed submission: retain all draft fields for correction or retry.
- Reload failure after a committed creation: clear the submitted draft without creating duplicates.

### Task 1: Atomic creation and database enforcement

**Files:** CLI-generated `supabase/migrations/*_eventcore_create_event_with_services.sql`, `*_eventcore_functions_creation_only.sql`, `tests/event-creation.sql`, `tests/database-flow.sql`.

**Interfaces:** `public.create_event_with_services(p_event jsonb, p_services jsonb default '[]') returns jsonb` returns `{event, services}`. Inputs contain new event fields and function rows without any existing event ID.

- [x] Write and run rollback integration checks that fail when the creation RPC is absent.
- [x] Implement explicit authentication, tenant authorization, active specialties, valid dates, quantities and money; insert the new event and all functions atomically.
- [x] Remove authenticated direct function INSERT and enforce immutable function event ownership, while retaining existing SELECT/UPDATE/DELETE policies.
- [x] Update existing integration fixtures to use creation-time functions and run the complete rollback flow.

### Task 2: Creation form and request validation

**Files:** `lib/event-creation.ts`, `app/components/event-creation.tsx`, `app/page.tsx`, `app/globals.css`, `public/sw.js`, `tests/event-creation.test.mjs`.

**Interfaces:** `buildEventCreation(fields: FormData, functionKeys: string[]): EventCreationInput` produces `{event, services}`. `EventCreationForm` receives clients, specialties, busy, and `onCreate(input): Promise<boolean>`; success resets the form and failure retains drafts.

- [x] Write failing tests for multiple functions, validation, optional empty functions and zero versus absent costs.
- [x] Implement the scoped creation form, add/remove rows and local validation; disable changes during submission.
- [x] Submit one RPC, preserve committed creation if the subsequent reload fails, and remove the old function insertion handler and form.
- [x] Verify form behavior on mobile and desktop, including failure/retry, reset, publication of existing functions, unchanged navigation and no overflow.

### Task 3: Review and publication

- [x] Run `npm test`, `npm run typecheck`, `npm run build`, database checks and browser checks.
- [x] Request one independent code review and resolve substantive findings.
- [x] Publish the additive RPC before the new interface, then activate creation-only enforcement after production is ready.
- [x] Verify the production deployment, service worker, database privileges and preserved record counts.

## Verified outcome

Published to https://eventcore.space through PR #5. The additive RPC migration is `20261005093505`; creation-only enforcement is `20261005094634`, activated after production was READY. All three rollback database scripts pass after enforcement. The existing event and function record fingerprints are unchanged.

Unit suite: 20/20. TypeScript and production build: passed. Browser navigation/layout: 105 checks. Interactive creation at 360, 390 and 1280 px: passed, including failure retention, duplicate-submit prevention, reset after committed creation with failed refresh, and publication management. Independent review: approved with no findings.
