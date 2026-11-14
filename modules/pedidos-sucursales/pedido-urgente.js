/* Vista y captura del Pedido Urgente: solo productos con saldo negativo. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const fmt = value => (Number(value) || 0).toLocaleString('es-CO');

  window.PedidosSucursalesUrgente = Object.freeze({
    render(rows) {
      return `
        <section class="ps-panel">
          <div class="ps-section-head"><div><h3>Pedido urgente</h3>
            <p>Disponible cualquier día para productos con inventario menor que cero.</p></div>
            <button class="ps-button ps-button-light" type="button" data-ps-action="recalcular-urgentes">Actualizar</button>
          </div>
          <p class="ps-warning">Solo se pueden solicitar productos cuyo saldo actual en esta sucursal sea negativo. El servidor vuelve a comprobarlo al enviar.</p>
          <div class="ps-list">
            ${rows.length ? rows.map((row, i) => `
              <article class="ps-product-row">
                <div class="ps-product-name"><b>${esc(row.nombre)}</b>
                  <small>${esc(row.codigo || 'Sin código')} · ${esc(row.laboratorio || 'Sin laboratorio')}</small></div>
                <span class="ps-negative">Existencia: ${fmt(row.saldo_unidades)} unidades</span>
                <label class="ps-quantity">Unidades solicitadas
                  <input type="number" min="1" step="1" inputmode="numeric"
                    data-ps-urgente-qty="${i}" data-producto-id="${esc(row.producto_id)}" value="1">
                </label>
              </article>`).join('') : '<p class="ps-empty">No hay productos con inventario negativo en esta sucursal.</p>'}
          </div>
          <label class="ps-field">Motivo de urgencia
            <textarea rows="2" maxlength="500" data-ps-urgente-motivo placeholder="Ej. Venta pendiente a cliente o agotado inesperado"></textarea>
          </label>
          <div class="ps-actions"><button class="ps-button" type="button" data-ps-action="enviar-urgente" ${rows.length ? '' : 'disabled'}>Enviar pedido urgente</button></div>
        </section>`;
    },
    collect(root, rows) {
      return rows.map((row, i) => {
        const input = root.querySelector('[data-ps-urgente-qty="' + i + '"]');
        const quantity = Number(input?.value);
        if (!Number.isInteger(quantity) || quantity <= 0) {
          throw new Error('Cada cantidad urgente debe ser un entero mayor que cero.');
        }
        return { producto_id: row.producto_id, cantidad_solicitada: quantity };
      });
    },
    reason(root) {
      return root.querySelector('[data-ps-urgente-motivo]')?.value.trim() || '';
    }
  });
})();
