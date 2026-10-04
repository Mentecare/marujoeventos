import test from 'node:test';
import assert from 'node:assert/strict';
import { capabilitiesFor, navigationFor, profileOrganizationFor } from '../lib/capabilities.ts';
import { validateDocument, normalizeDocument } from '../lib/identity.ts';
import { freelancerDashboard, businessDashboard } from '../lib/dashboard.ts';

test('freelancer and incomplete business accounts cannot open client or team management', () => {
  const freelancer = { role:'freelancer', profile_type:'freelancer', active:true, onboarding_completed:true };
  assert.equal(capabilitiesFor(freelancer).manageEvents, false);
  assert.equal(capabilitiesFor(freelancer).viewClients, false);
  assert.equal(navigationFor(freelancer).some(x => x.id === 'team' || x.id === 'clients'), false);
  assert.deepEqual(navigationFor(freelancer).slice(0,2).map(x => x.id), ['home','dashboard']);
  assert.equal(capabilitiesFor({...freelancer, profile_type:'company', onboarding_completed:false}).manageEvents, false);
  assert.equal(capabilitiesFor({...freelancer, role:'admin', active:false}).manageCalendar, false);
});

test('all completed business profiles retain clients/events while Google stays staff-only', () => {
  for (const type of ['team_lead','company','agency']) {
    const p={role:'freelancer',profile_type:type,active:true,onboarding_completed:true};
    assert.equal(capabilitiesFor(p).viewClients,true);
    assert.equal(capabilitiesFor(p).manageEvents,true);
    assert.equal(capabilitiesFor(p).manageCalendar,false);
  }
  assert.equal(capabilitiesFor({role:'admin',profile_type:null,active:true,onboarding_completed:true}).manageCalendar,true);
});

test('profile editing selects the first active owned organization regardless of the operational selection', () => {
  const organizations=[
    {id:'selected-managed',owner_profile_id:'another',active:true,created_at:'2026-01-01T00:00:00Z'},
    {id:'later-owned',owner_profile_id:'me',active:true,created_at:'2026-03-01T00:00:00Z'},
    {id:'inactive-owned',owner_profile_id:'me',active:false,created_at:'2025-01-01T00:00:00Z'},
    {id:'first-owned',owner_profile_id:'me',active:true,created_at:'2026-02-01T00:00:00Z'},
  ];
  assert.equal(profileOrganizationFor(organizations,'me')?.id,'first-owned');
  assert.equal(profileOrganizationFor(organizations,'unrelated'),null);
});

test('private identity checks reject forged check digits and support numeric and alphabetic CNPJ', () => {
  assert.equal(validateDocument('cpf','529.982.247-25'),true);
  assert.equal(validateDocument('cpf','529.982.247-24'),false);
  assert.equal(validateDocument('cpf','11111111111'),false);
  assert.equal(validateDocument('cnpj','11.222.333/0001-81'),true);
  assert.equal(validateDocument('cnpj','12.ABC.345/01DE-35'),true);
  assert.equal(validateDocument('cnpj','12.ABC.345/01DE-36'),false);
  assert.equal(normalizeDocument('cnpj','12.abc.345/01de-35'),'12ABC34501DE35');
  assert.equal(validateDocument('cpf','abc52998224725'),false);
});

const now=new Date('2026-10-04T12:00:00Z');
const events=[{id:'past',start_at:'2026-09-10T12:00:00Z',status:'completed'},{id:'future',start_at:'2026-10-10T12:00:00Z',status:'confirmed'}];
const services=[{id:'s1',event_id:'past',quantity_needed:2},{id:'s2',event_id:'future',quantity_needed:3}];
const assignments=[{id:'a1',event_service_id:'s1',status:'checked_out',agreed_amount:100},{id:'a2',event_service_id:'s2',status:'confirmed',agreed_amount:200},{id:'a3',event_service_id:'s2',status:'cancelled',agreed_amount:900},{id:'a4',event_service_id:'s2',status:'invited',agreed_amount:500}];
const payments=[{assignment_id:'a1',status:'paid',amount:100,paid_at:'2026-10-02T12:00:00Z'},{assignment_id:'a2',status:'pending',amount:200},{assignment_id:'a3',status:'paid',amount:900,paid_at:'2026-10-02T12:00:00Z'}];

test('earnings use paid records and separate future confirmed income without invitations/cancellations', () => {
  const d=freelancerDashboard({events,services,assignments,payments,applications:[{status:'accepted'},{status:'rejected'},{status:'withdrawn'}],ratings:[{rating:4},{rating:5}]},now);
  assert.equal(d.paidTotal,1000); // a cancelled job may still have a real historical payment
  assert.equal(d.paidThisMonth,1000);
  assert.equal(d.upcomingIncome,200);
  assert.equal(d.completedJobs,1);
  assert.equal(d.hireRate,50);
  assert.equal(d.reviewAverage,4.5);
  assert.equal(d.months.at(-1).paid,1000);
  assert.equal(d.months.at(-2).jobs,1);
});

test('empty dashboards show absent averages/rates rather than invented performance', () => {
  const d=freelancerDashboard({events:[],services:[],assignments:[],payments:[],applications:[],ratings:[]},now);
  assert.equal(d.hireRate,null); assert.equal(d.reviewAverage,null); assert.equal(d.reviewCount,0);
  assert.equal(d.months.length,6);
  const b=businessDashboard({events,services,assignments,payments,clients:[{active:true}]},now);
  assert.equal(b.activeEvents,1); assert.equal(b.completedEvents,1); assert.equal(b.vacancies,5);
  assert.equal(b.filledVacancies,3); assert.equal(b.clients,1);
});
