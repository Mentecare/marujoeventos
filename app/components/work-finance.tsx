"use client";
import { workflowApi, type WorkFinance, type WorkerWorkAssignment, type CommercialContract } from '@/lib/commercial';
import { supabase } from '@/lib/supabase-browser';
import { money, useMutation, workDate } from './workflow-ui';
import { revenueDateKey } from '@/lib/finance';
import { acceptedAmount } from '@/lib/work-presentation';
const metrics: [
  string,
  keyof WorkFinance
][] = [
    ['Venda contratada', 'sale_contracted'], ['Venda recebida', 'sale_received'], ['Venda a receber', 'sale_receivable'],
    ['Equipe contratada', 'labor_contracted'], ['Equipe paga', 'labor_paid'], ['Equipe a pagar', 'labor_payable'],
    ['Outros custos contratados', 'other_contracted'], ['Outros custos pagos', 'other_paid'], ['Outros custos a pagar', 'other_payable'],
    ['Resultado estimado', 'estimated_result'],
  ];
export function WorkFinancePanel({ finance, identityComplete, refresh, contracts = [] }: {
  finance: WorkFinance;
  identityComplete: boolean;
  refresh: () => Promise<void>;
  contracts?: CommercialContract[];
}) {
  const api = workflowApi(supabase), m = useMutation(refresh);
  const today = revenueDateKey(new Date());
  return <section className="panel">
    <h2>Financeiro do trabalho
    </h2>{m.feedback}
    <div className="metrics workFinanceMetrics">{metrics.map(([label, key]) =>
      <article className="metric" key={key}>
        <small>{label}
        </small>
        <strong className="currencyValue">{money(finance[key] as number | null)}
        </strong>
      </article>)}
    </div>
    <p className="subtle">Resultado estimado antes de despesas não resolvidas e impostos. {finance.unknown_labor_count} remunerações e {finance.unknown_expense_count} despesas sem valor. {finance.sale_source === 'legacy_contracted_gross' && finance.sale_received == null ? 'Venda histórica contratada; recebimento não informado.' : ''}
    </p>
    {identityComplete && finance.sale_contracted == null &&
      <form className="form" onSubmit={async (e) => {
        e.preventDefault();
        const form = e.currentTarget, f = new FormData(form);
        if (await m.run(() => api.recordSale(finance.event_id, Number(f.get('sale_amount')), String(f.get('sale_evidence'))), 'Venda registrada.'))
          form.reset();
      }}>
        <fieldset className="eventCreationFields" disabled={m.busy}>
          <h3>Registrar venda do trabalho
          </h3>
          <p className="subtle">Registre o total aceito e a referência do orçamento ou aceite externo. Recebimentos são registrados separadamente; o histórico permanece preservado.
          </p>
          <label>Total de venda aceito
            <input
              className="input"
              name="sale_amount"
              type="number"
              min="0"
              step="0.01"
              required />
          </label>
          <label>Referência do orçamento ou aceite
            <input
              className="input"
              name="sale_evidence"
              maxLength={2000}
              required />
          </label>
          <button className="btn">Registrar venda
          </button>
        </fieldset>
      </form>}
    {identityComplete && finance.sale_source !== 'accepted_contract' && contracts.length > 0 &&
      <form className="form" onSubmit={e => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        void m.run(() => api.linkSaleContract(finance.event_id, String(f.get('contract'))), 'Contrato vinculado.');
      }}>
        <fieldset className="eventCreationFields" disabled={m.busy}>
          <h3>Vincular contrato de venda aceito
          </h3>
          <p className="subtle">O contrato deve corresponder ao cliente, fornecedor e total existente. Recebimentos anteriores permanecem na sua fonte original.
          </p>
          <label>Contrato aceito
            <select
              className="select"
              name="contract"
              required>
              <option value="">Selecione
              </option>{contracts.map(c =>
                <option key={c.id} value={c.id}>{c.quote_snapshot.title} · {money(c.sale_total)}
                </option>)}
            </select>
          </label>
          <button className="btn secondary">Vincular contrato
          </button>
        </fieldset>
      </form>}
    {identityComplete && finance.sale_contracted != null && (finance.sale_receivable == null || finance.sale_receivable > 0) &&
      <form className="form" onSubmit={async (e) => {
        e.preventDefault();
        const form = e.currentTarget, f = new FormData(form), key = form.dataset.receiptKey || (form.dataset.receiptKey = crypto.randomUUID());
        if (await m.run(() => api.recordSaleReceipt(finance.event_id, Number(f.get('receipt_amount')), 'pix', String(f.get('receipt_date')), key), 'Recebimento registrado.')) {
          delete form.dataset.receiptKey;
          form.reset();
        }
      }}>
        <fieldset className="eventCreationFields" disabled={m.busy}>
          <h3>Registrar recebimento da venda
          </h3>
          <label>Valor recebido da venda
            <input
              className="input"
              name="receipt_amount"
              type="number"
              min="0.01"
              step="0.01"
              required />
          </label>
          <label>Data do recebimento da venda
            <input
              className="input"
              name="receipt_date"
              type="date"
              defaultValue={today}
              max={today}
              required />
          </label>
          <button className="btn secondary">Registrar recebimento da venda por Pix
          </button>
        </fieldset>
      </form>}
    <h3>Despesas
    </h3>
    {finance.expenses.map(x =>
      <article className="functionDraft" key={x.id}>
        <strong>{x.label}: {money(x.amount)}
        </strong>
        <p>Pago: {money(x.paid)} · {x.receipt_reference || 'Sem referência'}
        </p>
        {identityComplete && x.amount == null &&
          <form className="form" onSubmit={e => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            void m.run(() => api.resolveExpense(x.id, Number(f.get('resolved_amount')), String(f.get('resolution_reference'))), 'Valor da despesa confirmado.');
          }}>
            <fieldset className="eventCreationFields" disabled={m.busy}>
              <p className="subtle">A referência e o valor confirmados são novos registros; a despesa original permanece preservada.
              </p>
              <label>Valor confirmado da despesa
                <input
                  className="input"
                  name="resolved_amount"
                  type="number"
                  min="0"
                  step="0.01"
                  required />
              </label>
              <label>Referência da confirmação
                <input
                  className="input"
                  name="resolution_reference"
                  maxLength={500}
                  required />
              </label>
              <button className="btn secondary">Confirmar valor da despesa
              </button>
            </fieldset>
          </form>}
        {identityComplete && x.amount != null && x.paid < x.amount &&
          <form className="form" onSubmit={async (e) => {
            e.preventDefault();
            const form = e.currentTarget, f = new FormData(form), key = form.dataset.paymentKey || (form.dataset.paymentKey = crypto.randomUUID());
            if (await m.run(() => api.payExpense(x.id, Number(f.get('amount')), 'pix', String(f.get('date')), key), 'Despesa paga.')) {
              delete form.dataset.paymentKey;
              form.reset();
            }
          }}>
            <label>Pagamento da despesa
              <input
                className="input"
                name="amount"
                type="number"
                min="0.01"
                max={x.amount - x.paid}
                step="0.01"
                required />
            </label>
            <label>Data
              <input
                className="input"
                name="date"
                type="date"
                defaultValue={today}
                max={today}
                required />
            </label>
            <button className="btn secondary" disabled={m.busy}>Registrar pagamento da despesa por Pix
            </button>
          </form>}
      </article>)}
    {!finance.expenses.length &&
      <p className="empty">Nenhuma despesa registrada.
      </p>}
    <form className="form" onSubmit={async (e) => {
      e.preventDefault();
      const form = e.currentTarget, f = new FormData(form);
      if (await m.run(() => api.recordExpense(finance.event_id, String(f.get('label')), f.get('amount') === '' ? null : Number(f.get('amount')), String(f.get('reference')) || null), 'Despesa registrada.'))
        form.reset();
    }}>
      <fieldset className="eventCreationFields" disabled={m.busy || !identityComplete}>
        <h3>Registrar despesa
        </h3>
        <label>Descrição
          <input
            className="input"
            name="label"
            required />
        </label>
        <label>Valor (deixe vazio se desconhecido)
          <input
            className="input"
            name="amount"
            type="number"
            min="0"
            step="0.01" />
        </label>
        <label>Referência do comprovante
          <input className="input" name="reference" />
        </label>
        <button className="btn">Adicionar despesa
        </button>
      </fieldset>
    </form>
  </section>;
}
/** Finance-only authorization: this panel never loads operations or changes terms. */
export function TeamPayments({ rows, identityComplete, refresh }: {
  rows: WorkerWorkAssignment[];
  identityComplete: boolean;
  refresh: () => Promise<void>;
}) {
  const api = workflowApi(supabase), m = useMutation(refresh);
  return <section className="panel">
    <h3>Remuneração e pagamentos da equipe
    </h3>{m.feedback}
    {rows.map(a =>
      <article className="functionDraft" key={a.id}>
        <h4>{a.worker_name || 'Profissional'} · {a.function_name}
        </h4>
        <p>Total aceito: {money(acceptedAmount(a))} · {a.accepted_terms ? `Revisão ${a.accepted_terms.revision}` : 'Total histórico'}
        </p>
        {a.payments.map(p =>
          <p key={p.id}>{money(p.amount)} · {p.status} · {p.method}{p.paid_at ? ` · ${workDate(p.paid_at)}` : ''}
          </p>)}
        {!a.payments.length &&
          <p className="subtle">Nenhum pagamento registrado.
          </p>}
        {identityComplete && acceptedAmount(a) != null && !a.payments.some(p => p.status === 'paid') && !['cancelled', 'reserve', 'no_show'].includes(a.status) &&
          <button
            className="btn secondary"
            disabled={m.busy}
            onClick={() => m.run(() => api.pay(a.id, 'pix'), 'Pagamento registrado.')}>Registrar pagamento por Pix
          </button>}
      </article>)}{!rows.length &&
        <p className="empty">Nenhuma remuneração de equipe.
        </p>}
  </section>;
}
