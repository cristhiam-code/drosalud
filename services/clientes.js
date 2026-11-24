/* Servicios de clientes, consentimiento y consulta de historial. */
(() => {
  'use strict';

  function validar(cliente) {
    if (!cliente || typeof cliente.from !== 'function' || typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de clientes requiere un cliente Supabase válido.');
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
      desde += 1000;
    }
    return filas;
  }

  async function listarClientes(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('clientes').select('*').order('nombre').order('id'));
  }

  async function listarConsentimientos(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('consentimientos_clientes').select('*')
      .order('aceptado_en').order('id'));
  }

  async function registrarConsentimiento(cliente, fila) {
    validar(cliente);
    const { error } = await cliente.from('consentimientos_clientes').insert(fila);
    if (error) throw error;
  }

  async function actualizarCliente(cliente, id, cambios) {
    validar(cliente);
    const { data, error } = await cliente.from('clientes').update(cambios)
      .eq('id', id).select('id').maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('El cliente no se actualizó. No se encontró el registro o tu usuario no tiene permiso.');
    return data;
  }

  async function crearCliente(cliente, fila) {
    validar(cliente);
    const { data, error } = await cliente.from('clientes').insert(fila).select().single();
    if (error) throw error;
    return data;
  }

  async function listarComprasCliente(cliente, clienteId) {
    validar(cliente);
    const { data, error } = await cliente.from('recibos_app').select('*')
      .eq('cliente_id', clienteId).order('creado_en', { ascending:false }).range(0, 499);
    if (error) throw error;
    return data || [];
  }

  async function listarLineasRecibo(cliente, reciboId) {
    validar(cliente);
    const { data, error } = await cliente.from('recibo_items_app').select('*')
      .eq('recibo_id', reciboId).order('id');
    if (error) throw error;
    return data || [];
  }

  async function cargarResumenCompras(cliente) {
    validar(cliente);
    return obtenerTodas(() => cliente.from('recibos_app')
      .select('cliente_id,total,creado_en,anulado').order('creado_en').order('id'));
  }

  async function anonimizarCliente(cliente, clienteId) {
    validar(cliente);
    const { data, error } = await cliente.rpc('anonimizar_cliente_drosalud', { p_cliente_id: clienteId });
    if (error) throw error;
    return data;
  }

  window.DrosaludCustomersService = Object.freeze({
    listarClientes, listarConsentimientos, registrarConsentimiento,
    actualizarCliente, crearCliente, listarComprasCliente,
    listarLineasRecibo, cargarResumenCompras, anonimizarCliente
  });
})();
