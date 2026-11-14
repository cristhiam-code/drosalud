/* Operación de despachos desde bodega central y recepción en sucursal. */
(() => {
  'use strict';
  const pending = new Map();

  function operationFor(key, payload) {
    const signature = JSON.stringify(payload);
    const current = pending.get(key);
    if (current?.signature === signature) return current.id;
    const id = window.crypto?.randomUUID
      ? window.crypto.randomUUID()
      : 'ps-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
    pending.set(key, { signature, id });
    return id;
  }

  async function despachar(pedidoId, pedidos) {
    const pedido = pedidos.find(row => row.id === pedidoId);
    if (!pedido) throw new Error('No se encontró el pedido.');
    const items = (pedido.items || []).filter(item =>
      Number(item.cantidad_autorizada) > Number(item.cantidad_despachada || 0)
    ).map(item => ({
      pedido_item_id: item.id,
      unidades_despachadas: Number(item.cantidad_autorizada) - Number(item.cantidad_despachada || 0)
    }));
    if (!items.length) throw new Error('No hay unidades autorizadas pendientes de despacho.');
    const operationId = operationFor('despacho:' + pedidoId, items);
    const result = await window.PedidosSucursalesAPI.despachar(pedidoId, items, null, operationId);
    pending.delete('despacho:' + pedidoId);
    return result;
  }

  async function confirmarRecepcion(despachoId, pedidos, root) {
    const pedido = pedidos.find(row => (row.despachos || []).some(d => d.id === despachoId));
    const despacho = pedido?.despachos?.find(d => d.id === despachoId);
    if (!despacho) throw new Error('No se encontró el despacho.');
    const items = window.PedidosSucursalesHistorial.receiptItems(root, despacho);
    const operationId = operationFor('recepcion:' + despachoId, items);
    const result = await window.PedidosSucursalesAPI.confirmarRecepcion(despachoId, items, null, operationId);
    pending.delete('recepcion:' + despachoId);
    return result;
  }

  window.PedidosSucursalesDespachos = Object.freeze({ despachar, confirmarRecepcion });
})();
