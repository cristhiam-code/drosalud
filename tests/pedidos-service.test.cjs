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

function createReadClient(rows) {
  const tables = [];
  const client = {
    tables,
    from(table) {
      tables.push(table);
      const query = {
        select() { return this; }, eq() { return this; }, neq() { return this; },
        gte() { return this; }, lte() { return this; }, in() { return this; },
        order() { return this; }, range() { return this; },
        maybeSingle() { return Promise.resolve({ data: rows[table] ?? null, error: null }); },
        then(resolve, reject) {
          return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject);
        }
      };
      return query;
    }
  };
  return client;
}

test('carga los datos de pantalla y el perfil a través del servicio', async () => {
  const rows = {
    usuarios_drosalud: { rol: 'admin', activo: true },
    productos_app: [{ id: 'p1' }],
    proveedores: [{ id: 'pr1' }],
    pedidos_resumen: [{ id: 'pedido1' }],
    inventario_saldos: [{ producto_id: 'p1', saldo_unidades: -2 }],
    pedidos_items: [{ id: 'pi1' }],
    ordenes_compra: [{ id: 'oc1' }],
    ordenes_compra_items: [{ id: 'oi1' }]
  };
  const client = createReadClient(rows);
  const result = await service.cargarDatosModulo(client, 'user-1');
  assert.deepEqual(result, {
    perfil: rows.usuarios_drosalud, productos: rows.productos_app,
    proveedores: rows.proveedores, pedidos: rows.pedidos_resumen,
    saldos: rows.inventario_saldos, items: rows.pedidos_items,
    ordenes: rows.ordenes_compra, itemsOrden: rows.ordenes_compra_items
  });
  assert.ok(client.tables.includes('usuarios_drosalud'));
});

test('carga ventas, saldos y compromisos para el cálculo de pedido sugerido', async () => {
  const rows = {
    recibos_app: [{ id: 'r1' }],
    recibo_items_app: [{ producto_id: 'p1', cantidad: 2, unidades_por_presentacion: 3 }],
    inventario_saldos: [{ producto_id: 'p1', saldo_unidades: 1 }],
    ordenes_compra: [{ id: 'oc1', estado: 'aprobada' }],
    pedidos: [{ id: 'pedido1' }],
    ordenes_compra_items: [{ orden_id: 'oc1', pedido_item_id: 'pi1', producto_id: 'p1', unidades_solicitadas: 4, unidades_recibidas: 1 }],
    pedidos_items: [{ id: 'pi2', producto_id: 'p1', cantidad_autorizada: 3 }]
  };
  const result = await service.cargarDatosSugerencia(createReadClient(rows), 'desde', 'hasta');
  assert.deepEqual(result.lineasRecibo, rows.recibo_items_app);
  assert.deepEqual(result.saldos, rows.inventario_saldos);
  assert.deepEqual(result.itemsOrden, rows.ordenes_compra_items);
  assert.deepEqual(result.itemsAutorizados, rows.pedidos_items);
});

test('rechaza una dependencia de lectura ausente', async () => {
  await assert.rejects(service.cargarDatosModulo(null, 'user-1'), /cliente Supabase válido/);
  await assert.rejects(service.cargarDatosSugerencia(null, 'desde', 'hasta'), /cliente Supabase válido/);
});
