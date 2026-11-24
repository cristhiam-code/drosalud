'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/pedidos.js');

const service = global.window.DrosaludOrdersService;

test('encapsula las cinco RPC del flujo de pedidos y conserva sus argumentos', async () => {
  const calls = [];
  const client = {
    async rpc(name, args) {
      calls.push({ name, args });
      return { data: name === 'guardar_pedido' ? 'pedido-1' : { ok: true }, error: null };
    }
  };
  const items = [{ producto_id: 'p1', cantidad_solicitada: 3 }];
  const allocations = [{ pedido_item_id: 'pi1', proveedor_id: 'pr1', unidades: 3, costo_unitario_base: 1000 }];

  assert.equal(await service.guardarPedido(client, {
    p_pedido_id: null, p_tipo: 'sugerido', p_notas: null, p_items: items
  }), 'pedido-1');
  await service.enviarPedido(client, 'pedido-1');
  await service.autorizarPedido(client, { p_pedido_id: 'pedido-1', p_items: items });
  await service.rechazarPedido(client, { p_pedido_id: 'pedido-2', p_motivo: 'Duplicado' });
  await service.generarOrdenesCompra(client, {
    p_pedido_id: 'pedido-1', p_asignaciones: allocations, p_operacion_id: 'op-1'
  });

  assert.deepEqual(calls, [
    { name: 'guardar_pedido', args: { p_pedido_id: null, p_tipo: 'sugerido', p_notas: null, p_items: items } },
    { name: 'enviar_pedido', args: { p_pedido_id: 'pedido-1' } },
    { name: 'autorizar_pedido', args: { p_pedido_id: 'pedido-1', p_items: items } },
    { name: 'rechazar_pedido', args: { p_pedido_id: 'pedido-2', p_motivo: 'Duplicado' } },
    { name: 'generar_ordenes_compra_pedido', args: {
      p_pedido_id: 'pedido-1', p_asignaciones: allocations, p_operacion_id: 'op-1'
    }}
  ]);
});

test('propaga el error del backend y exige cliente Supabase', async () => {
  const error = new Error('pedido rechazado');
  const client = { async rpc() { return { data: null, error }; } };
  await assert.rejects(service.autorizarPedido(client, {}), value => value === error);
  await assert.rejects(service.guardarPedido(null, {}), /cliente Supabase válido/);
});
