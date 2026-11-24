'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/caja.js');

const service = global.window.DrosaludCashService;

function fakeClient(rows = []) {
  const calls = [];
  const client = {
    calls,
    async rpc(name, args) {
      calls.push({ type: 'rpc', name, args });
      return { data: { ok: true }, error: null };
    },
    from(table) {
      calls.push({ type: 'from', table });
      const query = {
        select(columns) { calls.push({ type: 'select', columns }); return query; },
        eq(column, value) { calls.push({ type: 'eq', column, value }); return query; },
        order(column, options) { calls.push({ type: 'order', column, options }); return query; },
        limit(value) { calls.push({ type: 'limit', value }); return query; },
        then(resolve, reject) { return Promise.resolve({ data: rows, error: null }).then(resolve, reject); }
      };
      return query;
    }
  };
  return client;
}

test('encapsula los RPC de caja y conserva nombres y argumentos', async () => {
  const client = fakeClient();
  await service.jornadasPendientes(client);
  await service.resumen(client, '2026-11-24');
  await service.registrarGasto(client, {
    fecha: '2026-11-24', concepto: 'Transporte', monto: 5000,
    formaPago: 'Efectivo', categoria: 'Operación'
  });
  await service.anularGasto(client, 'g1', 'Registro duplicado');
  await service.cerrarJornada(client, {
    fecha: '2026-11-24', base: 10000, contado: 15000, notas: 'Cierre revisado'
  });
  await service.reabrirJornada(client, '2026-11-24', 'Corrección autorizada');

  assert.deepEqual(client.calls.filter(x => x.type === 'rpc'), [
    { type: 'rpc', name: 'jornadas_pendientes_drosalud', args: undefined },
    { type: 'rpc', name: 'resumen_caja_drosalud', args: { p_fecha: '2026-11-24' } },
    { type: 'rpc', name: 'registrar_gasto_drosalud', args: {
      p_fecha: '2026-11-24', p_concepto: 'Transporte', p_monto: 5000,
      p_forma_pago: 'Efectivo', p_categoria: 'Operación'
    }},
    { type: 'rpc', name: 'anular_gasto_drosalud', args: { p_id: 'g1', p_motivo: 'Registro duplicado' } },
    { type: 'rpc', name: 'cerrar_caja_drosalud', args: {
      p_fecha: '2026-11-24', p_base: 10000, p_contado: 15000, p_notas: 'Cierre revisado'
    }},
    { type: 'rpc', name: 'reabrir_caja_drosalud', args: {
      p_fecha: '2026-11-24', p_motivo: 'Corrección autorizada'
    }}
  ]);
});

test('lista gastos, cierres e historial con los filtros y límites esperados', async () => {
  const rows = [{ id: 'x1' }];
  const client = fakeClient(rows);

  assert.deepEqual(await service.listarGastos(client, '2026-11-24'), rows);
  assert.deepEqual(await service.listarCierres(client), rows);
  assert.deepEqual(await service.listarHistorial(client), rows);

  assert.deepEqual(client.calls.filter(x => x.type === 'from').map(x => x.table), [
    'gastos', 'cierres_caja', 'cierres_caja_historial'
  ]);
  assert.deepEqual(client.calls.filter(x => x.type === 'limit').map(x => x.value), [500, 100]);
});

test('propaga los errores del cliente y rechaza una dependencia inválida', async () => {
  const error = new Error('error de caja');
  const client = fakeClient();
  client.rpc = async () => ({ data: null, error });
  await assert.rejects(service.resumen(client, '2026-11-24'), value => value === error);
  await assert.rejects(service.jornadasPendientes(null), /cliente Supabase válido/);
});
