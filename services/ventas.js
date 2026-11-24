/* Servicios de ventas: reciben el cliente como dependencia explícita. */
(() => {
  'use strict';

  async function registrarVenta(clienteSupabase, venta, items) {
    if (!clienteSupabase || typeof clienteSupabase.rpc !== 'function') {
      throw new Error('El servicio de ventas requiere un cliente Supabase válido.');
    }
    const { data, error } = await clienteSupabase.rpc('registrar_venta_drosalud', {
      p_venta: venta,
      p_items: items
    });
    if (error) throw error;
    if (!data || !data.id) {
      throw new Error('Supabase no devolvió un recibo válido. La venta no quedó registrada.');
    }
    return data;
  }

  async function crearCotizacion(clienteSupabase, cotizacion, items) {
    if (!clienteSupabase || typeof clienteSupabase.rpc !== 'function') {
      throw new Error('El servicio de ventas requiere un cliente Supabase válido.');
    }
    const { data, error } = await clienteSupabase.rpc('crear_cotizacion_venta_drosalud', {
      p_cotizacion: cotizacion,
      p_items: items
    });
    if (error) throw error;
    return data;
  }

  window.DrosaludSalesService = Object.freeze({
    registrarVenta,
    crearCotizacion
  });
})();
