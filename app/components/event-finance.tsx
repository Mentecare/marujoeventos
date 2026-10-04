"use client";

import { type FormEvent, useState } from "react";
import { businessRevenue, currentRevenuePeriod, revenueDateKey, revenuePeriodError, type EventFinancial, type RevenueData, type RevenuePeriod } from "@/lib/finance";

function brl(value: number | null) {
  return value == null ? "—" : value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}
function dateLabel(value: string) { return value.split("-").reverse().join("/"); }

export function RevenueDashboard({ data, period, loaded, loading, onPeriodChange, onOpenEvent }: {
  data: RevenueData;
  period: RevenuePeriod;
  loaded: boolean;
  loading: boolean;
  onPeriodChange: (period: RevenuePeriod) => void;
  onOpenEvent: (id: string) => void;
}) {
  const [draft, setDraft] = useState(period);
  const [error, setError] = useState("");
  const revenue = loaded ? businessRevenue(data, period) : null;
  const today = revenueDateKey(new Date());
  function apply(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const invalid = revenuePeriodError(draft);
    setError(invalid ?? "");
    if (!invalid) onPeriodChange(draft);
  }
  function reset() {
    const current = currentRevenuePeriod();
    setDraft(current); setError(""); onPeriodChange(current);
  }
  function eventName(id: string) { return data.events.find(event => event.id === id)?.name ?? "Evento"; }
  if (!revenue) return <section className="panel revenuePanel" aria-labelledby="revenue-title"><h2 id="revenue-title">Receitas</h2><p className="subtle" role="status">{loading ? "Atualizando receitas…" : "Receitas indisponíveis. Use Atualizar para carregar os valores."}</p></section>;
  return <section className="panel revenuePanel" aria-labelledby="revenue-title">
    <div className="sectionHead"><div><h2 id="revenue-title">Receitas</h2><p className="subtle">{dateLabel(period.start)} a {dateLabel(period.end)} · pela data do evento</p></div></div>
    <form className="form revenueFilters" onSubmit={apply}>
      <label>Início do período<input className="input" type="date" required max={today} value={draft.start} onChange={event => setDraft({ ...draft, start: event.target.value })}/></label>
      <label>Fim do período<input className="input" type="date" required min={draft.start || undefined} max={today} value={draft.end} onChange={event => setDraft({ ...draft, end: event.target.value })}/></label>
      <button className="btn" type="submit">Aplicar período</button>
      <button className="btn secondary" type="button" onClick={reset}>Mês atual</button>
    </form>
    {error && <p className="error" role="alert">{error}</p>}
    <div className="metrics revenueMetrics" aria-live="polite">
      <div className="metric"><span>Receita bruta</span><strong>{brl(revenue.grossRevenue)}</strong><small>{revenue.recordedEventCount} {revenue.recordedEventCount === 1 ? "evento com valor informado" : "eventos com valor informado"}</small></div>
      <div className="metric"><span>Receita líquida</span><strong>{brl(revenue.netRevenue)}</strong><small>{revenue.missingCostEventIds.length ? "Há custos a confirmar" : "Após custos e deduções registrados"}</small></div>
    </div>
    <p className="subtle revenueExplanation">Líquida = bruta − equipe ({brl(revenue.teamCosts)}) − despesas extras ({brl(revenue.extraCosts)}) − impostos e descontos ({brl(revenue.deductions)}). Eventos cancelados não entram.</p>
    {revenue.missingEventIds.length > 0 && <div className="revenuePending" role="status"><p>{revenue.recordedEventCount ? "Totais parciais. " : "Receitas aguardando valores. "}{revenue.missingEventIds.length} {revenue.missingEventIds.length === 1 ? "evento sem valor cobrado não foi incluído" : "eventos sem valor cobrado não foram incluídos"}. Informe os valores em Eventos → Pagamentos.</p><div className="actions">{revenue.missingEventIds.slice(0, 5).map(id => <button className="btn secondary" type="button" key={id} onClick={() => onOpenEvent(id)}>Informar valores: {eventName(id)}</button>)}</div></div>}
    {revenue.missingCostEventIds.length > 0 && <div className="revenuePending" role="status"><p>Confirme os valores das contratações para calcular a receita líquida.</p><div className="actions">{revenue.missingCostEventIds.slice(0, 5).map(id => <button className="btn secondary" type="button" key={id} onClick={() => onOpenEvent(id)}>Conferir custos: {eventName(id)}</button>)}</div></div>}
  </section>;
}

export function AssignmentCostForm({ assignmentId, amount, busy, onSave }: {
  assignmentId: string;
  amount: number | null;
  busy: boolean;
  onSave: (assignmentId: string, amount: number) => Promise<void>;
}) {
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const fields = new FormData(event.currentTarget);
    await onSave(assignmentId, Number(fields.get("amount")));
  }
  return <form className="form assignmentCostForm" onSubmit={submit}>
    <label>Valor contratado (R$)<input className="input" name="amount" type="number" inputMode="decimal" min={0} max={9999999999.99} step="0.01" required defaultValue={amount ?? ""}/></label>
    <button className="btn secondary" disabled={busy}>Salvar valor</button>
  </form>;
}

export function EventFinancialForm({ eventId, financial, busy, onSave }: {
  eventId: string;
  financial?: EventFinancial;
  busy: boolean;
  onSave: (financial: EventFinancial) => Promise<void>;
}) {
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const fields = new FormData(event.currentTarget);
    await onSave({ event_id: eventId, gross_amount: Number(fields.get("gross_amount")), deductions_amount: Number(fields.get("deductions_amount") || 0), extra_costs_amount: Number(fields.get("extra_costs_amount") || 0) });
  }
  return <form className="panel form" onSubmit={submit}>
    <h3>Receita do evento</h3>
    <p className="subtle">Informe o total cobrado ao cliente. Os pagamentos à equipe entram automaticamente como custos, inclusive os ainda pendentes.</p>
    <label>Valor cobrado ao cliente (R$)<input className="input" name="gross_amount" type="number" inputMode="decimal" min={0} max={9999999999.99} step="0.01" required defaultValue={financial?.gross_amount ?? ""}/></label>
    <div className="formGrid">
      <label>Impostos e descontos (R$)<input className="input" name="deductions_amount" type="number" inputMode="decimal" min={0} max={9999999999.99} step="0.01" defaultValue={financial?.deductions_amount ?? 0}/></label>
      <label>Despesas extras (R$)<input className="input" name="extra_costs_amount" type="number" inputMode="decimal" min={0} max={9999999999.99} step="0.01" defaultValue={financial?.extra_costs_amount ?? 0}/></label>
    </div>
    <small className="subtle">Em despesas extras, informe apenas custos além dos pagamentos à equipe.</small>
    <button className="btn" disabled={busy}>Salvar valores do evento</button>
  </form>;
}
