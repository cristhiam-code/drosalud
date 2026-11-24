'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../domain/dinero.js');

const money = global.window.DrosaludMoney;

test('suma subtotal a partir de precio por unidad base y cantidad', () => {
  assert.equal(money.subtotalLineas([
    { precio_venta: 1000, cantidad: 10 },
    { precio_venta: 1200, cantidad: 3 }
  ]), 13600);
});

test('subtotal vacío es cero', () => {
  assert.equal(money.subtotalLineas([]), 0);
});

test('calcula porcentaje de ganancia sobre el costo de compra', () => {
  assert.equal(money.porcentajeSobreCosto(1300, 1000), 30);
  assert.equal(money.porcentajeSobreCosto(900, 1000), -10);
});

test('no divide por cero cuando el costo no es positivo', () => {
  assert.equal(money.porcentajeSobreCosto(1000, 0), 0);
  assert.equal(money.porcentajeSobreCosto(1000, null), 0);
});
