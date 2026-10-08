import type { SupabaseClient } from '@supabase/supabase-js';
import type { EventCreationInput } from './event-creation.ts';

export type MarketRole = 'provider' | 'buyer' | 'unclassified';
export type BuyerSubtype = 'agency' | 'scenography';
export type BusinessIdentityInput = { organization_id?: string; display_name: string; organization_type: 'team' | 'company' | 'agency'; market_role: Exclude<MarketRole, 'unclassified'>; buyer_subtype?: BuyerSubtype | null; document: string };
export type CommercialOrganization = { id: string; display_name: string; organization_type: string; market_role: MarketRole; buyer_subtype: BuyerSubtype | null; is_owner: boolean; can_operate: boolean; can_finance: boolean };
export type CommercialContext = { profile_id: string; identity_complete: boolean; document_type: 'cpf' | 'cnpj' | null; document_last4: string | null; organizations: CommercialOrganization[] };
export type ProviderSummary = { id: string; display_name: string; organization_type: string; specialties: string[] };
export type SaleLineInput = { label: string; service_type?: 'loader' | 'security' | 'waiter' | 'other'; quantity: number; contract_days: number; client_unit_price: number; planned_hours?: number | null; freelancer_unit_cost?: number | null };
export type SaleQuoteInput = { id?: string; expected_revision?: number; organization_id: string; request_id?: string | null; client_id?: string | null; title: string; event_date?: string | null; venue?: string | null; valid_until: string; payment_terms: string; show_unit_prices: boolean };
/** Deliberately sale-only, including for provider callers/PDF. Do not add internal fields. */
export type SaleQuoteDTO = {
  id: string; revision: number; status: 'draft' | 'sent' | 'accepted' | 'rejected' | 'cancelled';
  title: string; issued_at: string; event_date: string | null; venue: string | null; valid_until: string | null;
  payment_terms: string | null; show_unit_prices: boolean; client_total: number;
  issuer: { id: string | null; display_name: string }; client: { display_name: string };
  request_id: string | null; contract_id: string | null;
  items: { id: string; label: string; quantity: number; contract_days: number; planned_hours: number | null; client_unit_price: number; line_total: number }[];
};
export type ContractRequest = { id: string; provider_organization_id: string; buyer_organization_id: string; title: string; description: string; created_by: string; event_date: string | null; venue: string | null; status: 'requested' | 'quoted' | 'contracted' | 'cancelled'; created_at: string };
export type CommercialContract = { id: string; proposal_id: string; request_id: string | null; client_id: string; accepted_by: string; provider_organization_id: string; buyer_organization_id: string | null; sale_total: number; quote_snapshot: SaleQuoteDTO; accepted_at: string; acceptance_method: 'platform' | 'external_recorded'; received_total: number; receivable_total: number };
export type CustomerReceipt = { id: string; contract_id: string; amount: number; method: 'pix' | 'transfer' | 'cash' | 'other'; received_on: string; created_at: string };
export type CommercialWorkspace = { requests: ContractRequest[]; quotes: SaleQuoteDTO[]; contracts: CommercialContract[]; receipts: CustomerReceipt[] };

export function saleLineTotal(line: Pick<SaleLineInput, 'quantity' | 'contract_days' | 'client_unit_price'>): number {
  const { quantity, contract_days, client_unit_price } = line;
  const cents = Math.round(client_unit_price * 100);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 10000 || !Number.isSafeInteger(contract_days) || contract_days < 1 || contract_days > 366 || !Number.isFinite(client_unit_price) || client_unit_price < 0 || Math.abs(cents / 100 - client_unit_price) > 1e-9) throw new Error('invalid_quote_item');
  const totalCents = cents * quantity * contract_days;
  if (!Number.isSafeInteger(totalCents) || totalCents > 999999999999) throw new Error('invalid_quote_total');
  return totalCents / 100;
}

async function rpc<T>(db: SupabaseClient, name: string, args?: Record<string, unknown>): Promise<T> {
  const result = await db.rpc(name, args);
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
}
/** Pass a browser authenticated client or commercialActor().db, never a service client. */
export function commercialApi(db: SupabaseClient) {
  return {
    context: () => rpc<CommercialContext>(db, 'get_commercial_context'),
    configureBusiness: (input: BusinessIdentityInput) => rpc<string>(db, 'configure_business_identity', { p_payload: input }),
    setFinanceMember: (organizationId: string, profileId: string, enabled: boolean) => rpc<void>(db, 'set_organization_finance_member', { p_organization_id: organizationId, p_profile_id: profileId, p_enabled: enabled }),
    canFinanceEvent: (eventId: string) => rpc<boolean>(db, 'can_finance_event', { p_event_id: eventId }),
    providers: () => rpc<ProviderSummary[]>(db, 'list_commercial_providers'),
    workspace: (organizationId: string) => rpc<CommercialWorkspace>(db, 'get_commercial_workspace', { p_organization_id: organizationId }),
    request: (buyerId: string, providerId: string, title: string, description: string, eventDate: string | null, venue: string | null) => rpc<string>(db, 'create_contract_request', { p_buyer_organization_id: buyerId, p_provider_organization_id: providerId, p_title: title, p_description: description, p_event_date: eventDate, p_venue: venue }),
    saveQuote: (quote: SaleQuoteInput, items: SaleLineInput[]) => rpc<string>(db, 'save_sale_quote', { p_quote: quote, p_items: items }),
    quote: (id: string) => rpc<SaleQuoteDTO>(db, 'get_sale_quote', { p_proposal_id: id }),
    submitQuote: (id: string, revision: number) => rpc<void>(db, 'submit_sale_quote', { p_proposal_id: id, p_expected_revision: revision }),
    acceptQuote: (id: string, revision: number, externalEvidence: string | null = null) => rpc<string>(db, 'accept_sale_quote', { p_proposal_id: id, p_expected_revision: revision, p_external_evidence: externalEvidence }),
    recordReceipt: (contractId: string, amount: number, method: CustomerReceipt['method'], receivedOn: string, idempotencyKey: string) => rpc<string>(db, 'record_customer_receipt', { p_contract_id: contractId, p_amount: amount, p_method: method, p_received_on: receivedOn, p_idempotency_key: idempotencyKey }),
  };
}

/** Operational rows deliberately omit wages; fetch finances only after can_finance. */
export type EventOperations = {
  event: { id: string; name: string; organization_id: string | null; status: string; start_at: string; end_at: string | null; venue: string; arrival_tolerance_minutes: number };
  can_finance: boolean;
  /** Effective hire permission includes finance and an event that is not completed/cancelled. */
  can_hire: boolean;
  services: { id: string; event_id: string; label: string; service_type: string; specialty_id: string | null; quantity_needed: number; reserve_target: number; contract_days: number | null; planned_hours: number | null; briefing: string | null; requirements: string | null; visibility: 'open' | 'private'; application_enabled: boolean }[];
  assignments: { id: string; event_service_id: string; freelancer_id: string; status: string }[];
};
export function getEventOperations(db: SupabaseClient, eventId: string) {
  return rpc<EventOperations>(db, 'get_event_operations', { p_event_id: eventId });
}

/** Existing own-worker RPC; agreed amounts/payments remain RLS-filtered to their own rows. */
export type WorkerSchedule = {
  events: { id: string; name: string; venue: string; start_at: string; end_at: string | null; status: string; arrival_tolerance_minutes: number }[];
  services: { id: string; event_id: string; label: string; service_type: string; specialty_id: string | null; quantity_needed: number; reserve_target: number; briefing: string | null; contract_days: number | null; visibility: 'open' | 'private'; application_enabled: boolean }[];
};
export function getWorkerSchedule(db: SupabaseClient) {
  return rpc<WorkerSchedule>(db, 'get_my_schedule');
}

export type WorkOrigin = 'platform' | 'whatsapp' | 'referral' | 'other';
export type RemunerationInput = { basis: 'daily' | 'service'; rate: number; contract_days: number | null; planned_hours?: number | null; benefits?: string | null; additions?: number; deductions?: number };
/** SQL projections always supply every key, including null unknown amounts. */
export type WorkRemuneration = { basis: 'daily' | 'service'; rate: number | null; contract_days: number | null; planned_hours: number | null; benefits: string | null; additions: number; deductions: number; total: number | null };
export type AssignmentTerms = WorkRemuneration & { id: string; assignment_id: string; revision: number; created_at: string; accepted_at: string | null };
/** Creation returns finance-authorized database rows; subsequent reads use scoped DTOs. */
export type CreatedWork = {
  event: EventOperations['event'] & { client_id: string; origin: WorkOrigin; commercial_contract_id: string | null; public_region: string | null; notes: string | null };
  services: (EventOperations['services'][number] & { freelancer_unit_cost: number | null; remuneration_basis: 'daily' | 'service' | null; remuneration_rate: number | null; benefits: string | null; additions: number; deductions: number; public_description: string | null })[];
};
export type WorkerWorkAssignment = {
  id: string; freelancer_id: string; event_service_id: string; event_id: string; event_name: string; venue: string; start_at: string; end_at: string | null;
  event_status: string; status: string; function_name: string; legacy_agreed_amount: number | null;
  offered_terms: AssignmentTerms | null; accepted_terms: AssignmentTerms | null; terms_history: AssignmentTerms[];
  payments: { id: string; amount: number; status: string; method: string | null; paid_at: string | null; term_id: string | null }[];
  worker_name?: string; can_review?: boolean;
  completion_confirmed: boolean;
};
export type WorkOpportunity = { service_id: string; event_id: string; event_name: string; start_at: string; end_at: string | null; venue: string; function_name: string; specialty_id: string | null; vacancies: number; amount: number | null; contractor_name: string; requirements: string | null; event_status: string; compatible: boolean; contract_days: number | null; remuneration: (Omit<WorkRemuneration, 'benefits'> & { benefits: null }) | null };
export type ProviderPeople = { base: { freelancer_id: string; full_name: string; city: string | null; active: boolean }[]; teams: { id: string; name: string; freelancer_ids: string[] }[] };
export type WorkerHistory = { freelancer_id: string; full_name: string; city: string | null; job_count: number; average_stars: number | null; review_count: number; punctuality: number | null; punctuality_count: number };
export type ProviderHistory = { organization_id: string; display_name: string; job_count: number; average_stars: number | null; review_count: number };
export type ProviderPresentation = { id: string; display_name: string; organization_type: string; bio: string | null; specialties: string[]; average_stars: number | null; review_count: number; job_count: number };
export type BuyerWorkStatus = { contract_id: string; sale_total: number; quote: SaleQuoteDTO; received_total: number; work: { event_id: string; name: string; venue: string; start_at: string; end_at: string | null; status: string; completion_confirmed: boolean; reviewed?: boolean; can_confirm?: boolean } | null };
/** Minimal discovery projection; finance membership does not imply operations access. */
export type WorkFinanceIndex = { event_id: string; event_name: string; organization_id: string | null };
export type WorkFinance = {
  event_id: string; sale_source: 'accepted_contract' | 'legacy_contracted_gross' | 'recorded_sale' | 'unknown';
  sale_contracted: number | null; sale_received: number | null; sale_receivable: number | null; sale_deductions: number;
  labor_contracted: number | null; labor_paid: number; labor_payable: number | null; unknown_labor_count: number;
  other_contracted: number | null; other_paid: number | null; other_payable: number | null; unknown_expense_count: number;
  estimated_result: number | null; result_label: 'estimated_before_unresolved_expenses_and_taxes';
  expenses: { id: string; label: string; amount: number | null; receipt_reference: string | null; paid: number }[];
};

/** A legacy cost is already a total. Apply daily multiplication only with an explicit basis. */
export function remunerationTotal(terms: RemunerationInput): number {
  const centValue = (value: number) => {
    const cents = Math.round(value * 100);
    if (!Number.isFinite(value) || value < 0 || value > 9999999999.99 || !Number.isSafeInteger(cents) || Math.abs(cents / 100 - value) > 1e-9) throw new Error('invalid_remuneration');
    return cents;
  };
  if (!['daily', 'service'].includes(terms.basis) || (terms.basis === 'daily' && (!Number.isSafeInteger(terms.contract_days) || terms.contract_days! < 1 || terms.contract_days! > 2147483647))) throw new Error('invalid_remuneration');
  const total = centValue(terms.rate) * (terms.basis === 'daily' ? terms.contract_days! : 1) + centValue(terms.additions ?? 0) - centValue(terms.deductions ?? 0);
  if (!Number.isSafeInteger(total) || total < 0 || total > 999999999999) throw new Error('invalid_remuneration');
  return total / 100;
}

/** Use the authenticated caller client; SQL owns tenancy, acceptance and evidence rules. */
export function workflowApi(db: SupabaseClient) {
  return {
    createWork: (event: EventCreationInput['event'], services: EventCreationInput['services']) => rpc<CreatedWork>(db, 'create_event_with_services', { p_event: event, p_services: services }),
    createExternalClient: (organizationId: string, name: string) => rpc<string>(db, 'create_external_work_client', { p_organization_id: organizationId, p_name: name }),
    proposeTerms: (assignmentId: string, terms: RemunerationInput) => rpc<string>(db, 'propose_assignment_terms', { p_assignment_id: assignmentId, p_terms: terms }),
    acceptTerms: (termId: string) => rpc<void>(db, 'accept_assignment_terms', { p_term_id: termId }),
    respond: (assignmentId: string, status: 'confirmed' | 'cancelled') => rpc<void>(db, 'respond_to_assignment', { p_assignment_id: assignmentId, p_status: status }),
    pay: (assignmentId: string, method: CustomerReceipt['method']) => rpc<void>(db, 'mark_assignment_paid', { p_assignment_id: assignmentId, p_method: method }),
    people: (organizationId: string) => rpc<ProviderPeople>(db, 'get_provider_people', { p_organization_id: organizationId }),
    setBaseMember: (organizationId: string, freelancerId: string, enabled: boolean) => rpc<void>(db, 'set_provider_base_member', { p_organization_id: organizationId, p_freelancer_id: freelancerId, p_enabled: enabled }),
    saveTeam: (organizationId: string, teamId: string | null, name: string) => rpc<string>(db, 'save_provider_team', { p_organization_id: organizationId, p_team_id: teamId, p_name: name }),
    deleteTeam: (teamId: string) => rpc<void>(db, 'delete_provider_team', { p_team_id: teamId }),
    setTeamMember: (teamId: string, freelancerId: string, enabled: boolean) => rpc<void>(db, 'set_provider_team_member', { p_team_id: teamId, p_freelancer_id: freelancerId, p_enabled: enabled }),
    inviteSelected: (serviceId: string, freelancerIds: string[]) => rpc<string[]>(db, 'invite_selected_workers', { p_service_id: serviceId, p_freelancer_ids: freelancerIds }),
    createAssignment: (serviceId: string, freelancerId: string, status: 'invited' | 'reserve' = 'invited') => rpc<string>(db, 'create_event_assignment', { p_service_id: serviceId, p_freelancer_id: freelancerId, p_status: status }),
    applyOpportunity: (serviceId: string, message: string | null = null) => rpc<string>(db, 'apply_for_opportunity', { p_service_id: serviceId, p_message: message }),
    hireApplication: (applicationId: string) => rpc<string>(db, 'hire_application', { p_application_id: applicationId }),
    recordAttendance: (assignmentId: string, kind: 'in' | 'out', latitude: number, longitude: number) => rpc<void>(db, 'record_assignment_attendance', { p_assignment_id: assignmentId, p_kind: kind, p_lat: latitude, p_lng: longitude }),
    validateAttendance: (assignmentId: string) => rpc<void>(db, 'validate_assignment_attendance', { p_assignment_id: assignmentId }),
    publishFunction: (serviceId: string, published: boolean) => rpc<void>(db, 'publish_work_function', { p_service_id: serviceId, p_published: published }),
    opportunities: () => rpc<WorkOpportunity[]>(db, 'get_work_opportunities'),
    workerAssignments: () => rpc<WorkerWorkAssignment[]>(db, 'get_my_work_assignments'),
    eventRemunerations: (eventId: string) => rpc<WorkerWorkAssignment[]>(db, 'get_event_remunerations', { p_event_id: eventId }),
    financeIndex: () => rpc<WorkFinanceIndex[]>(db, 'get_work_finance_index'),
    finance: (eventId: string) => rpc<WorkFinance>(db, 'get_work_finance', { p_event_id: eventId }),
    resolveExpense: (expenseId:string,amount:number,reference:string)=>rpc<string>(db,'resolve_work_expense',{p_expense_id:expenseId,p_amount:amount,p_evidence_reference:reference}),
    recordSale: (eventId:string,amount:number,reference:string)=>rpc<string>(db,'record_work_sale',{p_event_id:eventId,p_amount:amount,p_evidence_reference:reference}),
    linkSaleContract: (eventId:string,contractId:string)=>rpc<void>(db,'link_work_sale_contract',{p_event_id:eventId,p_contract_id:contractId}),
    recordSaleReceipt: (eventId:string,amount:number,method:CustomerReceipt['method'],date:string,key:string)=>rpc<string>(db,'record_work_sale_receipt',{p_event_id:eventId,p_amount:amount,p_method:method,p_received_on:date,p_idempotency_key:key}),
    recordExpense: (eventId: string, label: string, amount: number | null, receiptReference: string | null = null) => rpc<string>(db, 'record_work_expense', { p_event_id: eventId, p_label: label, p_amount: amount, p_receipt_reference: receiptReference }),
    payExpense: (expenseId: string, amount: number, method: CustomerReceipt['method'], paidOn: string, idempotencyKey: string) => rpc<string>(db, 'record_work_expense_payment', { p_expense_id: expenseId, p_amount: amount, p_method: method, p_paid_on: paidOn, p_idempotency_key: idempotencyKey }),
    completeEvent: (eventId: string) => rpc<void>(db, 'complete_work_event', { p_event_id: eventId }),
    confirmWorkerCompletion: (assignmentId: string) => rpc<void>(db, 'confirm_assignment_completion', { p_assignment_id: assignmentId }),
    confirmContractCompletion: (contractId: string) => rpc<void>(db, 'confirm_contract_completion', { p_contract_id: contractId }),
    rateWorker: (assignmentId: string, rating: number, comment: string | null = null) => rpc<string>(db, 'submit_assignment_rating', { p_assignment_id: assignmentId, p_rating: rating, p_comment: comment }),
    rateProvider: (contractId: string, rating: number, comment: string | null = null) => rpc<string>(db, 'submit_provider_rating', { p_contract_id: contractId, p_rating: rating, p_comment: comment }),
    workerHistory: (organizationId: string) => rpc<WorkerHistory[]>(db, 'get_provider_worker_history', { p_organization_id: organizationId }),
    providerHistory: (organizationId: string) => rpc<ProviderHistory[]>(db, 'get_buyer_provider_history', { p_organization_id: organizationId }),
    buyerWork: (contractId: string) => rpc<BuyerWorkStatus>(db, 'get_buyer_work_status', { p_contract_id: contractId }),
    providerPresentation: (organizationId: string) => rpc<ProviderPresentation>(db, 'get_provider_presentation', { p_organization_id: organizationId }),
  };
}
