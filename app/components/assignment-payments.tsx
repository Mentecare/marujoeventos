"use client";
import {useEffect,useRef,useState} from 'react';
import {workflowApi,type AssignmentPaymentLedger,type WorkerWorkAssignment} from '@/lib/commercial';
import {assignmentPaymentSummary} from '@/lib/work-presentation';
import {revenueDateKey} from '@/lib/finance';
import {supabase} from '@/lib/supabase-browser';
import {calendarDate,money,useMutation,workDate} from './workflow-ui';
export function AssignmentPayments({assignment:a,canRecord=false,refresh}:{assignment:WorkerWorkAssignment;canRecord?:boolean;refresh:()=>Promise<void>}){
 const summary=assignmentPaymentSummary(a),[expanded,setExpanded]=useState(false);
 return <div className="payrollBlock">
  <div className="metrics"><article className="metric"><small>Combinado e aceito</small><strong>{money(summary.contracted)}</strong></article><article className="metric"><small>Já pago</small><strong>{money(summary.paid)}</strong></article><article className="metric"><small>Saldo pendente</small><strong>{money(summary.balance)}</strong></article></div>
  <h4>Histórico de pagamentos</h4>{a.payments.map(p=><p key={p.id}>{money(p.amount)} · {p.status==='paid'?'Pago':p.status==='pending'?'Previsto':p.status} · {p.method||'Forma não informada'}{p.paid_at?` · ${workDate(p.paid_at)}`:''}</p>)}{!a.payments.length&&<p className="subtle">Nenhum pagamento registrado.</p>}
  <details onToggle={e=>setExpanded(e.currentTarget.open)}><summary>{canRecord?'Adiantamentos, parcelas e quitação':'Detalhes dos meus recebimentos'}</summary>{expanded&&<PaymentEditor assignmentId={a.id} canRecord={canRecord&&['confirmed','checked_in','checked_out'].includes(a.status)} refresh={refresh}/>}</details>
 </div>;
}
function PaymentEditor({assignmentId,canRecord,refresh}:{assignmentId:string;canRecord:boolean;refresh:()=>Promise<void>}){
 const api=workflowApi(supabase),[ledger,setLedger]=useState<AssignmentPaymentLedger|null>(null),[error,setError]=useState(''),[reload,setReload]=useState(0),key=useRef<string|null>(null);
 async function load(){const data=await api.assignmentLedger(assignmentId);setLedger(data)}
 const m=useMutation(async()=>{await load();await refresh()});
 useEffect(()=>{let active=true;setLedger(null);setError('');api.assignmentLedger(assignmentId).then(v=>{if(active)setLedger(v)}).catch(()=>{if(active)setError('Não foi possível carregar o saldo e as referências. Tente novamente.')});return()=>{active=false}},[assignmentId,reload]);
 if(error)return <p className="error" role="alert">{error} <button className="btn secondary" onClick={()=>setReload(x=>x+1)}>Tentar novamente</button></p>;
 if(!ledger)return <p role="status">Carregando saldo autorizado…</p>;
 const today=revenueDateKey(new Date());
 return <>{m.feedback}{ledger.entries.map(entry=><article className="operationRow" key={entry.id}><div><strong>{entry.payment_kind==='advance'?'Adiantamento':entry.payment_kind==='settlement'?'Quitação':'Pagamento parcial'} · {money(entry.amount)}</strong><span>{calendarDate(entry.paid_on)} · {entry.method}</span>{entry.evidence_reference&&<span>Referência: {entry.evidence_reference}</span>}{entry.notes&&<span>{entry.notes}</span>}</div></article>)}
 {canRecord&&ledger.balance!=null&&ledger.balance>0&&<form className="form" onSubmit={async e=>{e.preventDefault();const form=e.currentTarget,f=new FormData(form);key.current??=crypto.randomUUID();if(await m.run(()=>api.recordAssignmentPayment(assignmentId,Number(f.get('amount')),String(f.get('method')) as 'pix'|'transfer'|'cash'|'other',String(f.get('date')),String(f.get('kind')) as 'advance'|'partial'|'settlement',String(f.get('reference'))||null,String(f.get('notes'))||null,key.current!), 'Pagamento registrado no histórico.')){key.current=null;form.reset()}}}>
  <fieldset className="eventCreationFields" disabled={m.busy}><legend>Registrar pagamento já realizado</legend><p className="subtle">Saldo atual: {money(ledger.balance)}. Uma quitação deve corresponder ao saldo completo.</p>
  <label>Tipo de lançamento<select name="kind" className="select"><option value="advance">Adiantamento</option><option value="partial">Pagamento parcial</option><option value="settlement">Quitação do saldo</option></select></label>
  <label>Valor pago (R$)<input className="input" name="amount" type="number" min="0.01" step="0.01" max={ledger.balance} required/></label>
  <label>Data do pagamento<input className="input" name="date" type="date" max={today} defaultValue={today} required/></label>
  <label>Forma<select name="method" className="select"><option value="pix">Pix</option><option value="transfer">Transferência</option><option value="cash">Dinheiro</option><option value="other">Outra</option></select></label>
  <label>Referência do comprovante<input className="input" name="reference" maxLength={500} placeholder="Ex.: identificação da transferência"/></label>
  <label>Observação<input className="input" name="notes" maxLength={1000}/></label><button className="btn">Registrar pagamento</button></fieldset>
 </form>}{ledger.balance===0&&<p className="notice">Saldo quitado.</p>}</>;
}
