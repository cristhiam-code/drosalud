/* Cálculos monetarios puros del catálogo y del recibo. */
(() => {
  'use strict';

  function subtotalLineas(items) {
    return items.reduce((total, item) => total + Number(item.precio_venta) * item.cantidad, 0);
  }

  function porcentajeSobreCosto(precioVenta, costoCompra) {
    return costoCompra > 0 ? (precioVenta - costoCompra) / costoCompra * 100 : 0;
  }

  window.DrosaludMoney = Object.freeze({
    subtotalLineas,
    porcentajeSobreCosto
  });
})();
