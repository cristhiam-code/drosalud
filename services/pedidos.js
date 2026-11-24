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


  async function obtenerTodas(consulta) {
    const filas = [];
    let desde = 0;
    while (true) {
      const { data, error } = await consulta().range(desde, desde + 999);
      if (error) throw error;
      const pagina = data || [];
      filas.push(...pagina);
      if (pagina.length < 1000) break;
      desde += 1000;
    }
    return filas;
  }

  async function cargarDatosModulo(cliente, userId) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de pedidos requiere un cliente Supabase válido.');
    }
    const perfil = await cliente.from('usuarios_drosalud')
      .select('rol,activo').eq('user_id', userId).maybeSingle();
    if (perfil.error) throw perfil.error;

    const [productos, proveedores, pedidos, saldos] = await Promise.all([
      obtenerTodas(() => cliente.from('productos_app')
        .select('id,codigo,nombre,laboratorio,precio_compra,unidades_por_caja,unidades_por_venta')
        .order('nombre').order('id')),
      obtenerTodas(() => cliente.from('proveedores').select('id,nombre,activo')
        .eq('activo', true).order('nombre')),
      obtenerTodas(() => cliente.from('pedidos_resumen').select('*').order('creado_en', { ascending:false })),
      obtenerTodas(() => cliente.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id'))
    ]);
    const ids = pedidos.map(pedido => pedido.id);
    const items = ids.length ? await obtenerTodas(() => cliente.from('pedidos_items')
      .select('*').in('pedido_id', ids).order('creado_en')) : [];
    const ordenes = ids.length ? await obtenerTodas(() => cliente.from('ordenes_compra')
      .select('id,numero,pedido_id,proveedor_id,estado,creado_en')
      .in('pedido_id', ids).order('creado_en', { ascending:false })) : [];
    const ordenIds = ordenes.map(orden => orden.id);
    const itemsOrden = ordenIds.length ? await obtenerTodas(() => cliente.from('ordenes_compra_items')
      .select('id,orden_id,pedido_item_id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base')
      .in('orden_id', ordenIds).order('creado_en')) : [];
    return { perfil: perfil.data, productos, proveedores, pedidos, saldos, items, ordenes, itemsOrden };
  }

  async function cargarDatosSugerencia(cliente, desde, hasta) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de pedidos requiere un cliente Supabase válido.');
    }
    const recibos = await obtenerTodas(() => cliente.from('recibos_app')
      .select('id').eq('anulado', false).gte('creado_en', desde)
      .lte('creado_en', hasta).order('creado_en').order('id'));
    const lotes = [];
    for (let offset = 0; offset < recibos.length; offset += 100) {
      lotes.push(recibos.slice(offset, offset + 100).map(row => row.id));
    }
    const lineasRecibo = (await Promise.all(lotes.map(ids => obtenerTodas(() =>
      cliente.from('recibo_items_app').select('producto_id,cantidad,unidades_por_presentacion')
        .in('recibo_id', ids).order('id')
    )))).flat();
    const [saldos, ordenes, pedidosAutorizados] = await Promise.all([
      obtenerTodas(() => cliente.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id')),
      obtenerTodas(() => cliente.from('ordenes_compra').select('id,pedido_id,estado')
        .neq('estado', 'cancelada').order('creado_en')),
      obtenerTodas(() => cliente.from('pedidos').select('id').eq('estado', 'autorizado').order('creado_en'))
    ]);
    const ordenIds = ordenes.map(orden => orden.id);
    const itemsOrden = ordenIds.length ? await obtenerTodas(() => cliente.from('ordenes_compra_items')
      .select('orden_id,pedido_item_id,producto_id,unidades_solicitadas,unidades_recibidas')
      .in('orden_id', ordenIds).order('creado_en')) : [];
    const pedidoIds = pedidosAutorizados.map(pedido => pedido.id);
    const itemsAutorizados = pedidoIds.length ? await obtenerTodas(() => cliente.from('pedidos_items')
      .select('id,producto_id,cantidad_autorizada').in('pedido_id', pedidoIds).order('creado_en')) : [];
    return { recibos, lineasRecibo, saldos, ordenes, itemsOrden, pedidosAutorizados, itemsAutorizados };
  }

  window.DrosaludOrdersService = Object.freeze({
    cargarDatosModulo,
    cargarDatosSugerencia,
    guardarPedido: (cliente, argumentos) => ejecutar(cliente, 'guardar_pedido', argumentos),
    enviarPedido: (cliente, pedidoId) => ejecutar(cliente, 'enviar_pedido', { p_pedido_id: pedidoId }),
    autorizarPedido: (cliente, argumentos) => ejecutar(cliente, 'autorizar_pedido', argumentos),
    rechazarPedido: (cliente, argumentos) => ejecutar(cliente, 'rechazar_pedido', argumentos),
    generarOrdenesCompra: (cliente, argumentos) =>
      ejecutar(cliente, 'generar_ordenes_compra_pedido', argumentos)
  });
})();
