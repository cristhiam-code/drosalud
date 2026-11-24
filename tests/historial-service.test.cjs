'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/historial.js');
const service = global.window.DrosaludHistoryService;

function clientMock(rows = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      const query = { table, filters: [], operation: 'select' };
      return {
        select(...args) { query.selection = args; return this; },
        order(...args) { query.order = args; return this; },
        limit(value) { query.limit = value; return this; },
        range(...args) { query.range = args; return this; },
        eq(...args) { query.filters.push(['eq', ...args]); return this; },
        gte(...args) { query.filters.push(['gte', ...args]); return this; },
        lt(...args) { query.filters.push(['lt', ...args]); return this; },
        in(...args) { query.filters.push(['in', ...args]); return this; },
        update(value) { query.operation = 'update'; query.value = value; return this; },
        delete() { query.operation = 'delete'; return this; },
        maybeSingle() { calls.push({ ...query }); return Promise.resolve({ data: { id: 'r1' }, error: null }); },
        then(resolve, reject) {
          calls.push({ ...query });
          return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject);
        }
      };
    }
  };
}

test('consulta cotizaciones y sus líneas', async () => {
  const client = clientMock({
    cotizaciones_venta_app: [{ id: 'c1' }],
    cotizacion_venta_items_app: [{ id: 'i1', cotizacion_id: 'c1' }]
  });
  assert.deepEqual(await service.listarCotizaciones(client), [{ id: 'c1' }]);
  assert.deepEqual(await service.listarLineasCotizacion(client, 'c1'), [{ id: 'i1', cotizacion_id: 'c1' }]);
});

test('elimina y anula recibos manteniendo el contrato de confirmación', async () => {
  const client = clientMock();
  await service.eliminarRecibo(client, 'r1');
  const changes = { anulado: true, motivo_anulacion: 'Error de producto' };
  await service.anularRecibo(client, 'r1', changes);
  assert.deepEqual(client.calls.map(call => call.operation), ['delete', 'update']);
  assert.deepEqual(client.calls[1].value, changes);
});

test('consulta ventas por período y obtiene líneas en lotes', async () => {
  const client = clientMock({
    recibos_app: [{ id: 'r1' }, { id: 'r2' }],
    recibo_items_app: [{ id: 'i1' }]
  });
  const receipts = await service.listarVentasPeriodo(client, 'inicio', 'fin');
  const items = await service.listarLineasRecibos(client, receipts);
  assert.equal(receipts.length, 2);
  assert.deepEqual(items, [{ id: 'i1' }]);
  assert.ok(client.calls[0].filters.some(filter => filter[0] === 'gte'));
  assert.ok(client.calls[0].filters.some(filter => filter[0] === 'lt'));
  assert.deepEqual(client.calls[1].filters[0], ['in', 'recibo_id', ['r1', 'r2']]);
});

test('consulta detalle de recibo y cambios de precio', async () => {
  const client = clientMock({
    recibo_items_app: [{ id: 'i1' }],
    historial_precios: [{ id: 'h1' }]
  });
  assert.deepEqual(await service.listarLineasRecibo(client, 'r1'), [{ id: 'i1' }]);
  assert.deepEqual(await service.listarCambiosPrecio(client), [{ id: 'h1' }]);
});

test('rechaza cliente inválido y propaga errores', async () => {
  await assert.rejects(service.listarCotizaciones(null), /cliente Supabase válido/);
  const error = new Error('sin acceso');
  const client = {
    from() {
      const chain = { select() { return this; }, order() { return this; }, limit() { return this; }, then(resolve, reject) { return Promise.resolve({ data: null, error }).then(resolve, reject); } };
      return chain;
    }
  };
  await assert.rejects(service.listarCotizaciones(client), value => value === error);
});
