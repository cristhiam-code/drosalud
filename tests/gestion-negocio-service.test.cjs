'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/gestion-negocio.js');
const service = global.window.DrosaludBusinessManagementService;

function clientMock() {
  const calls = [];
  const client = {
    calls,
    from(table) {
      const query = { table, operation: 'select', filters: [] };
      const chain = {
        select(value) { query.selection = value; return this; },
        order(...args) { query.order = args; return this; },
        eq(...args) { query.filters.push(['eq', ...args]); return this; },
        update(value) { query.operation = 'update'; query.value = value; return this; },
        insert(value) { query.operation = 'insert'; query.value = value; return this; },
        delete() { query.operation = 'delete'; return this; },
        single() { calls.push({ ...query }); return Promise.resolve({ data: { id: 'new-id' }, error: null }); },
        maybeSingle() { calls.push({ ...query }); return Promise.resolve({ data: { id: 'existing-id' }, error: null }); },
        limit(value) { query.limit = value; return this; },
        then(resolve, reject) {
          calls.push({ ...query });
          return Promise.resolve({ data: [], error: null }).then(resolve, reject);
        }
      };
      return chain;
    },
    async rpc(name, args) { calls.push({ rpc: name, args }); return { data: { ok: true }, error: null }; }
  };
  return client;
}

test('carga proveedores, compras y cotizaciones del usuario', async () => {
  const client = clientMock();
  const result = await service.cargar(client, 'user-1');
  assert.deepEqual(result, { proveedores: [], compras: [], cotizaciones: [] });
  assert.deepEqual(client.calls.map(call => call.table), [
    'proveedores', 'compras_pendientes', 'cotizaciones_proveedor'
  ]);
  assert.ok(client.calls.some(call => call.filters?.some(filter => filter[1] === 'owner_id' && filter[2] === 'user-1')));
});

test('encapsula altas, edición y eliminación de proveedores', async () => {
  const client = clientMock();
  const row = { owner_id: 'user-1', nombre: 'Proveedor' };
  await service.guardarProveedor(client, row, null, 'user-1');
  await service.guardarProveedor(client, row, 'provider-1', 'user-1');
  await service.eliminarProveedor(client, 'provider-1', 'user-1');
  assert.deepEqual(client.calls.map(call => call.operation), ['insert', 'update', 'delete']);
});

test('conserva las dos RPC de compras y sus argumentos', async () => {
  const client = clientMock();
  const args = { p_producto_nombre: 'Producto', p_costo_real: 1200 };
  await service.guardarCompra(client, true, args);
  await service.guardarCompra(client, false, args);
  assert.deepEqual(client.calls.map(call => call.rpc), [
    'guardar_compra_con_costo_real', 'guardar_compra_pendiente'
  ]);
  assert.deepEqual(client.calls[0].args, args);
});

test('consulta recibos, líneas y registra cotizaciones', async () => {
  const client = clientMock();
  await service.listarRecibos(client);
  await service.listarLineasRecibo(client, 'receipt-1');
  await service.registrarCotizacion(client, { owner_id: 'user-1', precio_unitario: 1000 });
  assert.deepEqual(client.calls.map(call => call.table), [
    'recibos', 'recibo_items_app', 'cotizaciones_proveedor'
  ]);
  assert.equal(client.calls[0].limit, 100);
  assert.ok(client.calls[1].filters.some(filter => filter[1] === 'recibo_id' && filter[2] === 'receipt-1'));
});

test('propaga errores y rechaza un cliente no válido', async () => {
  await assert.rejects(service.cargar(null, 'user-1'), /cliente Supabase válido/);
  const error = new Error('sin permiso');
  const broken = { from() { const q = { select() { return this; }, order() { return this; }, eq() { return this; }, then(resolve, reject) { return Promise.resolve({ data: null, error }).then(resolve, reject); } }; return q; } };
  await assert.rejects(service.cargar(broken, 'user-1'), value => value === error);
});
