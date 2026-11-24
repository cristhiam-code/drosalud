'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../domain/presentaciones.js');

const presentations = global.window.DrosaludPresentations;

test('resuelve el factor de presentación con valor predeterminado seguro', () => {
  assert.equal(presentations.unidadesPresentacion({ unidades_por_presentacion: 12 }), 12);
  assert.equal(presentations.unidadesPresentacion({ unidadesPorPresentacion: 6 }), 6);
  assert.equal(presentations.unidadesPresentacion({}), 1);
  assert.equal(presentations.unidadesPresentacion({ unidades_por_presentacion: 0 }), 1);
});

test('convierte cantidad de cajas a empaques y conserva unidades sueltas', () => {
  assert.equal(presentations.cantidadPresentacion({
    presentacion: 'Caja', cantidad: 24, unidades_por_presentacion: 12
  }), 2);
  assert.equal(presentations.cantidadPresentacion({
    presentacion: 'Unidad', cantidad: 3, unidades_por_presentacion: 12
  }), 3);
});

test('convierte precio por unidad a precio por caja solo cuando corresponde', () => {
  assert.equal(presentations.precioPresentacion({
    presentacion: 'Caja', precio_venta: 850, unidades_por_presentacion: 10
  }), 8500);
  assert.equal(presentations.precioPresentacion({
    presentacion: 'Unidad', precio_venta: 850, unidades_por_presentacion: 10
  }), 850);
});

test('prepara una línea normal sin alterar su cantidad ni su precio', () => {
  assert.deepEqual(presentations.itemsCarritoParaGuardar({
    pid: 'p1', n: 'Producto', q: 2, p: 4500, fraccionable: false
  }), [{
    producto_id: 'p1',
    nombre: 'Producto',
    cantidad: 2,
    precio_venta: 4500,
    presentacion: 'Unidad',
    unidades_por_presentacion: 1
  }]);
});

test('separa cajas y unidades sueltas en líneas expresadas en unidades base', () => {
  assert.deepEqual(presentations.itemsCarritoParaGuardar({
    pid: 'p2',
    n: 'Producto fraccionable',
    fraccionable: true,
    cajas: 1,
    unidadesCaja: 10,
    precioCaja: 10000,
    unidades: 3,
    precioUnidad: 1200
  }), [
    {
      producto_id: 'p2',
      nombre: 'Producto fraccionable',
      cantidad: 10,
      precio_venta: 1000,
      presentacion: 'Caja',
      unidades_por_presentacion: 10
    },
    {
      producto_id: 'p2',
      nombre: 'Producto fraccionable',
      cantidad: 3,
      precio_venta: 1200,
      presentacion: 'Unidad',
      unidades_por_presentacion: 1
    }
  ]);
});

test('no genera líneas vacías si el carrito fraccionable está en cero', () => {
  assert.deepEqual(presentations.itemsCarritoParaGuardar({
    pid: 'p3', n: 'Producto', fraccionable: true,
    cajas: 0, unidadesCaja: 10, precioCaja: 10000,
    unidades: 0, precioUnidad: 1000
  }), []);
});
