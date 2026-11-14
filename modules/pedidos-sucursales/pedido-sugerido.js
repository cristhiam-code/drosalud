/* Vista y captura del Pedido Sugerido. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const fmt = value => (Number(value) || 0).toLocaleString('es-CO');

  window.PedidosSucursalesSugerido = Object.freeze({
    render(rows) {
      const total = rows.reduce((sum, row) => sum + (Number(row.cantidad_sugerida) || 0), 0);
      return `
        <section class="ps-panel">
          <div class="ps-section-head">
            <div><h3>Pedido sugerido</h3>
              <p>Reposición calculada con la rotación de los últimos siete días.</p></div>
            <button class="ps-button ps-button-light" type="button" data-ps-action="recalcular">Recalcular</button>
          </div>
          <div class="ps-kpis">
            <div><small>Productos por reponer</small><b>${fmt(rows.length)}</b></div>
            <div><small>Unidades sugeridas</small><b>${fmt(total)}</b></div>
            <div><small>Periodo de rotación</small><b>7 días</b></div>
          </div>
          <p class="ps-note">La propuesta resta las existencias y las cantidades que ya vienen en camino. Puedes ajustar cada cantidad antes de enviarla.</p>
          <div class="ps-list">
            ${rows.length ? rows.map((row, i) => `
              <article class="ps-product-row">
                <div class="ps-product-name"><b>${esc(row.producto_nombre)}</b>
                  <small>${esc(row.codigo || 'Sin código')} · ${esc(row.laboratorio || 'Sin laboratorio')}</small></div>
                <div class="ps-metrics">
                  <span>Vendido 7 días <b>${fmt(row.ventas_7_dias)}</b></span>
                  <span>Existencia <b>${fmt(row.saldo_unidades)}</b></span>
                  <span>Por recibir <b>${fmt(row.pendientes_unidades)}</b></span>
                </div>
                <label class="ps-quantity">Unidades a pedir
                  <input type="number" min="0" step="1" inputmode="numeric"
                    data-ps-sugerido-qty="${i}" data-producto-id="${esc(row.producto_id)}"
                    value="${Math.max(0, Number(row.cantidad_sugerida) || 0)}">
                </label>
              </article>`).join('') : '<p class="ps-empty">No hay productos que requieran reposición con los datos actuales.</p>'}
          </div>
          <div class="ps-actions">
            <button class="ps-button" type="button" data-ps-action="enviar-sugerido" ${rows.length ? '' : 'disabled'}>Enviar pedido sugerido</button>
          </div>
        </section>`;
    },
    collect(root, rows) {
      return rows.map((row, i) => {
        const input = root.querySelector('[data-ps-sugerido-qty="' + i + '"]');
        const quantity = Number(input?.value);
        if (!Number.isInteger(quantity) || quantity < 0) {
          throw new Error('Revisa las cantidades del pedido sugerido.');
        }
        return quantity > 0 ? {
          producto_id: row.producto_id,
          cantidad_solicitada: quantity
        } : null;
      }).filter(Boolean);
    }
  });
})();
