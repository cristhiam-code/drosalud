'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/informes.js');

const service = global.window.DrosaludReportsService;

function fakeClient(data = {}, errors = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      calls.push({ type: 'from', table });
      const query = {
        select(columns) { calls.push({ type: 'select', table, columns }); return query; },
        order(column, options) { calls.push({ type: 'order', table, column, options }); return query; },
        not(column, operator, value) { calls.push({ type: 'not', table, column, operator, value }); return query; },
        range(start, end) {
          calls.push({ type: 'range', table, start, end });
          if (errors[table]) return Promise.resolve({ data: null, error: errors[table] });
          const rows = data[table] || [];
          return Promise.resolve({ data: rows.slice(start, end + 1), error: null });
        }
      };
      return query;
    }
  };
}

test('carga catálogo, saldos, costos de movimientos e historial', async () => {
  const client = fakeClient({
    productos_app: [{ id: 'p1', nombre: 'Producto' }],
    inventario_saldos: [{ producto_id: 'p1', saldo_unidades: 4 }],
    inventario_movimientos: [{ producto_id: 'p1', costo_unitario_base: 200, creado_en: '2026-11-20' }],
    historial_costos: [{ producto_id: 'p1', costo_unitario_base: 190, registrado_en: '2026-11-19' }]
  });

  const result = await service.loadInventory(client);

  assert.equal(result.products.length, 1);
  assert.equal(result.balances[0].saldo_unidades, 4);
  assert.equal(result.movements[0].costo_unitario_base, 200);
  assert.equal(result.history[0].costo_unitario_base, 190);
  assert.equal(result.warning, '');
});

test('lee más de 1000 filas en páginas sin perder registros', async () => {
  const products = Array.from({ length: 1001 }, (_, i) => ({ id: 'p' + i }));
  const client = fakeClient({ productos_app: products });

  const result = await service.loadInventory(client);

  assert.equal(result.products.length, 1001);
  assert.deepEqual(
    client.calls.filter(x => x.type === 'range' && x.table === 'productos_app').map(x => [x.start, x.end]),
    [[0, 999], [1000, 1999]]
  );
});

test('si falla el costo de movimientos usa catálogo y devuelve advertencia', async () => {
  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    const client = fakeClient(
      { productos_app: [], inventario_saldos: [], historial_costos: [] },
      { inventario_movimientos: new Error('sin permiso') }
    );
    const result = await service.loadInventory(client);
    assert.deepEqual(result.movements, []);
    assert.match(result.warning, /costo de los movimientos/);
  } finally {
    console.warn = originalWarn;
  }
});

test('si falla historial de costos no bloquea el informe', async () => {
  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    const client = fakeClient(
      { productos_app: [], inventario_saldos: [], inventario_movimientos: [] },
      { historial_costos: new Error('historial no disponible') }
    );
    const result = await service.loadInventory(client);
    assert.deepEqual(result.history, []);
    assert.equal(result.warning, '');
  } finally {
    console.warn = originalWarn;
  }
});

test('un error en catálogo o saldos sí detiene la carga', async () => {
  const client = fakeClient({}, { productos_app: new Error('catálogo no disponible') });
  await assert.rejects(service.loadInventory(client), /catálogo no disponible/);
});

test('requiere que el cliente Supabase sea inyectado', async () => {
  await assert.rejects(service.loadInventory(null), /cliente Supabase válido/);
});
