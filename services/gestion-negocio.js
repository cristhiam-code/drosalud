/* Servicios de proveedores, solicitudes por conseguir y cotizaciones. */
(() => {
  'use strict';

  function validarCliente(cliente) {
    if (!cliente || typeof cliente.from !== 'function' || typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de gestión requiere un cliente Supabase válido.');
    }
  }

  async function cargar(cliente, userId) {
    validarCliente(cliente);
    const [proveedores, compras, cotizaciones] = await Promise.all([
      cliente.from('proveedores').select('*').order('nombre'),
      cliente.from('compras_pendientes').select('*').eq('owner_id', userId).order('creado_en', { ascending:false }),
      cliente.from('cotizaciones_proveedor').select('*').eq('owner_id', userId).order('consultado_en', { ascending:false })
    ]);
    for (const result of [proveedores, compras, cotizaciones]) if (result.error) throw result.error;
    return {
      proveedores: proveedores.data || [],
      compras: compras.data || [],
      cotizaciones: cotizaciones.data || []
    };
  }

  async function guardarProveedor(cliente, row, id, userId) {
    validarCliente(cliente);
    const result = id
      ? await cliente.from('proveedores').update(row).eq('id', id).eq('owner_id', userId).select('id').maybeSingle()
      : await cliente.from('proveedores').insert(row).select('id').single();
    if (result.error) throw result.error;
    if (id && !result.data) throw new Error('El proveedor no se actualizó. No se encontró el registro o tu usuario no tiene permiso.');
    return result.data;
  }

  async function eliminarProveedor(cliente, id, userId) {
    validarCliente(cliente);
    const { error } = await cliente.from('proveedores').delete().eq('id', id).eq('owner_id', userId);
    if (error) throw error;
  }

  async function guardarCompra(cliente, conCostoReal, argumentos) {
    validarCliente(cliente);
    const rpc = conCostoReal ? 'guardar_compra_con_costo_real' : 'guardar_compra_pendiente';
    const { data, error } = await cliente.rpc(rpc, argumentos);
    if (error) throw error;
    return data;
  }

  async function listarRecibos(cliente) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('recibos')
      .select('id,numero,cliente_nombre,creado_en').order('creado_en', { ascending:false }).limit(100);
    if (error) throw error;
    return data || [];
  }

  async function listarLineasRecibo(cliente, reciboId) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('recibo_items_app')
      .select('id,nombre,cantidad,precio_venta').eq('recibo_id', reciboId).order('id');
    if (error) throw error;
    return data || [];
  }

  async function registrarCotizacion(cliente, row) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('cotizaciones_proveedor').insert(row);
    if (error) throw error;
    return data;
  }

  window.DrosaludBusinessManagementService = Object.freeze({
    cargar, guardarProveedor, eliminarProveedor, guardarCompra,
    listarRecibos, listarLineasRecibo, registrarCotizacion
  });
})();
