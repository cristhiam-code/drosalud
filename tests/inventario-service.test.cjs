'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/inventario.js');
const service = global.window.DrosaludInventoryService;

function clientMock(rows = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      const q = { table, filters: [] };
      return {
        select(value) { q.selection = value; return this; },
        order(...args) { q.order = args; return this; },
        eq(...args) { q.filters.push(['eq', ...args]); return this; },
        gte(...args) { q.filters.push(['gte', ...args]); return this; },
        lt(...args) { q.filters.push(['lt', ...args]); return this; },
        in(...args) { q.filters.push(['in', ...args]); return this; },
        limit(value) { q.limit = value; return this; },
        range(...args) { q.range = args; return this; },
        then(resolve, reject) {
          calls.push({ ...q });
          return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject);
        }
      };
    }
  };
}

test('consulta catálogo con y sin columna de línea', async () => {
  const client = clientMock({ productos_app: [{ id: 'p1', nombre: 'Producto' }] });
  assert.deepEqual(await service.listarProductosConLinea(client), [{ id: 'p1', nombre: 'Producto' }]);
  assert.deepEqual(await service.listarProductosSinLinea(client), [{ id: 'p1', nombre: 'Producto' }]);
  assert.ok(client.calls[0].selection.includes('linea'));
  assert.ok(!client.calls[1].selection.includes('linea'));
});

test('consulta saldos y ventas dentro de la semana solicitada', async () => {
  const client = clientMock({
    inventario_saldos: [{ producto_id: 'p1', saldo_unidades: 4 }],
    recibos_app: [{ id: 'r1' }],
    recibo_items_app: [{ producto_id: 'p1', cantidad: 2, unidades_por_presentacion: 5 }]
  });
  assert.deepEqual(await service.listarSaldos(client), [{ producto_id: 'p1', saldo_unidades: 4 }]);
  const items = await service.listarVentasSemana(client, 'lunes', 'siguiente-lunes');
  assert.deepEqual(items, [{ producto_id: 'p1', cantidad: 2, unidades_por_presentacion: 5 }]);
  const receiptQuery = client.calls.find(call => call.table === 'recibos_app');
  assert.ok(receiptQuery.filters.some(filter => filter[0] === 'gte' && filter[2] === 'lunes'));
  assert.ok(receiptQuery.filters.some(filter => filter[0] === 'lt' && filter[2] === 'siguiente-lunes'));
});

test('valida la tabla de pedidos para diagnóstico del módulo', async () => {
  const client = clientMock({ pedidos_resumen: [] });
  await service.comprobarPedidos(client);
  assert.equal(client.calls[0].table, 'pedidos_resumen');
  assert.equal(client.calls[0].limit, 1);
});

test('rechaza cliente inválido y propaga errores de consulta', async () => {
  await assert.rejects(service.listarSaldos(null), /cliente Supabase válido/);
  const error = new Error('esquema no instalado');
  const client = { from() { return { select() { return this; }, order() { return this; }, range() { return Promise.resolve({ data: null, error }); } }; } };
  await assert.rejects(service.listarSaldos(client), value => value === error);
});
