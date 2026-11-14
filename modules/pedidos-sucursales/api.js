/* API del módulo Pedidos de Sucursales.
 * Todas las operaciones de negocio se ejecutan mediante RPC en PostgreSQL.
 * Este archivo no contiene reglas de autorización en el cliente.
 */
(() => {
  'use strict';

  async function rpc(name, params = {}) {
    if (typeof sb === 'undefined' || !sb?.rpc) {
      throw new Error('La conexión con la base de datos no está disponible.');
    }
    const { data, error } = await sb.rpc(name, params);
    if (error) throw error;
    return data;
  }

  function rows(data) {
    if (Array.isArray(data)) return data;
    if (Array.isArray(data?.items)) return data.items;
    if (Array.isArray(data?.pedidos)) return data.pedidos;
    return [];
  }

  window.PedidosSucursalesAPI = Object.freeze({
    contexto: () => rpc('ps_obtener_contexto'),
    configuracion: () => rpc('ps_admin_listar_configuracion'),
    crearSucursal: (codigo, nombre) => rpc('ps_admin_crear_sucursal', { p_codigo: codigo, p_nombre: nombre }),
    asignarUsuario: (userId, sucursalId) => rpc('ps_admin_asignar_usuario', { p_user_id: userId, p_sucursal_id: sucursalId }),
    configurarDias: (sucursalId, dias) => rpc('ps_admin_configurar_dias', { p_sucursal_id: sucursalId, p_dias: dias }),
    sugerido: async () => rows(await rpc('ps_obtener_pedido_sugerido')),
    negativos: async () => rows(await rpc('ps_obtener_productos_negativos')),
    pedidos: async filtro => rows(await rpc('ps_listar_pedidos_sucursal', {
      p_filtro: filtro || 'historial'
    })),
    crear: (tipo, items, notas = null) => rpc('ps_crear_pedido_sucursal', {
      p_tipo: tipo,
      p_items: items,
      p_notas: notas
    }),
    autorizar: (pedidoId, items) => rpc('ps_autorizar_pedido_sucursal', {
      p_pedido_id: pedidoId,
      p_items: items
    }),
    rechazar: (pedidoId, motivo) => rpc('ps_rechazar_pedido_sucursal', {
      p_pedido_id: pedidoId,
      p_motivo: motivo
    }),
    despachar: (pedidoId, items, notas = null) => rpc('ps_registrar_despacho_sucursal', {
      p_pedido_id: pedidoId,
      p_items: items,
      p_notas: notas
    }),
    confirmarRecepcion: (despachoId, items, notas = null) => rpc('ps_confirmar_recepcion_sucursal', {
      p_despacho_id: despachoId,
      p_items: items,
      p_notas: notas
    })
  });
})();
