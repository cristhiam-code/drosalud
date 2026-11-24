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
