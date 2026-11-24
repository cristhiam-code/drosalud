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


  async function listarDatos(cliente, incluirAuditoria) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de compras requiere un cliente Supabase válido.');
    }
    const [ordenes, documentos, lineas, recepciones, costos, auditoria, vinculos] = await Promise.all([
      cliente.from('ordenes_compra').select('id,numero,proveedor_id,estado,documento_proveedor,creado_en,proveedor:proveedores(nombre),items:ordenes_compra_items(id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base,producto:productos(id,nombre,codigo,unidades_por_caja))').in('estado',['aprobada','parcial','recibida']).order('creado_en',{ascending:false}),
      cliente.from('documentos_proveedor').select('id,proveedor_id,tipo_documento,numero_documento,fecha_emision,subtotal,descuentos,impuestos,flete,total,estado,notas,creado_en,proveedor:proveedores(nombre)').order('creado_en',{ascending:false}).limit(300),
      cliente.from('documentos_proveedor_items').select('id,documento_id,orden_item_id,producto_id,descripcion_documento,presentacion_documento,unidades_por_presentacion,cantidad_documentada,unidades_documentadas,precio_por_presentacion,costo_unitario_base,producto:productos(nombre,codigo)').order('creado_en',{ascending:true}).limit(1500),
      cliente.from('recepciones_compra').select('id,numero,orden_id,proveedor_id,documento_id,documento_proveedor,recibido_en,proveedor:proveedores(nombre),items:recepciones_compra_items(id,orden_item_id,producto_id,unidades,costo_unitario_base,producto:productos(nombre,codigo))').order('recibido_en',{ascending:false}).limit(500),
      cliente.from('historial_costos').select('id,producto_id,proveedor_id,costo_unitario_base,costo_presentacion,unidades_por_presentacion,origen,referencia_id,registrado_por,registrado_en').order('registrado_en',{ascending:false}).limit(300),
      incluirAuditoria ? cliente.from('auditoria_precios').select('id,producto_id,producto_nombre,campo,valor_anterior,valor_nuevo,usuario_email,rol,motivo,creado_en').order('creado_en',{ascending:false}).limit(300) : Promise.resolve({data:[],error:null}),
      cliente.from('documentos_proveedor_ordenes').select('documento_id,orden_id')
    ]);
    for (const resultado of [ordenes,documentos,lineas,recepciones,costos,auditoria,vinculos]) {
      if (resultado.error) throw resultado.error;
    }
    const lineasPorDocumento = new Map();
    (lineas.data || []).forEach(linea => {
      if (!lineasPorDocumento.has(linea.documento_id)) lineasPorDocumento.set(linea.documento_id, []);
      lineasPorDocumento.get(linea.documento_id).push(linea);
    });
    const documentosCompletos = (documentos.data || []).map(documento => ({
      ...documento,
      items: lineasPorDocumento.get(documento.id) || [],
      ordenes: (vinculos.data || []).filter(vinculo => vinculo.documento_id === documento.id).map(vinculo => vinculo.orden_id)
    }));
    return {
      ordenes: ordenes.data || [],
      documentos: documentosCompletos,
      recepciones: recepciones.data || [],
      costos: costos.data || [],
      auditoria: auditoria.data || []
    };
  }

  window.DrosaludPurchasesService = Object.freeze({
    listarDatos,
    registrarDocumentoProveedor: (cliente, argumentos) =>
      ejecutar(cliente, 'registrar_documento_proveedor', argumentos),
    registrarRecepcionDocumentada: (cliente, argumentos) =>
      ejecutar(cliente, 'registrar_recepcion_compra_documentada', argumentos)
  });
})();
