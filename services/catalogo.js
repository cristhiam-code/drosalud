/* Servicios de catálogo: persistencia de productos, precios y trazabilidad. */
(() => {
  'use strict';

  function validar(cliente) {
    if (!cliente || typeof cliente.from !== 'function' || typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de catálogo requiere un cliente Supabase válido.');
    }
  }

  async function ejecutarRpc(cliente, nombre, argumentos) {
    validar(cliente);
    const { data, error } = await cliente.rpc(nombre, argumentos);
    if (error) throw error;
    return data;
  }

  async function actualizarPrecios(cliente, argumentos) {
    return ejecutarRpc(cliente, 'actualizar_precios_drosalud_con_motivo', argumentos);
  }

  async function habilitarFraccionamiento(cliente, argumentos) {
    return ejecutarRpc(cliente, 'habilitar_fraccionamiento_producto', argumentos);
  }

  async function actualizarProducto(cliente, id, cambios) {
    validar(cliente);
    const { data, error } = await cliente.from('productos').update(cambios)
      .eq('id', id).select('id').maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('El producto no se actualizó. No se encontró el registro o tu usuario no tiene permiso.');
    return data;
  }

  async function crearProducto(cliente, producto) {
    validar(cliente);
    const { data, error } = await cliente.from('productos').insert(producto).select().single();
    if (error) throw error;
    return data;
  }

  async function eliminarProducto(cliente, id) {
    validar(cliente);
    const { error } = await cliente.from('productos').delete().eq('id', id);
    if (error) throw error;
  }

  async function listarAuditoriaProducto(cliente, id) {
    validar(cliente);
    const { data, error } = await cliente.from('auditoria_precios')
      .select('campo,valor_anterior,valor_nuevo,usuario_email,motivo,creado_en')
      .eq('producto_id', id).order('creado_en', { ascending:false }).limit(12);
    if (error) throw error;
    return data || [];
  }

  async function contarProductos(cliente) {
    validar(cliente);
    const { count, error } = await cliente.from('productos').select('*', { count:'exact', head:true });
    if (error) throw error;
    return count || 0;
  }

  async function importarProductos(cliente, productos) {
    validar(cliente);
    const { error } = await cliente.from('productos').insert(productos);
    if (error) throw error;
  }

  window.DrosaludCatalogService = Object.freeze({
    actualizarPrecios, habilitarFraccionamiento, actualizarProducto,
    crearProducto, eliminarProducto, listarAuditoriaProducto,
    contarProductos, importarProductos
  });
})();
