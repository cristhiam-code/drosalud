/* Servicios de compras/recepción: cliente Supabase inyectado y argumentos explícitos. */
(() => {
  'use strict';

  async function ejecutar(cliente, nombre, argumentos) {
    if (!cliente || typeof cliente.rpc !== 'function') {
      throw new Error('El servicio de compras requiere un cliente Supabase válido.');
    }
    const { data, error } = await cliente.rpc(nombre, argumentos);
    if (error) throw error;
    return data;
  }

  window.DrosaludPurchasesService = Object.freeze({
    registrarDocumentoProveedor: (cliente, argumentos) =>
      ejecutar(cliente, 'registrar_documento_proveedor', argumentos),
    registrarRecepcionDocumentada: (cliente, argumentos) =>
      ejecutar(cliente, 'registrar_recepcion_compra_documentada', argumentos)
  });
})();
