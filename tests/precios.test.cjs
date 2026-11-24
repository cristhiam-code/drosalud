'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../domain/precios.js');

const pricing = global.window.DrosaludPricing;

test('calcula el precio sugerido y redondea hacia arriba según ajustes', () => {
  assert.equal(pricing.precioSugerido(1000, { m: 25, r: 100 }), 1300);
  assert.equal(pricing.precioSugerido(1000, { m: 25, r: 500 }), 1500);
});

test('mantiene el redondeo matemático cuando no hay regla de redondeo', () => {
  assert.equal(pricing.precioSugerido(1000, { m: 25, r: 0 }), 1250);
});

test('respeta el precio de venta manual existente', () => {
  assert.equal(pricing.precioVentaProducto({
    precio_compra: 1000, precio_venta: 1450
  }, { m: 25, r: 100 }), 1450);
  assert.equal(pricing.precioVentaProducto({
    precio_compra: 1000, precio_venta: 0
  }, { m: 25, r: 100 }), 0);
});

test('sugiere precio solo cuando no hay precio manual y existe costo positivo', () => {
  assert.equal(pricing.precioVentaProducto({
    precio_compra: 1000, precio_venta: null
  }, { m: 25, r: 100 }), 1300);
  assert.equal(pricing.precioVentaProducto({
    precio_compra: 0, precio_venta: null
  }, { m: 25, r: 100 }), null);
  assert.equal(pricing.precioVentaProducto({
    precio_compra: null, precio_venta: null
  }, { m: 25, r: 100 }), null);
});
