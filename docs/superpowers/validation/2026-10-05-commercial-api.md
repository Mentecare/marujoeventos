# EventCore commercial and work API — Tasks 1–2 contract

Status: Tasks 1–2 implemented and validated in a disposable PostgreSQL 17.5 engine on 2026-10-06. **Not applied to hosted Supabase.** Deploy with the compatible UI after controller review. Task 2 extends this contract with external work, immutable remuneration evidence, private people/teams, real histories and scoped presentation. Types and caller adapters: `lib/commercial.ts`; verified server caller: `lib/actor-server.ts`; schemas: `20261005194714_eventcore_commercial_foundation.sql` and `20261006082244_eventcore_workflows_history.sql`.

## Caller and authorization

Call `commercialApi(authenticatedBrowserClient)` in the browser, or `commercialApi((await commercialActor(request)).db)` in server routes. The actor validates the bearer JWT with `auth.getUser`, checks the active profile with that same caller client, and retains the caller Authorization header for every RPC/RLS query. It never constructs a service-role client. Actor failures are `ActorError` with status 401 (`unauthorized`), 403 (`forbidden`) or 503 (`commercial_unavailable`). Keep server responses/exports private and uncached. Existing Google staff verification is unchanged.

All commercial public RPCs below require `authenticated` grants and active database identity/tenant checks; JWT user metadata never grants business permissions. Organization market role is independent of profile type and generic staff role. Owners have finance permission. Active organization members have finance permission only after an owner enables `finance_authorized`. Manager/coordinator status alone permits operations, not financial reads. Buyer agencies/scenography hire provider organizations; buyer identities never authorize direct worker hiring/publication/payment.

| Canonical helper | Meaning |
| --- | --- |
| `private.eventcore_org_owner(uuid)` | Actual active organization owner; no generic admin shortcut. |
| `private.eventcore_org_member(uuid)` | Active owner or active member. |
| `private.eventcore_org_manager(uuid)` | Owner or active manager. |
| `private.eventcore_org_finance(uuid)` | Owner or explicitly finance-authorized active member. |
| `private.eventcore_has_identity()` | Caller has valid private CPF/CNPJ check digits; not government verification. |
| `private.eventcore_can_manage_event(uuid)` | Active provider/unclassified tenant manager or designated coordinator; historical unowned creator also retains operations. Buyer events do not authorize workforce operations. |
| `private.eventcore_can_finance_event(uuid)` | Tenant owner/explicit finance member, or creator of that historical unowned event. Identity completion is not required for history reads. |
| `private.eventcore_can_hire_event(uuid)` | Event operator with identity and provider classification; historical unowned event additionally requires creator to own an active provider. Hiring currently also checks finance permission because the existing RPC returns/creates wage amounts. |
| `private.eventcore_operates_freelancer(uuid)` | Read participant contacts only through an authorized operating/finance event relationship. |
| `private.eventcore_can_pay_assignment(uuid)` | Assignment finance permission plus caller identity/provider classification. Finance members can pay without being operating managers. |

Private helper schemas are not application RPC endpoints. `can_finance_event` is the public read-permission check. Display a finance-authorized user's missing document honestly and require completion before a new remuneration/payment operation. Do not infer provider role from CPF/CNPJ, organization type, Google staff role, or past events.

## Exact public RPC signatures

UUID results are JSON strings; `void` results are null; `jsonb` results are JSON objects/arrays. Dates are ISO `YYYY-MM-DD`; timestamps are ISO strings. Decimal money is BRL with two fractional digits. TypeScript money fields are numbers; SQL persists exact `numeric` values. Amounts must be finite and nonnegative except receipts, which must be positive.

| RPC / SQL return | Exact named arguments | Permission / result |
| --- | --- | --- |
| `configure_business_identity → uuid` | `p_payload jsonb` | Active caller; existing organization must be owned. Returns organization ID. |
| `get_commercial_context → jsonb` | none | Active caller; own context only. |
| `set_organization_finance_member → void` | `p_organization_id uuid, p_profile_id uuid, p_enabled boolean` | Owner only; member must be active; audited. |
| `can_finance_event → boolean` | `p_event_id uuid` | Canonical finance history/read capability. |
| `list_commercial_providers → jsonb` | none | Active caller; sanitized active provider array. |
| `create_contract_request → uuid` | `p_buyer_organization_id uuid, p_provider_organization_id uuid, p_title text, p_description text, p_event_date date, p_venue text` | Identified buyer finance actor, valid active provider. Returns request ID. |
| `save_sale_quote → uuid` | `p_quote jsonb, p_items jsonb` | Identified provider finance actor. Returns new/updated proposal ID. |
| `get_sale_quote → jsonb` | `p_proposal_id uuid` | Provider finance actor; buyer finance actor only for sent/accepted own quotes; legacy proposal creator. Sale-only DTO. |
| `submit_sale_quote → void` | `p_proposal_id uuid, p_expected_revision integer` | Identified provider finance actor; draft, current revision, valid dates/items. |
| `accept_sale_quote → uuid` | `p_proposal_id uuid, p_expected_revision integer, p_external_evidence text DEFAULT NULL` | Identified actual buyer finance actor for platform quotes; identified provider finance actor plus evidence for external quotes. Returns contract ID. |
| `get_commercial_workspace → jsonb` | `p_organization_id uuid` | Owner/explicit finance member of selected organization. Requests, sale-only quotes, contracts, receipts. |
| `record_customer_receipt → uuid` | `p_contract_id uuid, p_amount numeric, p_method text, p_received_on date, p_idempotency_key text` | Identified contracted provider finance actor only. Returns receipt ID. |
| `get_event_operations → jsonb` | `p_event_id uuid` | Authorized event operator; explicit operational allowlists (below); no wage fields. `can_hire` includes finance and open-event prerequisites. |
| `get_my_schedule → jsonb` | none | Existing completed active freelancer profile only; own event/service schedule; no service costs. Retained unchanged; `getWorkerSchedule` adapter. |

Existing compatible signatures retained: `complete_profile(p_payload jsonb) → jsonb`; `create_event_with_services(p_event jsonb, p_services jsonb DEFAULT '[]') → jsonb`; `create_event_assignment(p_service_id uuid, p_freelancer_id uuid, p_status text DEFAULT 'invited', p_amount numeric DEFAULT NULL, p_application_id uuid DEFAULT NULL) → uuid`; `mark_assignment_paid(p_assignment_id uuid, p_method text) → void`; `set_assignment_amount(p_assignment_id uuid, p_amount numeric) → uuid`; `set_organization_member(p_organization_id uuid, p_profile_id uuid, p_active boolean DEFAULT true) → void`. They now use canonical tenant/provider/finance checks. Membership changes cannot reactivate/deactivate another owner's finance/manager authorization through a generic manager shortcut. Deactivating membership clears explicit finance permission.

## Input contracts

`BusinessIdentityInput`:

```ts
{
  organization_id?: string; // omit to create; actual owner required to update
  display_name: string; // 2..150 characters
  organization_type: 'team' | 'company' | 'agency';
  market_role: 'provider' | 'buyer';
  buyer_subtype?: 'agency' | 'scenography' | null; // required only for buyer
  document: string; // one CPF ou CNPJ field
}
```

Classification can move from unclassified to provider/buyer through this authorized action. A classified organization cannot switch market role. Updating an existing organization's type is not supported by this RPC; it retains its existing type. The responsible's document is stored only in `profile_private_identity` and returned in context only as type/last four. No `verified` badge is produced. The legacy `complete_profile` JSON shape still accepts `document_number`; new UI supplies `document`. CPF is permitted for team/company/buyer responsibles, while freelancer completion still requires CPF. `market_role`/`buyer_subtype` are optional additions to profile completion; omitting them leaves a newly created organization unclassified.

Normalize to uppercase, remove standard mask punctuation and whitespace, then infer CPF for 11 digits or numeric/alphanumeric CNPJ for 14 characters. Invalid/non-mask characters remain invalid. CNPJ uses 12 alphanumeric characters plus two numeric check digits, ASCII value minus 48, modulus 11 and official weights. Existing CPF/numeric CNPJ validators are reused. This is syntax/check-digit validation, not identity verification. Primary references read: [Receita technical manual](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf) and [Receita FAQ, question 14](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/perguntas-e-respostas/cnpj/cnpj-alfanumerico.pdf). Both confirm `12.ABC.345/01DE-35`.

`SaleQuoteInput` and lines:

```ts
{
  id?: string; expected_revision?: number; // both for updating a draft
  organization_id: string; // provider, never caller-supplied buyer ownership
  request_id?: string | null; // platform request; provider must match request
  client_id?: string | null; // active provider-owned client for external work
  title: string; event_date?: string | null; venue?: string | null;
  valid_until: string; payment_terms: string; show_unit_prices: boolean;
}
// 1..200 items
{
  label: string; service_type?: 'loader' | 'security' | 'waiter' | 'other';
  quantity: number; // integer 1..10,000
  contract_days: number; // integer 1..366
  client_unit_price: number;
  planned_hours?: number | null;
  freelancer_unit_cost?: number | null; // internal provider input ONLY
}
```

Titles are 2..200 characters; labels 1..300; payment terms ≤3,000. Validity must be finite and today or later. Unit price/cost must have cent precision, be within `0..9,999,999,999.99`, and total must also fit that range. Hours, when supplied, are `0..9,999.99`. Request title is 2..200; description ≤5,000; venue is truncated to 500 characters.

For platform requests, provider/buyer identifiers and client name are derived from the stored authorized request. Passing extra forged `buyer_organization_id` fields does not change ownership. Saving a new request quote creates a provider-scoped client display record automatically. An external quote requires an active client already owned by the provider. Existing Clients management supplies that record; the external customer requires no account.

## Results and state changes

`CommercialContext` supplies profile ID, `identity_complete`, document type/last-four and member organizations with role/subtype and `is_owner`, `can_operate`, `can_finance`. `ProviderSummary` contains only ID, display name, organization type and specialties. It has no owner document or commercial totals.

`SaleQuoteDTO` is an explicit allowlist for both UI and PDF: ID, revision, status, title, issue timestamp, event date/venue, validity, payment terms, unit-price-display flag, sale total, issuer `{id, display_name}`, client `{display_name}`, request/contract IDs and items `{id, label, quantity, contract_days, planned_hours, client_unit_price, line_total}`. It never returns freelancer cost, internal margin or private document. The unit-display flag affects presentation only; totals are identical. This task supplies issuer name/ID; logo lookup/rendering and PDF route belong to the delivery task and must retain authorized access.

Line sale = quantity × days × sale unit price. The approved example gives R$5,600 independently from 10 × 2 × R$220 remuneration (R$4,400). Worker historical amounts remain totals; no migration multiplies them. Existing proposal-item days default to 1, retaining previous arithmetic. Existing proposal totals are not rewritten.

A draft starts at revision 1 and each successful save increments its revision. Updates require `expected_revision`; submission/acceptance require `p_expected_revision`. Submit freezes the quote at sent. Sent quotes cannot be edited; make another draft/quote if conditions change. Buyer cannot see draft quotes or raw proposal/item cost rows. Acceptance locks request then proposal, validates current revision/validity, recomputes sale totals, derives parties from the proposal/request, creates one immutable contract snapshot, and records audit evidence. A request can have only one accepted contract. Repeated acceptance is rejected. Accepted `get_sale_quote` returns the stored snapshot, so subsequent client/issuer profile edits cannot change the accepted document.

External acceptance is recorded by the provider, with `p_external_evidence` 3..2,000 trimmed characters, and `acceptance_method='external_recorded'`. It does not claim that an unregistered customer authenticated. Platform method is `platform`. No email/notification is sent by these RPCs.

Workspace contracts include `sale_total`, the sale-only `quote_snapshot`, parties and acceptance metadata, plus `received_total` and `receivable_total = sale_total - received_total`. Workspace omits external evidence. Receipts contain ID, contract ID, amount, method, received date, created timestamp; workspace omits recorder/idempotency key. Raw contract/receipt tables are RLS protected to the same commercial parties; raw contracts also retain external evidence for authorized finance audit. Methods are `pix|transfer|cash|other`; receipt date must be finite and not in the future; key is 1..100 nonblank characters. Repeating the same contract/key/data returns the original ID; changed data raises `idempotency_conflict`; overpayment raises `receipt_exceeds_receivable`. Contracts and receipts are append-only evidence.

Operators use `get_event_operations` for events/services/assignments without wages and use finance tables only after `can_finance_event` succeeds. The returned `can_hire` is the effective actor permission: identity/provider/operator **and finance**, with event status outside `completed|cancelled`; it does not promise vacancy capacity or eligibility of a specific candidate. The underlying private `eventcore_can_hire_event` remains the role/identity/operator prerequisite used by existing workforce functions. Workers use `get_my_schedule` plus RLS-filtered own assignments/payments. Direct `event_services` rows include internal remuneration and therefore remain finance-only. `get_event_opportunities` retains its current signature but its `amount` is null for non-freelancer callers; the buyer cannot obtain provider wages through discovery. Later opportunity-sharing changes must keep public payloads sanitized.

`EventOperations` uses explicit SQL allowlists matching `lib/commercial.ts`. Root keys are `event, can_finance, can_hire, services, assignments`; event keys are `id, name, organization_id, status, start_at, end_at, venue, arrival_tolerance_minutes`; service keys are `id, event_id, label, service_type, specialty_id, quantity_needed, reserve_target, contract_days, planned_hours, briefing, requirements, visibility, application_enabled`; assignment keys are `id, event_service_id, freelancer_id, status`. Every key is present, including nullable fields. Exact-key SQL assertions guard against accidental column propagation. Event notes, client IDs, Google metadata, wage amounts and future table columns are not automatically included.

Linked freelancer reads require own worker identity or an authorized operating/finance event relationship. Generic staff may maintain only unlinked legacy records (`profile_id IS NULL`). Raw INSERT cannot create any linked identity, UPDATE cannot rebind identity or row ID, and linked DELETE cannot enable delete/reinsert ownership transfer. The ownership trigger also protects inserts/updates executed through a definer function with an authenticated actor. `complete_profile` retains verified self-onboarding and metadata updates for the caller's actual linked identity. Administrative profile deletion/maintenance without a caller identity remains an explicitly privileged database action; no client claim/rebind endpoint is exposed.

Google sync remains staff-only, then verifies the same caller JWT with `commercialActor` and calls `get_event_operations` for the requested event before constructing the privileged export client, reading event/client/workforce data, fetching a Google token, calling Calendar or updating integration state. Permission failure, missing/mismatched event and mismatched verified actor fail closed with 403. Google OAuth/staff helper/callback behavior remains unchanged. An authorized staff event operator does not need finance permission for this operational export.

## Errors and direct writes

Domain exceptions are Postgres `P0001`, with stable messages: `forbidden`, `identity_required`, `invalid_private_document`, `private_document_conflict`, `invalid_market_role`, `invalid_organization`, `market_role_locked`, `member_not_found`, `provider_required`, `invalid_request`, `invalid_quote_items`, `invalid_quote_item`, `invalid_quote`, `invalid_quote_total`, `stale_quote`, `quote_immutable`, `quote_not_available`, `external_acceptance_evidence_required`, `invalid_receipt`, `idempotency_conflict`, `receipt_exceeds_receivable`, `commercial_record_immutable`, `freelancer_ownership_is_immutable`. Invalid SQL casts can return Postgres input/date errors; validate forms before calling. The adapter throws `Error(result.error.message)` and does not translate authorization into success. Handle expected domain errors and refresh stale drafts.

Authenticated direct writes to proposals/items, contracts, receipts, organization/member records, assignments insert/delete, payments, attendance and documents are revoked. Financial select policies replace old permissive staff/OR policies rather than adding another predicate. Audit visibility is caller-only, private identity is self-only. Assignment own-status responses remain allowed, with immutable identity/pay guards. Buyer raw event/service publication writes and hiring are denied. Profile/photo/Google integrations retain existing dedicated helpers and behavior.

## Compatibility, validation and non-destructive recovery

Do not apply the backend before UI consumes role/context, operations DTO and finance permissions. Old unclassified organizations retain history and cannot create new workforce work until explicit owner classification. Existing undocumented users retain historical creator operations/finance reads; new commercial/hiring/payment operations require completion. Generic staff previously read other tenants' financial data; this permissive access is intentionally removed. Old event-creation clients omit organization/classification and will fail authorized creation until compatible UI supplies the selected provider. Some previous raw service/assignment/document writes now require the authorized RPCs.

Local proof: 30 migration files passed on real disposable PostgreSQL 17.5 with minimal auth/storage shims. `commercial-security.sql` passes 172 statements in a transaction ending rollback; `database-read.sql` and `profile-photos.sql` each pass 8 statements. Nine focused tests (six commercial and three Google-handler), 35 total unit tests and typecheck passed. Actual Next HTTP integration returns 403 for unrelated staff, with the caller JWT retained on the permission RPC and no privileged export reads/adapters called. No hosted schema was changed; hosted authenticated API fixtures and platform advisors remain controller verification work. Fixture scope covers CPF/CNPJ, classification, undocumented legacy history, buyer raw/API denial, cross-tenant requests/quotes/contracts/receipts, draft/stale/repeated acceptance, external acceptance, finance grant/denial, buyer sale-only output, worker own pay and immutable accepted evidence.

Recovery is feature deactivation, not destructive schema rollback:

1. Disable the commercial UI/routes and revoke authenticated EXECUTE on the new mutating business/finance/request/quote/receipt RPCs. Keep accepted contracts, snapshots, receipts, added columns and indexes intact. Prefer preserving tightened tenant/finance policies.
2. Before applying, save actual `pg_get_functiondef` results, `pg_policies` and table/function ACLs for affected objects alongside the controller's baseline. Recheck business record hashes/counts for concurrent change. The ignored `database-before.json` provides prior definitions/policies but does not include all ACLs.
3. If compatibility requires restoring previous operations, create a new additive recovery migration. Restore ONLY reviewed previous definitions for replaced helpers/RPCs and previous policies/ACLs from the pre-apply snapshot. Test it on a clone first. Do not replay prior migrations wholesale: they contain schema creation and overly permissive generic staff finance policies. Restoring those finance policies reopens a known tenant leak and requires explicit controller security review.
4. Trigger inventory added here: `commercial_provider_service`, `commercial_quote_immutable`, `commercial_quote_items_immutable`, `commercial_contract_immutable`, `customer_receipt_immutable`, `commercial_freelancer_owner`. Retain contract/receipt/accepted-quote and worker ownership immutability. Restoring a generic freelancer ALL policy would reopen identity-forgery wage access and is not safe recovery. Any restoration of provider service creation must coordinate its guard with restored event-creation RPCs; removing only the guard does not restore revoked privileges.
5. Replaced definitions: organization owner/member/manager, event manage/tenant checks, `complete_profile`, tenant/assignment guards, event/assignment creation, worker payment/set-amount, organization membership and opportunity discovery. Restore individually from saved definitions; leave Google `eventcore_is_staff`/`verifyStaffToken` unchanged. Rerun legacy/tenant fixtures and compare historical hashes/counts. Never drop data, delete migration history, reclassify organizations by bulk UPDATE or recalculate historical agreements as daily rates.

Review I2/I3 are closed by Task 2 in disposable PostgreSQL: the owner’s exact label/quantity/initial-cost UPDATE and function DELETE fail; completed historical `set_assignment_amount(...,999)` and raw agreement/payment amount writes fail while the original R$440 rows remain unchanged. This is local SQL evidence, not a claim that hosted Supabase has applied the migration.


## Task 2 exact workflow RPCs

`workflowApi(authenticatedClient)` reuses the same caller/RLS client as `commercialApi`. The workflow migration follows the commercial foundation; it does not rewrite prior rows. Every new public endpoint below grants EXECUTE only to authenticated callers. All private DTO/lock/date helpers are non-client internals. Supplied UUIDs never grant tenancy. No RPC sends a notification, email, Calendar entry or broad alert.

| RPC / return | Exact named arguments | Actor/result |
| --- | --- | --- |
| `create_external_work_client → uuid` | `p_organization_id uuid, p_name text` | Identified provider finance manager. Creates an organization-owned client display record, no customer account. Name 1..150. |
| `create_event_with_services → jsonb` | Retained `p_event jsonb, p_services jsonb DEFAULT '[]'` | Identified provider manager with finance; creation extensions below. Returns the created event/services to that authorized finance actor. |
| `publish_work_function → void` | `p_service_id uuid, p_published boolean` | Identified provider operator with finance, open event. Only publication/application flags change. |
| `get_work_opportunities → jsonb` | none | Same eligible authenticated browsing as retained `get_event_opportunities`; explicit DTO below. |
| `invite_selected_workers → jsonb` | `p_service_id uuid, p_freelancer_ids uuid[]` | Canonical hire permission plus finance; 1..200 unique non-null selected workers; transaction returns assignment-ID array. No team-wide automatic selection. |
| `create_event_assignment → uuid` | Retained five named arguments | Creates `invited`/`reserve` only, initial conditions copied into immutable terms. `confirmed` raises `worker_acceptance_required`; overriding initial amount raises `remuneration_revision_required`. Reopening a cancelled row raises `historical_assignment_cannot_reopen`. |
| `respond_to_assignment → void` | `p_assignment_id uuid, p_status text` | Actual worker, invited/reserve only; `confirmed` explicitly accepts the current offer; `cancelled` declines availability. |
| `propose_assignment_terms → uuid` | `p_assignment_id uuid, p_terms jsonb` | Identified provider finance actor; new term revision, never updates old agreement. Days/hours must exactly match the initial snapshot. |
| `accept_assignment_terms → void` | `p_term_id uuid` | Actual linked active worker, latest offer only. Acceptance is append-only; retry of an already accepted term returns null. |
| `get_my_work_assignments → jsonb` | none | Active freelancer; own assignment DTO array, including own legacy totals and new accepted/offered terms. |
| `get_event_remunerations → jsonb` | `p_event_id uuid` | Canonical event finance actor; same explicit assignment DTO for that event only. Coordinators without finance are denied. |
| `mark_assignment_paid → void` | Retained `p_assignment_id uuid, p_method text` | Canonical identified provider finance actor; new jobs pay the latest accepted term through append-only `workforce_payments`; historical jobs retain existing `payments` amounts. Repeated paid operation returns null. |
| `set_assignment_amount → uuid` | Retained `p_assignment_id uuid, p_amount numeric` | Validates authorization/cent input then denies rewriting: legacy `historical_agreement_immutable`, new `remuneration_revision_required`. |
| `get_provider_people → jsonb` | `p_organization_id uuid` | Provider organization manager; private base and reusable team DTO. |
| `set_provider_base_member → void` | `p_organization_id uuid, p_freelancer_id uuid, p_enabled boolean` | Actual provider owner; adds/removes active onboarded worker. Removal clears reusable memberships, never job records. |
| `save_provider_team → uuid` | `p_organization_id uuid, p_team_id uuid, p_name text` | Actual provider owner; null team ID creates, non-null renames owned team; trimmed name 1..150. |
| `delete_provider_team → void` | `p_team_id uuid` | Actual owning provider; removes reusable team/members only. |
| `set_provider_team_member → void` | `p_team_id uuid, p_freelancer_id uuid, p_enabled boolean` | Actual owning provider; addition requires current private-base membership. |
| `get_work_finance → jsonb` | `p_event_id uuid` | Canonical event finance reader, including authorized undocumented legacy history. Sources/unknowns below. |
| `record_work_expense → uuid` | `p_event_id uuid, p_label text, p_amount numeric, p_receipt_reference text DEFAULT NULL` | Identified provider finance actor; label 1..300, amount null=unknown or exact nonnegative cents; reference ≤500. Finance permission suffices without manager membership. |
| `record_work_expense_payment → uuid` | `p_expense_id uuid, p_amount numeric, p_method text, p_paid_on date, p_idempotency_key text` | Same event finance actor; positive exact cents, known contracted expense, no overpayment; retry with identical expense/key/data returns prior ID, changed data rejects. |
| `complete_work_event → void` | `p_event_id uuid` | Canonical operator; non-cancelled event must have actually ended. This sets completed status, not participant evidence. |
| `confirm_assignment_completion → void` | `p_assignment_id uuid` | Actual worker on ended completed confirmed/check-in/check-out assignment; new terms must be accepted. Explicit confirmation that the work actually occurred, separate from availability. |
| `submit_assignment_rating → uuid` | Retained `p_assignment_id uuid, p_rating integer, p_comment text DEFAULT NULL` | Actual event operator reviewing a counterparty worker with real completed evidence; self-review denied, one review/assignment; stars 1..5, comment ≤1,000. |
| `confirm_contract_completion → void` | `p_contract_id uuid` | Actual buyer finance participant, with ended completed linked work; provider owners/members cannot confirm as their own buyer. External customer accounts are never fabricated. |
| `submit_provider_rating → uuid` | `p_contract_id uuid, p_rating integer, p_comment text DEFAULT NULL` | Actual buyer finance participant after participant confirmation; provider owner/member self-review denied; unique per contract. |
| `get_provider_worker_history → jsonb` | `p_organization_id uuid` | Own provider manager/finance actor; actual work history with independent evidence counts. |
| `get_buyer_provider_history → jsonb` | `p_organization_id uuid` | Actual buyer finance actor; participant-confirmed provider history only. |
| `get_buyer_work_status → jsonb` | `p_contract_id uuid` | Actual buyer finance actor; sale snapshot/receipts plus limited linked execution status, no people, wages or expense details. |
| `get_provider_presentation → jsonb` | `p_organization_id uuid` | Own active provider member, or actual buyer finance actor with a request/contract relationship. Allowlisted presentation only. |
| `get_provider_photo_collection → jsonb` | `p_organization_id uuid` | Same scoped presentation relationship; existing owner’s avatar/portfolio metadata for authorized signing. |

Retained canonical calls have typed workflow adapters:

| Adapter | Exact RPC / named arguments / return |
| --- | --- |
| `createAssignment(serviceId, freelancerId, status='invited')` | `create_event_assignment(p_service_id uuid, p_freelancer_id uuid, p_status text)` → UUID, with SQL defaults for amount/application. The adapter accepts `invited|reserve` and cannot override remuneration or force worker acceptance. |
| `applyOpportunity(serviceId, message=null)` | `apply_for_opportunity(p_service_id uuid, p_message text)` → application UUID. |
| `hireApplication(applicationId)` | `hire_application(p_application_id uuid)` → invited assignment UUID. |
| `recordAttendance(assignmentId, kind, latitude, longitude)` | `record_assignment_attendance(p_assignment_id uuid, p_kind text, p_lat numeric, p_lng numeric)` → null; kind `in|out`, timestamp recorded by SQL. |
| `validateAttendance(assignmentId)` | `validate_assignment_attendance(p_assignment_id uuid)` → null; canonical event operator, completed recorded check-in/out required. |

A published candidature→hire creates an invitation, followed by the worker’s explicit availability/remuneration acceptance. Private base/team membership never applies, invites, accepts, confirms completion or earns reputation.

## Creation, immutable terms and payment interface

`EventCreationInput`/`buildEventCreation` additionally accept event fields `organization_id`, `origin`, `commercial_contract_id`, `public_region`. New origins are `platform|whatsapp|referral|other`, default `other`; existing events remain SQL NULL (historical unknown). Origin is independent of each function’s `visibility`; default functions remain private. `commercial_contract_id`, when supplied, must be an accepted contract of this provider and this exact client, including against raw INSERT. One event per contract. Obtain the platform client ID from the accepted contract, not from a forged buyer input. External clients need no account: create/select an owned client, then create the event.

`workflowApi(db).createWork(input.event, input.services)` accepts the exact `EventCreationInput` types returned by `buildEventCreation`; its `CreatedWork` result declares the returned finance-authorized event/service fields, including IDs, stored origin and initial conditions. Creation still returns the compatible database-row JSON, so use `getEventOperations`, `workerAssignments`/`eventRemunerations`, `buyerWork` and `finance` for subsequent role-scoped reads. `WorkRemuneration` declares all eight required output keys; nullable rate/total/hours/benefits are present, never absent. Opportunity benefits are always null. Revision input `RemunerationInput` keeps optional additions/deductions/benefits and null hours defaults, but must supply the unchanged recorded days/hours.

New service inputs: `remuneration_basis: daily|service`, `remuneration_rate`, `planned_hours`, `benefits`, `additions`, `deductions`, and `public_description`. Days remain per-function positive integers. Hours 0..9,999.99; benefits/public description ≤2,000; public region ≤150. Amounts have exact cents and final per-worker total ≤9,999,999,999.99. Daily total = rate × days + additions − deductions; service total = rate + additions − deductions. Example: daily R$220 × 2 = **R$440 per worker**; quantity affects capacity/aggregate expense, never a single worker’s total. Sale pricing remains independent. Omitting basis/rate retains legacy `freelancer_unit_cost` total interpretation; old costs are never multiplied.

Every actual new assignment copies the initial role/day/hour/remuneration conditions into `assignment_terms` revision1. All term rows/acceptances/new workforce payments are append-only. `assignments.agreed_amount` retains its original value; it is **not the current accepted payable after a revised offer**. Use `accepted_terms.total`, with `legacy_agreed_amount` only for rows without any new terms. The latest offered revision appears separately. A proposed revision cannot silently become payable; only the exact worker accepts it, and days/hours remain creation-only. Revisions/first acceptances reject completed/cancelled/ended jobs, cancelled/check-out/no-show assignments or already paid new jobs. Payment retries do not change method/amount/evidence. New payroll is in `workforce_payments`; legacy `payments` are retained and the DTO merges both without copying/recalculating either.

`AssignmentTerms` exact keys: `id, assignment_id, revision, basis, rate, contract_days, planned_hours, benefits, additions, deductions, total, created_at, accepted_at`. `rate/total` may be null for an unknown legacy-style offer; unknown does not become zero. `RemunerationInput` for revisions uses `basis, rate, contract_days, planned_hours, benefits, additions, deductions`; supply the same recorded days/hours. `WorkerWorkAssignment` exact keys: `id, freelancer_id, event_service_id, event_id, event_name, venue, start_at, end_at, event_status, status, function_name, legacy_agreed_amount, offered_terms, accepted_terms, terms_history, payments, completion_confirmed`. Each payment has `id, amount, status, method, paid_at, term_id`; legacy term ID is null. Worker calls return own rows only; provider calls require finance.

Function INSERT is allowed only inside the canonical creation transaction through a private, transaction-bound creation session, with no caller write permission. UPDATE permits only publication/application flags; all identity, quantity/reserves, days/hours, briefing/requirements/public description and original remuneration conditions are frozen. DELETE also rejects, including privileged definer probes. Completed event status/dates/tolerance and completed assignment statuses cannot be reopened/changed. Recorded attendance freezes event dates/tolerance so punctuality cannot be manufactured by shifting the schedule afterward. Google may still update its existing integration metadata after authorized sync; it must not reopen completed work. Existing event-edit/Google UI must respect these errors.

`get_event_operations` retains its explicit root/event/assignment allowlists, adding only `planned_hours` to operational service keys. It still exposes no remuneration/benefits/sales. `get_my_schedule` remains compatible; use the new assignment DTO for the worker’s complete conditions/payments.

## Opportunity, finance and evidence projections

Retained opportunity columns keep their signature but now publish neutral `event_name='Oportunidade: [function]'`, Brazilian calendar-date timestamps (without the private event time), `venue=public_region` or `Região a confirmar`, and `requirements=public_description` or null. Publication never automatically exposes the private job name, exact venue/address, client, private requirements/benefits, notes or actual team. `get_work_opportunities` has those same15 keys plus `remuneration`. Only eligible authenticated freelancers get initial advertised `{basis,rate,contract_days,planned_hours,benefits:null,additions,deductions,total}`; non-workers get `amount:null, remuneration:null`. These are offered initial conditions, never another worker’s accepted agreement. Full private timing/location/conditions remain in authorized participant/operations DTOs. Task4 public sharing/alerts must retain this boundary and omit worker remuneration in generic public/channel payloads.

`ProviderPeople` exact shape: `{base:[{freelancer_id,full_name,city,active}], teams:[{id,name,freelancer_ids}]}`. It contains neither wages nor private worker contact/documents. Discovery is the separate `get_professional_directory` (name/city/specialties and actual aggregate evidence); zero reviews produce `rating:null`, never the cached/default5. Stored legacy cached rating/job values are not rewritten by this migration.

`WorkFinance` exact keys are declared in `lib/commercial.ts`: `event_id, sale_source, sale_contracted, sale_received, sale_receivable, sale_deductions, labor_contracted, labor_paid, labor_payable, unknown_labor_count, other_contracted, other_paid, other_payable, unknown_expense_count, estimated_result, result_label, expenses`. Accepted commercial contract plus actual `customer_receipts` supplies sale/received/receivable. Without a linked accepted contract, legacy `event_financials.gross_amount` supplies **contracted sale only** (`sale_source='legacy_contracted_gross'`), with received/receivable null. No sale source returns null. Labor comes from latest explicitly accepted terms or untouched legacy agreement/payment totals; an unaccepted unknown offer prevents a known contracted/payable result. Paid labor is actual paid evidence. Other contracted costs combine expense ledger and separately retained legacy extras; legacy extras have no payment source, so other paid/payable remain unknown if extras exist. Unknown expense amounts make contracted/payable/result null. Expenses return `{id,label,amount,receipt_reference,paid}` to finance only. Idempotent expense settlements and customer receipts are independent ledgers.

Estimated result = contracted sale − accepted/legacy labor − other contracted costs − recorded legacy sale deductions. Label is always `estimated_before_unresolved_expenses_and_taxes`; it is not asserted to be profit/net revenue. The legacy `businessRevenue` keeps previous `grossRevenue/netRevenue` calculations for compatibility, and adds canonical `contractedSale`, `receivedSale:null`, `receivableSale:null`, `estimatedResult`, `resultLabel`. Canonical estimate/sale stay unknown for an incomplete period; the previous partial gross remains available alongside missing-record IDs.

All DATE values (`valid_until`, `received_on`, `paid_on`, event-date-only fields) remain ISO dates without conversion to UTC days. SQL validity/future-date limits use `private.eventcore_business_today()` in `America/Sao_Paulo`; client date limits use existing `revenueDateKey/currentRevenuePeriod`. The fixed regression `2026-10-07T00:54Z → 2026-10-06` passes. A quote valid on that Brazilian day can save/submit/accept even after UTC midnight. No stored DATE values are rewritten.

Actual worker history requires an ended completed event plus validated recorded check-in/out (ordered timestamps, validator/time) **or explicit confirmation by the actual linked worker**. A preservation exception admits a completed legacy event with NULL scheduled end only when origin remains NULL, the assignment has no new terms and is checked out, scheduled start is past, and actual ordered validated check-out is past. It retains the unknown scheduled end and valid prior reviews, with actual attendance supplying punctuality; new-work origin/new assignment terms never qualify for this exception. Invitation/availability/registration/base/team membership alone provides no actual-work evidence. Punctuality uses validated actual attendance only; participant confirmation does not fabricate a timestamp. Worker rows have `{freelancer_id,full_name,city,job_count,average_stars,review_count,punctuality,punctuality_count}`. Jobs count distinct actual events; punctuality is percent on-time against the frozen event tolerance. Null stars/punctuality mean no evidence. Sort descending punctuality NULLS LAST, average stars NULLS LAST, real job count, then ascending name/id.

Buyer provider histories require actual buyer confirmation of an ended completed linked contract. Rows have `{organization_id,display_name,job_count,average_stars,review_count}`; sort descending average stars NULLS LAST, review count, real job count, then ascending display name/id. External customers without accounts are not fabricated as buyer participants/reviewers. Existing valid worker rating rows and uniqueness are retained; worker/provider rating evidence cannot be edited/deleted. Self-review and provider-member/owner buyer review are denied even for dual-role accounts.

`BuyerWorkStatus` contains `{contract_id,sale_total,quote,received_total,work}`; `work` is null or `{event_id,name,venue,start_at,end_at,status,completion_confirmed}`. It never returns freelancer identity/rates/costs/expenses. `ProviderPresentation` contains `{id,display_name,organization_type,bio,specialties,average_stars,review_count,job_count}` only; eligible presentation requires the actual buyer request/contract or own provider membership. No owner documents, contacts, private sales or wage fields are present.

Worker reputation/photo lookup now requires own identity or a canonical operating/finance event relationship, rather than generic staff/business status or base membership. Reputation returns only reviews from the caller’s actual authorized event scope (or own worker history). Existing uploads, declaration/quota, private bucket and cleanup infrastructure are unchanged. `GET /api/profile/photos?organization_id=UUID` adds scoped provider avatar/portfolio access to the existing authenticated signing path; `freelancer_id`/own-profile behavior is retained. Mixed organization/freelancer IDs or malformed IDs reject404. SQL authorizes first; the service signer signs only the returned stored paths, expiring in1,200 seconds, with private/no-store responses.

## Task 2 validation and additive recovery

Fresh continuation validation on 2026-10-06: disposable PostgreSQL 17.5 applies 31 migrations. Original continuation `workflows-security.sql` passed 212 statements; fix-round1 passes 220, including the NULL-end legacy evidence matrix. The before/after preservation regression applies 30 prior migrations, accepts the actual pre-Task2 rating (before fixture 25 statements), applies Task2 (108 statements), then verifies preserved authorized reviews/independent metrics and unchanged evidence (after fixture 21 statements), finally rolling back. The regression fails against the pre-fix Task2 predicate. Original continuation commercial 176, photo 8, read 8 also roll back; focused unit suite 28/28, full suite 44/44 and typecheck passed then and were not repeated for the SQL-only fix. Workflow SQL asserts exact assignment/terms/opportunity/finance/people/history/presentation/buyer DTO keys as well as expense idempotency and unknown expenses; portfolio tests execute actual handler/signing code with mocked external auth/storage boundaries. No hosted DDL/JWT/PostgREST, live Storage, Calendar call, browser baseline rerun, deployment or messages occurred in Task 2. Controller performs hosted ACL/advisor/JWT evidence after compatible UI review. Full command/results and recovery are recorded in `.superpowers/sdd/2026-10-05-aligned-flows/task-2-report.md`.

Before hosted application, preserve actual prior function definitions/policies/ACLs and row/count/hash baselines. Apply only after Task3 reads accepted-term payroll/finance DTOs and respects creation-only/closed-event errors. Old assignment amount forms and raw new-payroll table assumptions are incompatible with these strengthened rules.

Recovery: disable new workflow UI and revoke authenticated EXECUTE on new mutating work/base/team/terms/expense/completion/review/publication RPCs. Retain append-only terms, acceptances, payments, confirmations/ratings, columns, and tighter ownership/finance/photo restrictions. Do not drop evidence or recalculate historical totals. A reviewed additive recovery migration may restore individually saved compatible old function definitions/ACLs; restoring old unrestricted amount setters, service edits/deletion, broad staff portfolios or cross-tenant finance is not safe rollback. Keep `a_workflow_*` evidence/creation guards and immutable evidence triggers. If quote functions need restoration, keep Brazilian-date validity or explicitly review the UTC-midnight regression. Creation RPC and its private session guard must be restored together; removing a guard alone does not repair revoked ACLs.

## Task 3 fix round 1 — independent work-finance discovery

Migration `20261006203715_eventcore_work_finance_index.sql` adds read-only `get_work_finance_index() → jsonb`, typed as `WorkFinanceIndex[]` and exposed by caller-session `workflowApi(db).financeIndex()`. Each row has exactly `{event_id, event_name, organization_id}`; rows sort by private stored `start_at`, then ID, without projecting dates, address, client, assignments, remuneration or financial values. Empty authorization returns `[]`. The existing `private.eventcore_can_finance_event` is the sole per-row predicate, preserving active-actor/active-organization, independent active finance membership, provider/unclassified compatibility and own NULL-organization legacy creator rules. It never assigns historical ownership. Only authenticated has EXECUTE; anon/PUBLIC do not.

The page loads this index independently from `events` RLS/`get_event_operations`, then calls unchanged `get_work_finance` for each authorized ID. Finance-only members can reach their selected organization's finance panels without operations access; operation-specific remuneration DTOs remain fetched only for finance-authorized operations already accessible. Workers retain their own assignment/payment projection; buyers retain their separate commercial interface. No operational RLS, financial calculation, existing RPC or historic row changes.

Recovery: disable dependent finance discovery UI, then revoke authenticated EXECUTE on `get_work_finance_index()`. Preserve every row and existing ACL/RLS/helper. A reviewed additive migration may drop the read-only index after callers stop using it. Hosted migration/ACL/JWT/PostgREST validation remains a controller gate before activating this UI contract.
