import type {WorkerWorkAssignment} from './commercial.ts';
/** Only accepted revisions become payable; legacy totals never gain day multiplication. */
export function acceptedAmount(assignment:WorkerWorkAssignment):number|null{
 return assignment.accepted_terms?assignment.accepted_terms.total:assignment.terms_history.length?null:assignment.legacy_agreed_amount;
}
export function mutableWork(status:string,end:string|null,now=Date.now()){
 return !['completed','cancelled'].includes(status)&&(!end||new Date(end).getTime()>now);
}

/** Own assignments are the authority; only explicit completion evidence counts as completed work. */
export function workerDashboardMetrics(rows:WorkerWorkAssignment[]){
 const active=new Set<string>(),completed=new Set<string>();
 let paidTotal=0;
 for(const row of rows){
  if(!['completed','cancelled'].includes(row.event_status)&&['invited','confirmed','checked_in'].includes(row.status))active.add(row.event_id);
  if(row.event_status==='completed'&&row.completion_confirmed&&['confirmed','checked_in','checked_out'].includes(row.status))completed.add(row.event_id);
  for(const payment of row.payments)if(payment.status==='paid')paidTotal+=payment.amount;
 }
 return {activeWork:active.size,completedWork:completed.size,paidTotal};
}

/** Only settled payment evidence counts; pending legacy rows are never cash received. */
export function assignmentPaymentSummary(assignment:WorkerWorkAssignment){
 const contracted=acceptedAmount(assignment);
 const paidCents=assignment.payments.filter(p=>p.status==='paid').reduce((sum,p)=>sum+Math.round(p.amount*100),0);
 const paid=paidCents/100;
 return {contracted,paid,balance:contracted==null?null:(Math.round(contracted*100)-paidCents)/100};
}
