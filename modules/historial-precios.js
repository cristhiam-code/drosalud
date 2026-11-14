/* Drosalud · Historial de precios
 * Extraído sin cambiar la consulta ni la presentación original.
 * Depende de los helpers globales del núcleo clásico de index.html.
 */
(() => {
  'use strict';

  async function open() {
    const { data, error } = await sb
      .from('historial_precios')
      .select('*')
      .order('creado_en', { ascending: false })
      .limit(30);
    if (error) throw error;

    const nombreProducto = id =>
      (P.find(p => p.id === id) || {}).nombre || 'Producto eliminado';

    openM(`<h2 style="margin-top:0">Cambios recientes de precio</h2>${data.length ? data.map(x => {
      const d = (x.precio_nuevo - x.precio_anterior) / x.precio_anterior * 100;
      return `<div class="item"><div class="top"><span>${esc(nombreProducto(x.producto_id))}</span></div><small class="mut">${esc(fd(x.creado_en))} · ${money(x.precio_anterior)} → ${money(x.precio_nuevo)} <b class="${d > 0 ? 'warn' : ''}">(${d > 0 ? '+' : ''}${d.toFixed(1).replace('.', ',')}%)</b></small></div>`;
    }).join('') : '<p class="mut">Aún no hay cambios registrados.</p>'}<div class="acts"><button class="btn alt full" id="cx2">Cerrar</button></div>`);
    $('#cx2').onclick = closeM;
  }

  window.DrosaludCambiosPrecios = Object.freeze({ open });
})();
