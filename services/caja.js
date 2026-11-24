/* Servicios de caja: el cliente Supabase siempre se inyecta desde el shell. */
(() => {
  'use strict';

  function validarCliente(cliente) {
    if (!cliente || typeof cliente.rpc !== 'function' || typeof cliente.from !== 'function') {
      throw new Error('El servicio de caja requiere un cliente Supabase válido.');
    }
  }

  async function rpc(cliente, nombre, argumentos) {
    validarCliente(cliente);
    const { data, error } = await cliente.rpc(nombre, argumentos);
    if (error) throw error;
    return data;
  }

  async function listarGastos(cliente, fecha) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('gastos')
      .select('id,concepto,categoria,monto,forma_pago,anulado,motivo_anulacion,creado_en')
      .eq('fecha', fecha)
      .order('creado_en', { ascending: true });
    if (error) throw error;
    return data || [];
  }

  async function listarCierres(cliente) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('cierres_caja')
      .select('id,fecha,base_inicial,ventas_efectivo,ventas_total,gastos_efectivo,efectivo_esperado,efectivo_contado,diferencia,estado,cerrado_en')
      .order('fecha', { ascending: false })
      .limit(500);
    if (error) throw error;
    return data || [];
  }

  async function listarHistorial(cliente) {
    validarCliente(cliente);
    const { data, error } = await cliente.from('cierres_caja_historial')
      .select('id,fecha,version,motivo,registrado_en,registrado_por')
      .order('registrado_en', { ascending: false })
      .limit(100);
    if (error) throw error;
    return data || [];
  }

  window.DrosaludCashService = Object.freeze({
    jornadasPendientes: cliente => rpc(cliente, 'jornadas_pendientes_drosalud'),
    resumen: (cliente, fecha) => rpc(cliente, 'resumen_caja_drosalud', { p_fecha: fecha }),
    registrarGasto: (cliente, datos) => rpc(cliente, 'registrar_gasto_drosalud', {
      p_fecha: datos.fecha,
      p_concepto: datos.concepto,
      p_monto: datos.monto,
      p_forma_pago: datos.formaPago,
      p_categoria: datos.categoria
    }),
    anularGasto: (cliente, id, motivo) => rpc(cliente, 'anular_gasto_drosalud', {
      p_id: id,
      p_motivo: motivo
    }),
    cerrarJornada: (cliente, datos) => rpc(cliente, 'cerrar_caja_drosalud', {
      p_fecha: datos.fecha,
      p_base: datos.base,
      p_contado: datos.contado,
      p_notas: datos.notas
    }),
    reabrirJornada: (cliente, fecha, motivo) => rpc(cliente, 'reabrir_caja_drosalud', {
      p_fecha: fecha,
      p_motivo: motivo
    }),
    listarGastos,
    listarCierres,
    listarHistorial
  });
})();
