import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import ts from 'typescript';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import * as finance from '../lib/finance.ts';

// Render the actual client components; no browser, database or network mocks.
const require = createRequire(import.meta.url);
const compiled = ts.transpileModule(readFileSync(new URL('../app/components/event-finance.tsx', import.meta.url), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
}).outputText;
const componentModule = { exports: {} };
new Function('require', 'module', 'exports', compiled)(
  id => id === '@/lib/finance' ? finance : require(id), componentModule, componentModule.exports,
);
const { RevenueDashboard, AssignmentCostForm } = componentModule.exports;
const props = {
  data: { events: [], services: [], assignments: [], payments: [], financials: [] },
  period: finance.currentRevenuePeriod(), loaded: true, loading: false,
  onPeriodChange() {}, onOpenEvent() {},
};

test('unavailable and refreshing revenue do not claim zero receipts', () => {
  const unavailable = renderToStaticMarkup(React.createElement(RevenueDashboard, { ...props, loaded: false }));
  assert.ok(unavailable.includes('Receitas indisponíveis'));
  assert.ok(!unavailable.includes('R$'));
  const refreshing = renderToStaticMarkup(React.createElement(RevenueDashboard, { ...props, loaded: false, loading: true }));
  assert.ok(refreshing.includes('Atualizando receitas'));
  assert.ok(!refreshing.includes('R$'));
});

test('loaded revenue offers gross/net cards and two date fields capped at today', () => {
  const html = renderToStaticMarkup(React.createElement(RevenueDashboard, props));
  assert.ok(html.includes('Receita bruta'));
  assert.ok(html.includes('Resultado estimado'));
  assert.equal((html.match(/type="date"/g) ?? []).length, 2);
  assert.equal((html.match(new RegExp(`max="${finance.revenueDateKey(new Date())}"`, 'g')) ?? []).length, 2);
});

test('the missing contracted cost form requires an explicit value rather than defaulting to zero', () => {
  const html = renderToStaticMarkup(React.createElement(AssignmentCostForm, { assignmentId: 'test', amount: null, busy: false, onSave: async () => {} }));
  assert.ok(html.includes('required=""'));
  assert.ok(html.includes('value=""'));
  assert.ok(html.includes('Salvar valor'));
});
