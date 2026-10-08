# EventCore aligned flows — approved requirements, implementation contract

Authority: Douglas Cesar's approved requirements of 2026-10-05 in the execution conversation. This document records their technical interpretation; it is not a request for another product approval.

## Existing system and preservation

Use the existing Next 15 / React 19 app, Supabase project `mzwlchgxkuqptiqyznqd`, repository `Mentecare/marujoeventos`, Vercel project `marujoeventos`, domain `eventcore.space`, authentication, Google Agenda integration, PWA and private profile-photo storage. Preserve the approved white/green interface, mobile navigation (Início, Dashboard, Clientes, Equipe, Eventos), working event details and profile galleries. Extend existing components rather than restart or replace the application.

At discovery the database has three events, four functions, three assignments, three payments, zero reviews/proposals/organizations and two profiles. All three historical events have no organization; one existing administrator has no private identity document. These are observations, not permission to assign a new meaning to these records. Recheck the baseline immediately before applying migrations; fixtures must roll back. Existing assignments, agreements, payment amounts and valid reviews are immutable historical evidence. Keep historical totals as totals; adding contracted days must never multiply old amounts.

## Business and authorization model

Agencies and scenography buyers request quotations and hire provider companies/teams. Providers alone publish freelancer opportunities, invite workers, assemble teams, negotiate conditions and record worker payments. Buyers cannot directly hire a freelancer, including through existing RPCs, raw PostgREST writes or forged identifiers. Business role must be explicit for new operations; historical unclassified organizations/events remain visibly unclassified until an authorized owner supplies classification.

Enforce tenant, contract and participant permissions in RLS, security-definer functions, application APIs and output DTOs. A generic administrator/coordinator role must not grant access to another organization's commercial records. Preserve the creator's access to historical unowned events. Coordinators can operate their authorized events but require explicit finance authorization for financial information.

Maintain independent sale prices and freelancer remuneration. Provider owners and finance-authorized staff see own sales, receipts, remuneration, other expenses, receivables/payables and estimated results. Buyers see only their own sale proposals/contracts/charges/payments. Workers see only their own agreed role/days/hours, daily/service remuneration, total, benefits, agreed additions/deductions and payments. Public profiles/opportunity previews expose no private contracts, documents, salaries, revenue or margin. The same restrictions apply to raw database access, exports, PDF generation, notifications and shared links.

Track sale contracted/received/receivable and costs contracted/paid/payable independently. Unknown amounts remain unknown. Sale minus labor and other known costs is an estimated result before unresolved expenses/taxes, not automatically net profit or net revenue. Acceptance example: 10 workers × 2 days × R$280 sale = R$5,600; 10 × 2 × R$220 remuneration = R$4,400; each worker R$440; difference R$1,200 before other costs/taxes.

## Work, identity and history

External work supports an external client with no account. Record origin (`platform`, `whatsapp`, `referral`, `other`, or historical unknown) independently from visibility. New work is private by default; individual opportunities become public only through an explicit publication choice. Configure functions, quantities, contracted days and initial remuneration conditions only in event creation. Keep company freelancer base, reusable habitual teams and actual job allocations separate. Inclusion in a base/team is not consent: private invitations require availability/acceptance; published opportunities require an application and authorized hire.

A single required field “CPF ou CNPJ” identifies business/team responsibles; CNPJ including MEI is recommended, CPF is permitted. Infer type from normalized valid input; support numeric and current alphanumeric CNPJ with official check-digit rules. Never label identity as verified merely because input is valid. Full CPF is private; existing undocumented accounts retain access/history and complement identification for new commercial operations. A document never grants reputation stars or punctuality.

Provider histories include workers that actually worked with that provider; buyer histories include providers that actually served that buyer. Confirmed completed work and recorded attendance underpin these histories. Rank workers by measured punctuality first, then average stars; providers by average stars. Show jobs/review counts, unknown metrics as “sem avaliações”/“sem registros”, separate punctuality and stars, document deterministic tie breaks. Do not synthesize historical punctuality. Reviews require a real confirmed completed hiring relationship, authorized reviewer and uniqueness; external jobs require actual participant confirmation.

## Notifications and sharing

Provide an in-app notification center, explicit opt-in Web Push device subscriptions and confirmed-address email, with relevant-profile/function/region/date matching, optional all eligible opportunities, immediate/daily cadence, channel choices and pause. Browsing all published opportunities is independent from alert preferences. Private work/invitations never produce general alerts. Use sanitized payloads and links to the actual opportunity/contract, durable deduplication, bounded sending, retry/backoff, stale vacancy suppression and expired-device handling. Push denial/unsupported platforms leave other channels and browsing usable. Do not ask push permission on install/signup. Current iPhone/iPad Web Push requires a supported home-screen web app and explicit interaction; show honest platform guidance.

Integrations must be real adapters; an absent email provider/verified sender is an explicit dependency, not a simulated send. Test only isolated recipients; do not mass-send during validation. Scheduler/worker secrets stay server-side. Public share/WhatsApp links show an authorized published preview only; protected operational detail still requires eligible authenticated access.

## Quotations and delivery

Reuse existing proposals/items and jobs for quotation fill → preview → authorized PDF download for platform/external work. Include issuer logo/name, necessary client identity, issue/validity dates, services/functions/worker counts/days, sale line totals/grand total/payment terms, discrete EventCore watermark on every page and footer “Orçamento emitido pelo EventCore” linking to the platform. Toggle sale unit prices vs totals-only changes presentation only. PDFs never contain freelancer wages, internal costs or margin, and guessed identifiers grant no access. Use Brazilian money/dates, readable mobile preview and correct long-document pagination.

Deliver additive compatible migrations, explicit recovery instructions, real server/UI flows and a verified homologation version with publication prepared. Do not silently reinterpret historical data, delete records, replace infrastructure or claim deployments/integrations/migrations that were not observed. Verify permissions directly with authenticated SQL/API fixtures, cross-organization isolation, totals, external privacy, document validation/history preservation, real histories, preferences/notification privacy, short/long PDFs and existing navigation/auth/integrations.

## Verified primary references

- Receita Federal CNPJ current rollout: https://www.gov.br/receitafederal/pt-br/acesso-a-informacao/acoes-e-programas/programas-e-atividades/cnpj-alfanumerico
- Receita Federal technical digit calculation: https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj
- Receita Federal alphanumeric FAQ: https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/perguntas-e-respostas/cnpj/cnpj-alfanumerico.pdf
- Apple/WebKit home-screen Web Push: https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/
- Supabase scheduling, pg_cron/pg_net and Vault: https://supabase.com/docs/guides/functions/schedule-functions

