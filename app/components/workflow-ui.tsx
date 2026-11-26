"use client";
import {useRef,useState} from 'react';
export const money=(value:number|null|undefined)=>value==null?'Valor não informado':Number(value).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export const calendarDate=(value:string)=>value.slice(0,10).split('-').reverse().join('/');
export const workDate=(value:string)=>new Date(value).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'});
const operationErrors:Record<string,string>={
 payment_exceeds_payable:'O valor informado ultrapassa o saldo pendente. Atualize os dados e confira o pagamento.',
 settlement_must_match_balance:'Para quitar, informe exatamente o saldo pendente.',
 worker_acceptance_required:'O profissional precisa aceitar a convocação e as condições antes do pagamento.',
 invalid_installment:'Confira o valor, a data, a forma e o tipo de pagamento.',
 idempotency_conflict:'Esta tentativa já foi registrada com outros dados. Atualize o histórico antes de continuar.',
 assignment_has_installments:'Há pagamentos parciais registrados. Preserve as condições e faça o acerto financeiro antes de outras alterações.',
 payment_on_hold:'O pagamento está retido ou cancelado. Confira a contratação antes de registrar uma parcela.',
 invalid_shift:'Informe um turno futuro, dentro das datas do evento, com término posterior ao início e ponto de encontro.',
 worker_shift_conflict:'Este profissional já está alocado em outro turno no mesmo horário.',
 existing_shifts_outside_event:'As novas datas deixariam turnos já cadastrados fora do evento.',
 schedule_locked:'A escala não pode ser alterada após o início do turno ou o registro de presença.',
 replacement_evidence_locked:'A contratação já tem presença, pagamento ou substituição registrada. O histórico deve ser preservado.',
 invalid_replacement:'Selecione outro profissional e informe o motivo da substituição.',
 historical_assignment_cannot_reopen:'Este profissional já tem uma contratação nesta função. Preserve o histórico existente.',
 forbidden:'Sua conta não tem permissão para realizar esta ação.',event_closed:'Este evento não está aberto para alterações.',
};
export function useMutation(refresh:()=>Promise<void>){
 const lock=useRef(false);const [busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 async function run(work:()=>Promise<unknown>,message='Salvo.'){if(lock.current)return false;lock.current=true;setBusy(true);setError('');setNotice('');let committed=false;try{await work();committed=true;setNotice(message);await refresh();return true}catch(e){setError(operationErrors[e instanceof Error?e.message:String(e)]||(e instanceof Error?e.message:String(e)));return committed}finally{lock.current=false;setBusy(false)}}
 return {busy,run,feedback:<>{error&&<p className="error" role="alert">{error}</p>}{notice&&<p className="notice" role="status">{notice}</p>}</>};
}
