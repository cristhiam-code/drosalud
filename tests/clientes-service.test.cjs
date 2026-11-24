'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/clientes.js');
const service = global.window.DrosaludCustomersService;

function mockClient(rows = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      const q = { table, filters: [], operation: 'select' };
      return {
        select(...args) { q.selection = args; return this; },
        order(...args) { q.order = args; return this; },
        range(...args) { q.range = args; return this; },
        eq(...args) { q.filters.push(args); return this; },
        update(value) { q.operation = 'update'; q.value = value; return this; },
        insert(value) { q.operation = 'insert'; q.value = value; return this; },
        maybeSingle() { calls.push({ ...q }); return Promise.resolve({ data: { id: 'c1' }, error: null }); },
        single() { calls.push({ ...q }); return Promise.resolve({ data: { id: 'c1', nombre: 'Cliente' }, error: null }); },
        then(resolve, reject) {
          calls.push({ ...q });
          return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject);
        }
      };
    },
    async rpc(name, args) { calls.push({ rpc: name, args }); return { data: { ok: true }, error: null }; }
  };
}

test('lista clientes y consentimientos con paginación', async () => {
  const client = mockClient({ clientes: [{ id: 'c1' }], consentimientos_clientes: [{ cliente_id: 'c1' }] });
  assert.deepEqual(await service.listarClientes(client), [{ id: 'c1' }]);
  assert.deepEqual(await service.listarConsentimientos(client), [{ cliente_id: 'c1' }]);
  assert.deepEqual(client.calls.map(call => call.table), ['clientes', 'consentimientos_clientes']);
});

test('guarda y actualiza clientes y registra consentimiento', async () => {
  const client = mockClient();
  const created = await service.crearCliente(client, { nombre: 'Cliente' });
  await service.actualizarCliente(client, 'c1', { telefono: '3000000000' });
  await service.registrarConsentimiento(client, { cliente_id: 'c1', aceptado: true });
  assert.equal(created.id, 'c1');
  assert.deepEqual(client.calls.map(call => call.operation), ['insert', 'update', 'insert']);
});

test('consulta historial, detalle y resumen de compras', async () => {
  const client = mockClient({
    recibos_app: [{ id: 'r1', cliente_id: 'c1' }],
    recibo_items_app: [{ id: 'i1', recibo_id: 'r1' }]
  });
  assert.deepEqual(await service.listarComprasCliente(client, 'c1'), [{ id: 'r1', cliente_id: 'c1' }]);
  assert.deepEqual(await service.listarLineasRecibo(client, 'r1'), [{ id: 'i1', recibo_id: 'r1' }]);
  await service.cargarResumenCompras(client);
  assert.deepEqual(client.calls.map(call => call.table), ['recibos_app', 'recibo_items_app', 'recibos_app']);
});

test('anonimiza mediante la RPC administrativa sin cambiar argumentos', async () => {
  const client = mockClient();
  await service.anonimizarCliente(client, 'c1');
  assert.deepEqual(client.calls, [{ rpc: 'anonimizar_cliente_drosalud', args: { p_cliente_id: 'c1' } }]);
});

test('rechaza clientes inválidos y propaga errores del backend', async () => {
  await assert.rejects(service.listarClientes(null), /cliente Supabase válido/);
  const error = new Error('sin autorización');
  const client = { from() { const q = { select() { return this; }, order() { return this; }, range() { return this; }, then(resolve, reject) { return Promise.resolve({ data: null, error }).then(resolve, reject); } }; return q; } };
  await assert.rejects(service.listarClientes(client), value => value === error);
});
