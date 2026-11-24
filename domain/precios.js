/* Reglas puras de cálculo de precios. No lee ajustes globales ni accede a la base de datos. */
(() => {
  'use strict';

  function precioSugerido(costo, configuracion) {
    const valor = costo * (1 + configuracion.m / 100);
    return configuracion.r
      ? Math.ceil(valor / configuracion.r - 1e-9) * configuracion.r
      : Math.round(valor);
  }

  function precioVentaProducto(producto, configuracion) {
    if (producto.precio_venta != null) return Number(producto.precio_venta);
    const costo = Number(producto.precio_compra);
    return costo > 0 ? precioSugerido(costo, configuracion) : null;
  }

  window.DrosaludPricing = Object.freeze({
    precioSugerido,
    precioVentaProducto
  });
})();
