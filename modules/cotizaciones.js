/* Cotizaciones guardadas. La creación desde el POS permanece en el núcleo
 * porque comparte carrito, cliente, consentimiento y cálculo de venta.
 */
(() => {
  'use strict';
  const core = window.DrosaludCore;
  if (!core || core.version !== 1) throw new Error('No está disponible el puente del núcleo de Drosalud.');
  const api = core.cotizaciones;

  async function load() {
    const { data, error } = await api.db()
      .from('cotizaciones_venta_app')
      .select('*')
      .order('creado_en', { ascending: false })
      .order('numero', { ascending: false })
      .limit(500);
    if (error) throw error;
    api.setAll(data || []);
    render();
  }

  function render() {
    const q = api.norm(api.el('#coq').value);
    const rows = api.getAll().filter(r =>
      !q || api.norm((r.cliente_nombre || '') + ' ' + r.numero).includes(q)
    );
    api.el('#colist').innerHTML = rows.length
      ? rows.map(r =>
          '<button class="row" data-cotid="' + r.id + '">' +
            '<span class="nm">Cotización ' + api.pad(r.numero) +
            (r.cliente_nombre ? ' · ' + api.esc(api.titleCase(r.cliente_nombre)) : '') +
            '<small>' + api.esc(api.formatDateTime(r.creado_en)) + ' · ' +
            api.esc(r.estado) +
            (r.valida_hasta ? ' · válida hasta ' + api.esc(api.formatDate(r.valida_hasta)) : '') +
            '</small></span><span class="pr">' + api.money(r.total) +
            '</span></button>'
        ).join('')
      : '<p class="mut">No hay cotizaciones guardadas.</p>';
  }

  async function open(id) {
    const receipt = api.getAll().find(r => String(r.id) === String(id));
    if (!receipt) return;
    return api.handleError(async () => {
      const { data, error } = await api.db()
        .from('cotizacion_venta_items_app')
        .select('*')
        .eq('cotizacion_id', receipt.id)
        .order('id');
      if (error) throw error;
      api.showReceipt(
        { ...receipt, cot: true },
        (data || []).map(i => ({
          nombre: i.nombre,
          cantidad: i.cantidad,
          precio_venta: i.precio_venta,
          presentacion: i.presentacion,
          unidades_por_presentacion: i.unidades_por_presentacion
        }))
      );
    });
  }

  window.DrosaludCotizaciones = Object.freeze({ load, render, open });
})();
