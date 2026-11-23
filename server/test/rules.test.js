'use strict';

const test = require('node:test');
const assert = require('node:assert');
const rules = require('../src/rules');

const today = '2026-11-22';
const store = { name: 'Súper Centro Arrecife', lat: 28.963, lng: -13.55 };

test('distancia Arrecife - Las Palmas > 100 km', () => {
  assert.ok(rules.distanceKm(28.963, -13.55, 28.1235, -15.4363) > 150);
});

test('nombres normalizados y parecidos', () => {
  assert.strictEqual(rules.normName('Súper Centro (ejemplo)'), 'super centro');
  assert.ok(rules.similarNames('mercadona arrecife', 'mercadona'));
  assert.ok(!rules.similarNames('mercadona arrecife', 'hiperdino arrecife'));
});

test('valida una aportación correcta', () => {
  const v = rules.validateContribution({ ean: '8410000000000', price: '1.239', store, date: today }, today);
  assert.strictEqual(v.ok, true);
  assert.strictEqual(v.price, 1.24);
  assert.strictEqual(v.source, 'manual');
});

test('rechaza datos inválidos', () => {
  assert.strictEqual(rules.validateContribution({ ean: 'abc', price: 1, store }, today).ok, false);
  assert.strictEqual(rules.validateContribution({ ean: '8410000000000', price: -1, store }, today).ok, false);
  assert.strictEqual(rules.validateContribution({ ean: '8410000000000', price: 1, store: {} }, today).ok, false);
  assert.strictEqual(rules.validateContribution({ ean: '8410000000000', price: 1, store, date: '2027-01-01' }, today).ok, false);
});

test('estado inicial: fuera de rango, de confianza o pendiente', () => {
  const base = rules.validateContribution({ ean: '8410000000000', price: 9, store }, today);
  assert.strictEqual(rules.initialStatus(base, [1, 1.1, 0.9]), 'rejected');
  const ticket = { ...base, price: 1.05, source: 'ticket' };
  assert.strictEqual(rules.initialStatus(ticket, [1, 1.1, 0.9]), 'validated');
  const manual = { ...base, price: 1.05, source: 'manual' };
  assert.strictEqual(rules.initialStatus(manual, [1]), 'pending');
});

test('agrega con mediana, personas distintas y ofertas caducadas fuera', () => {
  const row = (price, date, key, extra = {}) => ({
    ean: '1', store_id: 7, store_name: 'S', lat: 0, lng: 0, price, observed_on: date,
    contributor_key: key, is_offer: false, valid_until: null, reports: 0, ...extra,
  });
  const out = rules.aggregate([
    row(1.0, '2026-11-20', 'a'),
    row(1.2, '2026-11-15', 'b'),
    row(1.1, '2026-11-10', 'a'),
    row(0.5, '2026-11-01', 'c', { is_offer: true, valid_until: '2026-11-05' }),
  ], today);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].price, 1.1);
  assert.strictEqual(out[0].confirmations, 2);
  assert.strictEqual(out[0].date, '2026-11-20');
});

test('cadenas: se reconocen por marca o nombre', () => {
  const { detectChain } = require('../src/chains');
  assert.strictEqual(detectChain('HiperDino Express'), 'hiperdino');
  assert.strictEqual(detectChain('', 'Mercadona Arrecife'), 'mercadona');
  assert.strictEqual(detectChain('Supermercados Dia'), 'dia');
  assert.strictEqual(detectChain('Diamante bazar'), null);
  assert.strictEqual(detectChain('Tienda de la esquina'), null);
});

test('aportación con id global de supermercado', () => {
  const v = rules.validateContribution(
    { ean: '8410000000000', price: 1, store: { ...store, global_id: 42, chain: 'mercadona' } }, today);
  assert.strictEqual(v.store.globalId, 42);
  assert.strictEqual(v.store.chain, 'mercadona');
});
