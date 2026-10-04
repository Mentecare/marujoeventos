type Event={id:string;start_at:string;status:string};
type Service={id:string;event_id:string;quantity_needed:number};
type Assignment={id:string;event_service_id:string;status:string;agreed_amount?:number|null};
type Payment={assignment_id:string;status:string;amount:number;paid_at?:string|null;created_at?:string};
type Data={events:Event[];services:Service[];assignments:Assignment[];payments:Payment[];applications?:{status:string}[];ratings?:{rating:number}[];clients?:{active:boolean}[]};
export function monthKey(value:string|Date){return new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit'}).format(new Date(value)).slice(0,7)}
function months(now:Date){
  const [year,month]=monthKey(now).split('-').map(Number);
  return Array.from({length:6},(_,i)=>{const d=new Date(Date.UTC(year,month-6+i,15,12));return {key:monthKey(d),label:new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',month:'short'}).format(d),paid:0,jobs:0,cost:0,events:0}});
}
export function freelancerDashboard(data:Data,now=new Date()){
  const series=months(now), paid=data.payments.filter(p=>p.status==='paid');
  const paidTotal=paid.reduce((sum,p)=>sum+Number(p.amount),0);
  for(const p of paid){const m=series.find(x=>x.key===monthKey(p.paid_at||p.created_at||now));if(m)m.paid+=Number(p.amount)}
  const completed=data.assignments.filter(a=>a.status==='checked_out');
  for(const a of completed){const s=data.services.find(x=>x.id===a.event_service_id);const ev=data.events.find(x=>x.id===s?.event_id);const m=ev&&series.find(x=>x.key===monthKey(ev.start_at));if(m)m.jobs++}
  const future=data.assignments.filter(a=>['confirmed','checked_in'].includes(a.status)&&!paid.some(p=>p.assignment_id===a.id)&&data.events.some(e=>e.id===data.services.find(s=>s.id===a.event_service_id)?.event_id&&e.status!=='cancelled'&&new Date(e.start_at)>now));
  const upcomingIncome=future.reduce((sum,a)=>sum+Number(data.payments.find(p=>p.assignment_id===a.id&&!['cancelled','paid'].includes(p.status))?.amount??a.agreed_amount??0),0);
  const applications=(data.applications||[]).filter(a=>a.status!=='withdrawn');
  const accepted=applications.filter(a=>a.status==='accepted').length;
  const ratings=data.ratings||[];
  return {paidTotal,paidThisMonth:series.at(-1)?.paid??0,upcomingIncome,completedJobs:completed.length,applications:applications.length,hireRate:applications.length?accepted/applications.length*100:null,reviewCount:ratings.length,reviewAverage:ratings.length?ratings.reduce((sum,r)=>sum+Number(r.rating),0)/ratings.length:null,months:series};
}
export function businessDashboard(data:Data,now=new Date()){
  const series=months(now);
  for(const e of data.events){const m=series.find(x=>x.key===monthKey(e.start_at));if(m&&e.status!=='cancelled')m.events++}
  for(const p of data.payments.filter(x=>x.status==='paid')){const m=series.find(x=>x.key===monthKey(p.paid_at||p.created_at||now));if(m)m.cost+=Number(p.amount)}
  return {activeEvents:data.events.filter(e=>!['completed','cancelled'].includes(e.status)).length,completedEvents:data.events.filter(e=>e.status==='completed').length,vacancies:data.services.reduce((sum,s)=>sum+Number(s.quantity_needed),0),filledVacancies:data.assignments.filter(a=>['invited','confirmed','checked_in','checked_out'].includes(a.status)).length,costs:data.payments.filter(p=>p.status!=='cancelled').reduce((sum,p)=>sum+Number(p.amount),0),paidCosts:data.payments.filter(p=>p.status==='paid').reduce((sum,p)=>sum+Number(p.amount),0),clients:(data.clients||[]).filter(c=>c.active).length,months:series};
}
