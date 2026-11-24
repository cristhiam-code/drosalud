'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/catalogo.js');
const service = global.window.DrosaludCatalogService;

function makeClient() {
  const calls = [];
  const client = {
    calls,
    from(table) {
      const query = { table, operation: 'select', filters: [] };
      return {
        select(...args) { query.selection = args; return this; },
        update(value) { query.operation = 'update'; query.value = value; return this; },
        insert(value) { query.operation = 'insert'; query.value = value; return this; },
        delete() { query.operation = 'delete'; return this; },
        eq(...args) { query.filters.push(args); return this; },
        order(...args) { query.order = args; return this; },
        limit(value) { query.limit = value; return this; },
        maybeSingle() { calls.push({ ...query }); return Promise.resolve({ data: { id: 'p1' }, error: null }); },
        single() { calls.push({ ...query }); return Promise.resolve({ data: { id: 'p1', nombre: 'Producto' }, error: null }); },
        then(resolve, reject) {
          calls.push({ ...query });
          return Promise.resolve({ data: [], count: 12, error: null }).then(resolve, reject);
        }
      };
    },
    async rpc(name, args) { calls.push({ rpc: name, args }); return { data: { ok: true, precio_compra: 1000, precio_venta: 1300 }, error: null }; }
  };
  return client;
}

test('mantiene los contratos RPC de precios y fraccionamiento', async () => {
  const client = makeClient();
  const priceArgs = { p_producto_id: 'p1', p_precio_compra: 1000, p_precio_venta: 1300, p_motivo: 'Factura' };
  const fractionArgs = { p_producto_id: 'p1', p_unidades_por_caja: 20, p_unidades_por_venta: 1 };
  assert.equal((await service.actualizarPrecios(client, priceArgs)).precio_venta, 1300);
  assert.equal((await service.habilitarFraccionamiento(client, fractionArgs)).ok, true);
  assert.deepEqual(client.calls.map(call => call.rpc), [
    'actualizar_precios_drosalud_con_motivo', 'habilitar_fraccionamiento_producto'
  ]);
  assert.deepEqual(client.calls[0].args, priceArgs);
  assert.deepEqual(client.calls[1].args, fractionArgs);
});

test('encapsula crear, actualizar y eliminar productos', async () => {
  const client = makeClient();
  await service.actualizarProducto(client, 'p1', { nombre: 'Actualizado' });
  const created = await service.crearProducto(client, { nombre: 'Producto' });
  await service.eliminarProducto(client, 'p1');
  assert.equal(created.id, 'p1');
  assert.deepEqual(client.calls.map(call => call.operation), ['update', 'insert', 'delete']);
});

test('consulta auditoría, cuenta e importa productos', async () => {
  const client = makeClient();
  assert.deepEqual(await service.listarAuditoriaProducto(client, 'p1'), []);
  assert.equal(await service.contarProductos(client), 12);
  await service.importarProductos(client, [{ nombre: 'A' }, { nombre: 'B' }]);
  assert.deepEqual(client.calls.map(call => call.table), [
    'auditoria_precios', 'productos', 'productos'
  ]);
  assert.equal(client.calls[0].limit, 12);
  assert.equal(client.calls[2].value.length, 2);
});

test('rechaza cliente inválido y propaga errores de backend', async () => {
  await assert.rejects(service.contarProductos(null), /cliente Supabase válido/);
  const error = new Error('sin autorización');
  const client = { rpc: async () => ({ data: null, error }) };
  await assert.rejects(service.actualizarPrecios(client, {}), value => value === error);
});
