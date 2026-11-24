/* Servicios de historial de ventas, cotizaciones y recibos. */
(() => {
  'use strict';

  function validar(cliente) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de historial requiere un cliente Supabase válido.');
    }
  }

  async function listarCotizaciones(cliente) {
    validar(cliente);
    const { data, error } = await cliente.from('cotizaciones_venta_app').select('*')
      .order('creado_en', { ascending:false }).order('numero', { ascending:false }).limit(500);
    if (error) throw error;
    return data || [];
  }

  async function listarLineasCotizacion(cliente, cotizacionId) {
    validar(cliente);
    const { data, error } = await cliente.from('cotizacion_venta_items_app').select('*')
      .eq('cotizacion_id', cotizacionId).order('id');
    if (error) throw error;
    return data || [];
  }

  async function eliminarRecibo(cliente, reciboId) {
    validar(cliente);
    const { error } = await cliente.from('recibos').delete().eq('id', reciboId);
    if (error) throw error;
  }

  async function anularRecibo(cliente, reciboId, cambios) {
    validar(cliente);
    const { data, error } = await cliente.from('recibos').update(cambios)
      .eq('id', reciboId).select('id').maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('No se pudo confirmar la anulación: el recibo no fue actualizado.');
    return data;
  }

  async function listarVentasPeriodo(cliente, desde, hasta) {
    validar(cliente);
    const filas = [];
    let inicio = 0;
    while (true) {
      const { data, error } = await cliente.from('recibos_app').select('*')
        .gte('creado_en', desde).lt('creado_en', hasta)
        .order('creado_en', { ascending:false }).order('id')
        .range(inicio, inicio + 999);
      if (error) throw error;
      const pagina = data || [];
      filas.push(...pagina);
      if (pagina.length < 1000) break;
      inicio += 1000;
    }
    return filas;
  }

  async function listarLineasRecibos(cliente, recibos) {
    validar(cliente);
    const filas = [];
    for (let inicio = 0; inicio < recibos.length; inicio += 40) {
      const ids = recibos.slice(inicio, inicio + 40).map(recibo => recibo.id);
      if (!ids.length) continue;
      const { data, error } = await cliente.from('recibo_items_app').select('*')
        .in('recibo_id', ids);
      if (error) throw error;
      filas.push(...(data || []));
    }
    return filas;
  }

  async function listarLineasRecibo(cliente, reciboId) {
    validar(cliente);
    const { data, error } = await cliente.from('recibo_items_app').select('*')
      .eq('recibo_id', reciboId).order('id');
    if (error) throw error;
    return data || [];
  }

  async function listarCambiosPrecio(cliente) {
    validar(cliente);
    const { data, error } = await cliente.from('historial_precios').select('*')
      .order('creado_en', { ascending:false }).limit(30);
    if (error) throw error;
    return data || [];
  }

  window.DrosaludHistoryService = Object.freeze({
    listarCotizaciones, listarLineasCotizacion, eliminarRecibo, anularRecibo,
    listarVentasPeriodo, listarLineasRecibos, listarLineasRecibo, listarCambiosPrecio
  });
})();
