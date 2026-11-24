/* Funciones puras compartidas: sin DOM, estado de negocio ni acceso a Supabase. */
(() => {
  'use strict';

  const escapeHtml = value => String(value == null ? '' : value).replace(/[&<>"]/g, char => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;'
  }[char]));

  const normalizeText = value => String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');

  const formatMoney = value => '$' + Math.round(value).toLocaleString('es-CO');

  window.DrosaludFormatters = Object.freeze({
    esc: escapeHtml,
    norm: normalizeText,
    money: formatMoney
  });
})();
