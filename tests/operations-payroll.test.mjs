import test from 'node:test';
import assert from 'node:assert/strict';
import {assignmentPaymentSummary} from '../lib/work-presentation.ts';
import {workflowApi} from '../lib/commercial.ts';
const base={accepted_terms:null,terms_history:[],legacy_agreed_amount:440,payments:[]};
test('payroll shows accepted contracted total, settled installments and exact remaining balance',()=>{
 const row={...base,payments:[{id:'legacy',status:'pending',amount:440},{id:'advance',status:'paid',amount:100.01},{id:'partial',status:'paid',amount:39.99}]};
 assert.deepEqual(assignmentPaymentSummary(row),{contracted:440,paid:140,balance:300});
 assert.deepEqual(assignmentPaymentSummary({...row,payments:[...row.payments,{status:'paid',amount:300}]}),{contracted:440,paid:440,balance:0});
});
test('pending remuneration revision does not invent a payable total or override accepted wages',()=>{
 const row={...base,terms_history:[{total:800}],offered_terms:{total:800},payments:[{status:'paid',amount:50}]};
 assert.deepEqual(assignmentPaymentSummary(row),{contracted:null,paid:50,balance:null});
 assert.deepEqual(assignmentPaymentSummary({...row,accepted_terms:{total:440}}),{contracted:440,paid:50,balance:390});
});
test('operations RPC adapter carries authoritative assignment, full payment evidence and caller idempotency',async()=>{
 const calls=[],api=workflowApi({rpc:async(name,args)=>{calls.push({name,args});return {data:[],error:null}}});
 await api.recordAssignmentPayment('assignment',100,'pix','2026-11-26','advance','Comprovante 1','Adiantamento','key-1');
 assert.deepEqual(calls.pop(),{name:'record_assignment_payment',args:{p_assignment_id:'assignment',p_amount:100,p_method:'pix',p_paid_on:'2026-11-26',p_payment_kind:'advance',p_evidence_reference:'Comprovante 1',p_notes:'Adiantamento',p_idempotency_key:'key-1'}});
 await api.shifts();assert.deepEqual(calls.pop(),{name:'get_work_shifts',args:{p_event_id:null}});
 await api.setShiftAssignment('shift','assignment',true);assert.deepEqual(calls.pop(),{name:'set_work_shift_assignment',args:{p_shift_id:'shift',p_assignment_id:'assignment',p_assigned:true}});
 await api.replaceAssignment('old','new-worker','Ausência');assert.deepEqual(calls.pop(),{name:'replace_event_assignment',args:{p_assignment_id:'old',p_replacement_freelancer_id:'new-worker',p_reason:'Ausência'}});
});
