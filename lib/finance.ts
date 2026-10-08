export type RevenuePeriod = { start: string; end: string };
export type EventFinancial = {
  event_id: string;
  gross_amount: number | null;
  deductions_amount: number;
  extra_costs_amount: number;
};
export type RevenueData = {
  events: { id: string; name?: string; start_at: string; status: string }[];
  services: { id: string; event_id: string }[];
  assignments: { id: string; event_service_id: string; status: string; agreed_amount?: number | null }[];
  payments: { assignment_id: string; amount: number; status: string }[];
  financials: EventFinancial[];
};

const dateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit',
});
export function revenueDateKey(value: string | Date) {
  const parts = Object.fromEntries(dateFormatter.formatToParts(new Date(value)).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function currentRevenuePeriod(now = new Date()): RevenuePeriod {
  const today = revenueDateKey(now);
  return { start: `${today.slice(0, 7)}-01`, end: today };
}

export function revenuePeriodError(period: RevenuePeriod, now = new Date()) {
  for (const value of [period.start, period.end]) {
    const date = new Date(`${value}T12:00:00Z`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
      return 'Informe duas datas válidas para o período.';
    }
  }
  if (period.start > period.end) return 'O início do período deve ser anterior ou igual ao término.';
  if (period.end > revenueDateKey(now)) return 'Selecione um período até hoje.';
  return null;
}

function cents(value: number | null | undefined): number | null {
  if (value == null || !Number.isFinite(Number(value)) || Number(value) < 0) return null;
  return Math.round((Number(value) + Number.EPSILON) * 100);
}

export function businessRevenue(data: RevenueData, period = currentRevenuePeriod(), now = new Date()) {
  const error = revenuePeriodError(period, now);
  if (error) throw new RangeError(error);
  const events = data.events.filter(event => {
    const day = revenueDateKey(event.start_at);
    return event.status !== 'cancelled' && day >= period.start && day <= period.end;
  });
  const financials = new Map(data.financials.map(row => [row.event_id, row]));
  const serviceEvents = new Map(data.services.map(service => [service.id, service.event_id]));
  const payments = new Map(data.payments.map(payment => [payment.assignment_id, payment]));
  const eventCosts = new Map<string, number>();
  const unknownCosts = new Set<string>();
  for (const assignment of data.assignments) {
    const eventId = serviceEvents.get(assignment.event_service_id);
    if (!eventId) continue;
    const payment = payments.get(assignment.id);
    if (assignment.status === 'reserve' && payment?.status !== 'paid') continue;
    // An actual paid record survives cancellation; a cancelled payment is never revived.
    if (payment?.status === 'cancelled') continue;
    if (!payment && ['cancelled', 'reserve'].includes(assignment.status)) continue;
    const amount = cents(payment ? payment.amount : assignment.agreed_amount);
    if (amount == null) unknownCosts.add(eventId);
    else eventCosts.set(eventId, (eventCosts.get(eventId) ?? 0) + amount);
  }

  let gross = 0, deductions = 0, extras = 0, costs = 0, recordedEventCount = 0;
  const missingEventIds: string[] = [], missingCostEventIds: string[] = [];
  for (const event of events) {
    const row = financials.get(event.id);
    const amount = cents(row?.gross_amount);
    if (amount == null) { missingEventIds.push(event.id); continue; }
    recordedEventCount++;
    gross += amount;
    deductions += cents(row?.deductions_amount) ?? 0;
    extras += cents(row?.extra_costs_amount) ?? 0;
    costs += eventCosts.get(event.id) ?? 0;
    if (unknownCosts.has(event.id)) missingCostEventIds.push(event.id);
  }
  const hasValues = recordedEventCount > 0 || events.length === 0;
  return {
    // Historical gross is contracted sale; there is no receipt source in this DTO.
    contractedSale: hasValues && missingEventIds.length === 0 ? gross / 100 : null,
    receivedSale: null,
    receivableSale: null,
    estimatedResult: hasValues && missingEventIds.length === 0 && missingCostEventIds.length === 0 ? (gross - deductions - extras - costs) / 100 : null,
    resultLabel: 'estimated_before_unresolved_expenses_and_taxes' as const,
    grossRevenue: hasValues ? gross / 100 : null,
    netRevenue: hasValues && missingCostEventIds.length === 0 ? (gross - deductions - extras - costs) / 100 : null,
    teamCosts: costs / 100,
    deductions: deductions / 100,
    extraCosts: extras / 100,
    eventCount: events.length,
    recordedEventCount,
    missingEventIds,
    missingCostEventIds,
  };
}
