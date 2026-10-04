# EventCore adaptive update

User authorization: continue the update shown in the attached video using maximum available effort. Existing GitHub, Vercel, Supabase, Auth, RLS, Google Calendar, PWA, domain and user data are authoritative and must be preserved.

## Required behavior

- Four profiles: freelancer, team lead, company and agency. Existing accounts complete their profile without registering again. Signup collects account details and guides profile completion; private CPF/CNPJ never appears in a professional directory.
- Database specialties remain extensible. Organization name/category and membership connect business profiles to their operations.
- Central capabilities control navigation and actions. Início and Dashboard are separate adjacent entries. Freelancers have opportunities, applications, their schedule, earnings and reputation; business profiles also have clients, teams and their events.
- Events support Meus eventos and Oportunidades for business profiles; freelancer opportunities match specialties. Publish requirements, date/time, venue, vacancies, compensation and contractor identity, while keeping client details and internal notes private.
- Application, selection, hiring, attendance and payment have valid state transitions. Hiring and related financial records are atomic, capacity is enforced and identity fields cannot be forged.
- Dashboards use real records: monthly paid earnings, upcoming contracted income, applications and valid hire rate, completed jobs, review average/count; business event/vacancy/cost/client metrics. Empty states describe missing data without fabricated values.
- One rating from 1–5 per completed assignment, optional comment, associated with the actual freelancer, event and contractor; reputation aggregates actual ratings and completed jobs.
- Existing administration, client/event/service forms, finance, attendance, Google connect/sync/disconnect and PWA remain available. Auth surfaces use moderate 8–12px corners and responsive layout.

## Completion evidence

Domain logic tests, a successful production build, rollback-only database flow/permission tests, desktop/mobile browser checks, successful preview and production deployment, official domain verification. Authenticated Google synchronization is only claimed when exercised with an authorized existing account; preserve its code and configuration otherwise and report the verification limit.
