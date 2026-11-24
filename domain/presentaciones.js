/* Conversiones de presentación y preparación de líneas para venta/cotización.
   Funciones puras: no consultan Supabase ni modifican el carrito original. */
(() => {
  'use strict';

  function unidadesPresentacion(item) {
    return Math.max(1, Number(item.unidades_por_presentacion || item.unidadesPorPresentacion || 1));
  }

  function cantidadPresentacion(item) {
    const factor = unidadesPresentacion(item);
    return item.presentacion === 'Caja'
      ? Number(item.cantidad || 0) / factor
      : Number(item.cantidad || 0);
  }

  function precioPresentacion(item) {
    return Number(item.precio_venta || 0)
      * (item.presentacion === 'Caja' ? unidadesPresentacion(item) : 1);
  }

  function unidadesCarrito(item) {
    return item.fraccionable
      ? ((Number(item.cajas) || 0) * item.unidadesCaja + (Number(item.unidades) || 0))
      : item.q;
  }

  function totalCarrito(item) {
    return item.fraccionable
      ? ((Number(item.cajas) || 0) * item.precioCaja + (Number(item.unidades) || 0) * item.precioUnidad)
      : (item.p * item.q);
  }

  function itemsCarritoParaGuardar(item) {
    if (!item.fraccionable) {
      return [{
        producto_id: item.pid,
        nombre: item.n,
        cantidad: item.q,
        precio_venta: item.p,
        presentacion: item.presentacion || 'Unidad',
        unidades_por_presentacion: item.unidadesPorPresentacion || 1
      }];
    }

    const output = [];
    if (item.cajas > 0) {
      output.push({
        producto_id: item.pid,
        nombre: item.n,
        cantidad: item.cajas * item.unidadesCaja,
        precio_venta: item.precioCaja / item.unidadesCaja,
        presentacion: 'Caja',
        unidades_por_presentacion: item.unidadesCaja
      });
    }
    if (item.unidades > 0) {
      output.push({
        producto_id: item.pid,
        nombre: item.n,
        cantidad: item.unidades,
        precio_venta: item.precioUnidad,
        presentacion: 'Unidad',
        unidades_por_presentacion: 1
      });
    }
    return output;
  }

  window.DrosaludPresentations = Object.freeze({
    unidadesPresentacion,
    cantidadPresentacion,
    precioPresentacion,
    unidadesCarrito,
    totalCarrito,
    itemsCarritoParaGuardar
  });
})();
