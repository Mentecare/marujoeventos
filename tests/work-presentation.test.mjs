import test from 'node:test';
import assert from 'node:assert/strict';
import {acceptedAmount,mutableWork,workerDashboardMetrics} from '../lib/work-presentation.ts';
import {capabilitiesFor} from '../lib/capabilities.ts';
const base={legacy_agreed_amount:200,accepted_terms:null,terms_history:[]};
test('presentation preserves historic totals and ignores unaccepted revised payable amounts',()=>{
 assert.equal(acceptedAmount(base),200);
 assert.equal(acceptedAmount({...base,terms_history:[{total:440}],offered_terms:{total:440}}),null);
 assert.equal(acceptedAmount({...base,terms_history:[{total:440},{total:460}],accepted_terms:{total:440},offered_terms:{total:460}}),440);
 assert.equal(acceptedAmount({...base,accepted_terms:{total:null}}),null);
 assert.equal(acceptedAmount({...base,accepted_terms:{total:0}}),0);
});
test('generic staff and business labels do not authorize finance; explicit canonical organization grants do',()=>{
 const p={role:'coordinator',profile_type:'company',active:true,onboarding_completed:true};
 assert.equal(capabilitiesFor(p).managePayments,false);
 const org={id:'org',market_role:'provider',can_operate:true,can_finance:false};
 assert.equal(capabilitiesFor(p,{organizations:[org]}).managePayments,false);
 assert.equal(capabilitiesFor(p,{organizations:[{...org,can_finance:true}]}).managePayments,true);
 const buyer=capabilitiesFor(p,{organizations:[{...org,market_role:'buyer',can_finance:true}]});
 assert.equal(buyer.manageEvents,false);assert.equal(buyer.manageTeam,false);assert.equal(buyer.managePayments,false);
});
test('ended, completed and cancelled work suppress remuneration revisions',()=>{
 assert.equal(mutableWork('confirmed','2099-01-01T12:00:00Z'),true);
 assert.equal(mutableWork('completed',null),false);
 assert.equal(mutableWork('cancelled',null),false);
 assert.equal(mutableWork('confirmed','2020-01-01T12:00:00Z'),false);
});

test('worker dashboard uses own distinct work, confirmed completion and paid evidence',()=>{
 const row={...base,id:'a',event_id:'active',event_status:'confirmed',status:'invited',completion_confirmed:false,payments:[]};
 const done={...row,id:'b',event_id:'done',event_status:'completed',status:'checked_out',completion_confirmed:true,payments:[{id:'paid',amount:440,status:'paid'},{id:'pending',amount:100,status:'pending'}]};
 const rows=[row,{...row,id:'second-function'},done,{...done,id:'duplicate',payments:[]},{...done,id:'not-confirmed',event_id:'unconfirmed',completion_confirmed:false,payments:[]},...['reserve','cancelled','no_show'].map(status=>({...done,id:status,event_id:status,status,payments:[]})),{...row,id:'cancelled-event',event_id:'cancelled-event',event_status:'cancelled'}];
 assert.deepEqual(workerDashboardMetrics(rows),{activeWork:1,completedWork:1,paidTotal:440});
 assert.deepEqual(workerDashboardMetrics([]),{activeWork:0,completedWork:0,paidTotal:0});
});
