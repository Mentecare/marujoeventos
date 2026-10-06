import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import * as commercial from '../lib/commercial.ts';
import * as presentation from '../lib/work-presentation.ts';
import * as finance from '../lib/finance.ts';
import * as photos from '../lib/profile-photos.ts';
const require=createRequire(import.meta.url),cache=new Map();
// Render real components and adapters. Only the external browser database is unavailable.
function component(name){if(cache.has(name))return cache.get(name);const module={exports:{}};const source=ts.transpileModule(readFileSync(new URL(`../app/components/${name}.tsx`,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;new Function('require','module','exports',source)(id=>id==='@/lib/supabase-browser'?{supabase:{}}:id==='@/lib/commercial'?commercial:id==='@/lib/work-presentation'?presentation:id==='@/lib/finance'?finance:id==='@/lib/profile-photos'?photos:id.startsWith('./')?component(id.slice(2)):require(id),module,module.exports);cache.set(name,module.exports);return module.exports}
const org={id:'provider',display_name:'Provider',market_role:'provider',can_operate:false,can_finance:true,is_owner:false};
test('explicit finance members can prepare commercial quotes without an operations role',()=>{const html=renderToStaticMarkup(React.createElement(component('commercial-workspace').CommercialWorkspace,{organization:org,identityComplete:true}));assert.ok(html.includes('Novo orçamento de venda'),'Quote editor must follow canonical finance permission')});
test('unknown contracted expense does not offer a settlement that requires a known amount',()=>{const {WorkFinancePanel}=component('work-finance');const render=amount=>renderToStaticMarkup(React.createElement(WorkFinancePanel,{identityComplete:true,refresh:async()=>{},finance:{expenses:[{id:'expense',label:'Transporte pendente',amount,paid:0}],unknown_labor_count:0,unknown_expense_count:amount==null?1:0}}));assert.ok(!render(null).includes('Registrar pagamento da despesa por Pix'));assert.ok(render(100).includes('Registrar pagamento da despesa por Pix'))});
test('workers see each offered change before accepting a revision alongside the accepted conditions',()=>{const {WorkerWork}=component('worker-work');const common={basis:'daily',contract_days:2,planned_hours:8,rate:220,additions:0,deductions:0,total:440};const html=renderToStaticMarkup(React.createElement(WorkerWork,{refresh:async()=>{},rows:[{id:'assignment',event_name:'Trabalho',function_name:'Carregador',start_at:'2099-10-07T12:00:00Z',end_at:'2099-10-07T22:00:00Z',event_status:'confirmed',status:'confirmed',accepted_terms:{...common,id:'accepted',revision:1,benefits:'Alimentação incluída'},offered_terms:{...common,id:'offered',revision:2,benefits:'Transporte incluído',deductions:20,total:420},terms_history:[],payments:[]}]}));assert.ok(html.includes('Alimentação incluída'));assert.ok(html.includes('Transporte incluído'),'The pending offer must disclose benefits and deductions before consent');assert.ok(html.includes('20,00'))});

test('finance discovery adapter uses the caller RPC independently from event operations',async()=>{
 const calls=[],index=[{event_id:'event',event_name:'Authorized finance',organization_id:'provider'}];
 const api=commercial.workflowApi({rpc:async(name,args)=>{calls.push({name,args});return {data:index,error:null}}});
 assert.deepEqual(await api.financeIndex(),index);
 assert.deepEqual(calls,[{name:'get_work_finance_index',args:undefined}]);
 const denied=commercial.workflowApi({rpc:async()=>({data:null,error:{message:'forbidden'}})});
 await assert.rejects(denied.financeIndex(),/forbidden/);
});
