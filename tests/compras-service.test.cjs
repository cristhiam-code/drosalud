'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/compras.js');

const service = global.window.DrosaludPurchasesService;

test('registra documento de proveedor con los argumentos recibidos', async () => {
  const calls = [];
  const client = { async rpc(name, args) { calls.push({ name, args }); return { data: { id: 'd1' }, error: null }; } };
  const args = { p_orden_id: 'o1', p_tipo_documento: 'factura', p_items: [{ producto_id: 'p1' }] };

  const result = await service.registrarDocumentoProveedor(client, args);

  assert.deepEqual(result, { id: 'd1' });
  assert.deepEqual(calls, [{ name: 'registrar_documento_proveedor', args }]);
});

test('registra recepción documentada sin alterar clave de idempotencia ni notas', async () => {
  const calls = [];
  const client = { async rpc(name, args) { calls.push({ name, args }); return { data: { id: 'r1' }, error: null }; } };
  const args = {
    p_orden_id: 'o1', p_documento_id: 'd1',
    p_items: [{ orden_item_id: 'oi1', cantidad: 2 }],
    p_operacion_id: 'op-unique', p_notas: 'Diferencia autorizada'
  };

  const result = await service.registrarRecepcionDocumentada(client, args);

  assert.deepEqual(result, { id: 'r1' });
  assert.deepEqual(calls, [{ name: 'registrar_recepcion_compra_documentada', args }]);
});

test('propaga errores del backend y exige cliente Supabase', async () => {
  const error = new Error('recepción rechazada');
  const client = { async rpc() { return { data: null, error }; } };
  await assert.rejects(service.registrarRecepcionDocumentada(client, {}), value => value === error);
  await assert.rejects(service.registrarDocumentoProveedor(null, {}), /cliente Supabase válido/);
});

test('lista compras y arma documentos con líneas y órdenes vinculadas', async () => {
  const rows = {
    ordenes_compra: [{ id: 'oc1' }],
    documentos_proveedor: [{ id: 'doc1', numero_documento: 'F-1' }],
    documentos_proveedor_items: [{ id: 'linea1', documento_id: 'doc1', producto_id: 'p1' }],
    recepciones_compra: [{ id: 'rec1' }],
    historial_costos: [{ id: 'costo1' }],
    auditoria_precios: [{ id: 'aud1' }],
    documentos_proveedor_ordenes: [{ documento_id: 'doc1', orden_id: 'oc1' }]
  };
  const calls = [];
  const client = {
    from(table) {
      const query = {
        select(value) { calls.push([table, 'select', value]); return this; },
        in(...args) { calls.push([table, 'in', ...args]); return this; },
        order(...args) { calls.push([table, 'order', ...args]); return this; },
        limit(value) { calls.push([table, 'limit', value]); return this; },
        then(resolve, reject) { return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject); }
      };
      return query;
    }
  };

  const result = await service.listarDatos(client, true);

  assert.deepEqual(result.ordenes, rows.ordenes_compra);
  assert.deepEqual(result.recepciones, rows.recepciones_compra);
  assert.deepEqual(result.costos, rows.historial_costos);
  assert.deepEqual(result.auditoria, rows.auditoria_precios);
  assert.deepEqual(result.documentos, [{
    ...rows.documentos_proveedor[0],
    items: rows.documentos_proveedor_items,
    ordenes: ['oc1']
  }]);
  assert.ok(calls.some(([table]) => table === 'auditoria_precios'));
});

test('omite la auditoría de precios para perfiles no administradores', async () => {
  const tables = [];
  const client = {
    from(table) {
      tables.push(table);
      const query = {
        select() { return this; }, in() { return this; }, order() { return this; }, limit() { return this; },
        then(resolve, reject) { return Promise.resolve({ data: [], error: null }).then(resolve, reject); }
      };
      return query;
    }
  };
  const result = await service.listarDatos(client, false);
  assert.deepEqual(result.auditoria, []);
  assert.ok(!tables.includes('auditoria_precios'));
  await assert.rejects(service.listarDatos(null, false), /cliente Supabase válido/);
});
