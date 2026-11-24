/* Servicios de pedidos: RPC del flujo de compra con cliente Supabase inyectado. */
(() => {
  'use strict';

  async function ejecutar(cliente, nombre, argumentos) {
    if (!cliente || typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de pedidos requiere un cliente Supabase válido.');
    }
    const { data, error } = await cliente.rpc(nombre, argumentos);
    if (error) throw error;
    return data;
  }

  window.DrosaludOrdersService = Object.freeze({
    guardarPedido: (cliente, argumentos) => ejecutar(cliente, 'guardar_pedido', argumentos),
    enviarPedido: (cliente, pedidoId) => ejecutar(cliente, 'enviar_pedido', { p_pedido_id: pedidoId }),
    autorizarPedido: (cliente, argumentos) => ejecutar(cliente, 'autorizar_pedido', argumentos),
    rechazarPedido: (cliente, argumentos) => ejecutar(cliente, 'rechazar_pedido', argumentos),
    generarOrdenesCompra: (cliente, argumentos) =>
      ejecutar(cliente, 'generar_ordenes_compra_pedido', argumentos)
  });
})();
