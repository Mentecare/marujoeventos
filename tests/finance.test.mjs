import test from 'node:test';
import assert from 'node:assert/strict';
import { businessRevenue, currentRevenuePeriod, revenuePeriodError } from '../lib/finance.ts';

const now = new Date('2026-10-04T20:00:00Z');
const empty = { events: [], services: [], assignments: [], payments: [], financials: [] };

test('the default revenue period runs from the first day of the current Brazilian month through today', () => {
  assert.deepEqual(currentRevenuePeriod(now), { start: '2026-10-01', end: '2026-10-04' });
  assert.deepEqual(currentRevenuePeriod(new Date('2026-10-01T02:30:00Z')), { start: '2026-09-01', end: '2026-09-30' });
});

test('periods accept historical ranges but reject future dates, reversed ranges and impossible dates', () => {
  assert.equal(revenuePeriodError({ start: '2020-01-01', end: '2026-09-30' }, now), null);
  for (const period of [
    { start: '2026-10-01', end: '2026-10-05' },
    { start: '2026-10-04', end: '2026-10-01' },
    { start: '2026-02-30', end: '2026-03-01' },
    { start: '', end: '2026-10-04' },
  ]) assert.ok(revenuePeriodError(period, now));
});

const data = {
  events: [
    { id: 'october', start_at: '2026-10-02T12:00:00Z', status: 'completed' },
    { id: 'september', start_at: '2026-10-01T02:59:59Z', status: 'completed' },
    { id: 'cancelled', start_at: '2026-10-02T12:00:00Z', status: 'cancelled' },
    { id: 'future', start_at: '2026-10-05T12:00:00Z', status: 'confirmed' },
  ],
  services: [{ id: 's1', event_id: 'october' }, { id: 's2', event_id: 'september' }],
  assignments: [
    { id: 'pending', event_service_id: 's1', status: 'confirmed', agreed_amount: 999 },
    { id: 'paid-cancelled', event_service_id: 's1', status: 'cancelled', agreed_amount: 5.02 },
    { id: 'cancelled-payment', event_service_id: 's1', status: 'cancelled', agreed_amount: 800 },
    { id: 'legacy', event_service_id: 's1', status: 'checked_out', agreed_amount: 7.03 },
    { id: 'reserve', event_service_id: 's1', status: 'reserve', agreed_amount: 800 },
    { id: 'september-assignment', event_service_id: 's2', status: 'checked_out', agreed_amount: 50 },
  ],
  payments: [
    { assignment_id: 'pending', amount: 20.01, status: 'pending' },
    { assignment_id: 'paid-cancelled', amount: 5.02, status: 'paid', paid_at: '2026-09-01T12:00:00Z' },
    { assignment_id: 'cancelled-payment', amount: 800, status: 'cancelled' },
    { assignment_id: 'reserve', amount: 800, status: 'pending' },
    { assignment_id: 'september-assignment', amount: 50, status: 'paid', paid_at: '2026-10-02T12:00:00Z' },
  ],
  financials: [
    { event_id: 'october', gross_amount: 100.10, deductions_amount: 10.05, extra_costs_amount: 12.04 },
    { event_id: 'september', gross_amount: 70, deductions_amount: 0, extra_costs_amount: 0 },
    { event_id: 'cancelled', gross_amount: 1000, deductions_amount: 0, extra_costs_amount: 0 },
    { event_id: 'future', gross_amount: 1000, deductions_amount: 0, extra_costs_amount: 0 },
  ],
};

test('net revenue deducts recorded obligations, extras and deductions once, using the event date', () => {
  const result = businessRevenue(data, currentRevenuePeriod(now), now);
  assert.equal(result.grossRevenue, 100.10);
  assert.equal(result.teamCosts, 32.06);
  assert.equal(result.deductions, 10.05);
  assert.equal(result.extraCosts, 12.04);
  assert.equal(result.netRevenue, 45.95);
  assert.equal(result.eventCount, 1);
  assert.deepEqual(result.missingEventIds, []);
  const earlier = businessRevenue(data, { start: '2026-09-01', end: '2026-09-30' }, now);
  assert.equal(earlier.grossRevenue, 70);
  assert.equal(earlier.netRevenue, 20);
});

test('empty periods show zero while unpriced events are excluded and clearly reported as incomplete', () => {
  assert.equal(businessRevenue(empty, currentRevenuePeriod(now), now).grossRevenue, 0);
  const unpriced = { id: 'unpriced', start_at: '2026-10-04T12:00:00Z', status: 'confirmed' };
  const result = businessRevenue({ ...data, events: [...data.events, unpriced] }, currentRevenuePeriod(now), now);
  assert.equal(result.grossRevenue, 100.10);
  assert.equal(result.netRevenue, 45.95);
  assert.deepEqual(result.missingEventIds, ['unpriced']);
  const unknown = businessRevenue({ ...empty, events: [unpriced] }, currentRevenuePeriod(now), now);
  assert.equal(unknown.grossRevenue, null);
  assert.equal(unknown.netRevenue, null);
  assert.equal(unknown.recordedEventCount, 0);
});

test('zero is a real recorded price and negative net revenue is preserved', () => {
  const result = businessRevenue({ ...data, financials: [{ event_id: 'october', gross_amount: 0, deductions_amount: 0, extra_costs_amount: 0 }] }, currentRevenuePeriod(now), now);
  assert.equal(result.grossRevenue, 0);
  assert.equal(result.netRevenue, -32.06);
});

test('unpaid reserves are excluded, while a real paid reserve still counts as a cost', () => {
  const result = businessRevenue({ ...data, payments: data.payments.map(payment => payment.assignment_id === 'reserve' ? { ...payment, status: 'paid' } : payment) }, currentRevenuePeriod(now), now);
  assert.equal(result.teamCosts, 832.06);
  assert.equal(result.netRevenue, -754.05);
});

test('a missing contracted cost keeps net revenue unknown instead of inventing profit', () => {
  const result = businessRevenue({ ...data, assignments: [...data.assignments, { id: 'unknown', event_service_id: 's1', status: 'confirmed', agreed_amount: null }] }, currentRevenuePeriod(now), now);
  assert.equal(result.grossRevenue, 100.10);
  assert.equal(result.netRevenue, null);
  assert.deepEqual(result.missingCostEventIds, ['october']);
});


test('legacy contracted gross exposes no fabricated receipt and labels the result as estimated', () => {
  const result = businessRevenue(data, currentRevenuePeriod(now), now);
  assert.equal(result.contractedSale,100.10);
  assert.equal(result.receivedSale,null);
  assert.equal(result.receivableSale,null);
  assert.equal(result.estimatedResult,45.95);
  assert.equal(result.resultLabel,'estimated_before_unresolved_expenses_and_taxes');
});

test('an incomplete contracted-sale period keeps the canonical estimated result unknown', () => {
  const unpriced={id:'unpriced',start_at:'2026-10-04T12:00:00Z',status:'confirmed'};
  const result=businessRevenue({...data,events:[...data.events,unpriced]},currentRevenuePeriod(now),now);
  assert.equal(result.contractedSale,null);assert.equal(result.estimatedResult,null);
  assert.equal(result.grossRevenue,100.10);assert.deepEqual(result.missingEventIds,['unpriced']);
});
