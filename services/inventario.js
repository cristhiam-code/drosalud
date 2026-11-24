/* Lecturas de inventario para Kardex y consulta semanal de ventas. */
(() => {
  'use strict';

  function validar(cliente) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de inventario requiere un cliente Supabase válido.');
    }
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
      desde += pagina.length;
    }
    return filas;
  }

  async function listarProductosConLinea(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('productos_app')
      .select('id,codigo,nombre,laboratorio,linea,unidades_por_caja')
      .order('nombre').order('id'));
  }

  async function listarProductosSinLinea(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('productos_app')
      .select('id,codigo,nombre,laboratorio,unidades_por_caja')
      .order('nombre').order('id'));
  }

  async function listarSaldos(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('inventario_saldos')
      .select('producto_id,saldo_unidades').order('producto_id'));
  }

  async function listarVentasSemana(cliente, inicio, fin) {
    validar(cliente);
    const recibos = await obtenerTodas(() => cliente.from('recibos_app').select('id')
      .eq('anulado', false).gte('creado_en', inicio).lt('creado_en', fin)
      .order('creado_en').order('id'));
    const lineas = [];
    for (let offset = 0; offset < recibos.length; offset += 100) {
      const ids = recibos.slice(offset, offset + 100).map(recibo => recibo.id);
      if (!ids.length) continue;
      const filas = await obtenerTodas(() => cliente.from('recibo_items_app')
        .select('producto_id,cantidad,unidades_por_presentacion')
        .in('recibo_id', ids).order('id'));
      lineas.push(...filas);
    }
    return lineas;
  }

  async function comprobarPedidos(cliente) {
    validar(cliente);
    const { error } = await cliente.from('pedidos_resumen').select('id').limit(1);
    if (error) throw error;
  }


  async function registrarRecepcion(cliente, argumentos) {
    validar(cliente);
    if (typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de inventario requiere un cliente Supabase con RPC.');
    }
    const { data, error } = await cliente.rpc('registrar_recepcion_inventario', argumentos);
    if (error) throw error;
    return data;
  }

  window.DrosaludInventoryService = Object.freeze({
    listarProductosConLinea, listarProductosSinLinea, listarSaldos,
    listarVentasSemana, comprobarPedidos, registrarRecepcion
  });
})();
