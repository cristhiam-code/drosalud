/* Puente controlado entre módulos extraídos y el núcleo legado de Drosalud.
 * Añadir aquí únicamente contratos que un módulo realmente necesite.
 */
(() => {
  'use strict';
  if (window.DrosaludCore) throw new Error('DrosaludCore ya fue inicializado.');
  window.DrosaludCore = Object.freeze({
    version: 1,
    cotizaciones: Object.freeze({
      db: () => sb,
      getAll: () => CO,
      setAll: rows => { CO = Array.isArray(rows) ? rows : []; },
      el: selector => $(selector),
      norm: value => norm(value),
      pad: value => pad(value),
      esc: value => esc(value),
      titleCase: value => tcase(value),
      formatDateTime: value => fmt(value),
      formatDate: value => fd(value),
      money: value => money(value),
      showReceipt: (receipt, items) => showRec(receipt, items),
      handleError: task => go(task)
    })
  });
})();
