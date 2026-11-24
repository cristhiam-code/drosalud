/* Consultas de informes: el cliente de datos se inyecta desde el shell. */
(() => {
  'use strict';

  async function readAll(build) {
    const rows = [];
    let start = 0;
    while (true) {
      const result = await build().range(start, start + 999);
      if (result.error) throw result.error;
      const page = result.data || [];
      rows.push(...page);
      if (page.length < 1000) return rows;
      start += page.length;
    }
  }

  async function loadInventory(cliente) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de informes requiere un cliente Supabase válido.');
    }

    const [products, balances] = await Promise.all([
      readAll(() => cliente.from('productos_app')
        .select('id,codigo,nombre,laboratorio,linea,precio_compra,precio_venta,fraccionable,unidades_por_caja,unidades_por_venta,actualizado_en')
        .order('nombre').order('id')),
      readAll(() => cliente.from('inventario_saldos')
        .select('producto_id,saldo_unidades')
        .order('producto_id'))
    ]);

    let movements = [];
    let warning = '';
    try {
      movements = await readAll(() => cliente.from('inventario_movimientos')
        .select('producto_id,costo_unitario_base,creado_en')
        .not('costo_unitario_base', 'is', null)
        .order('creado_en', { ascending: false }));
    } catch (error) {
      console.warn('No se pudo leer el costo de movimientos:', error);
      warning = 'No se pudo consultar el costo de los movimientos; se utilizará el costo del catálogo cuando exista.';
    }

    let history = [];
    try {
      history = await readAll(() => cliente.from('historial_costos')
        .select('producto_id,costo_unitario_base,registrado_en')
        .order('registrado_en', { ascending: false }));
    } catch (error) {
      console.warn('No se pudo leer historial de costos:', error);
    }

    return { products, balances, movements, history, warning };
  }

  window.DrosaludReportsService = Object.freeze({ loadInventory });
})();
