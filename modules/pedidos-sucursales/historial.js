/* Historial de pedidos creados por la sucursal. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const fmt = value => (Number(value) || 0).toLocaleString('es-CO');
  const status = value => ({
    pendiente_autorizacion:'Pendiente', en_revision:'En revisión', aprobado:'Aprobado', rechazado:'Rechazado',
    en_preparacion:'En preparación', despachado:'Despachado',
    parcial:'Recibido parcialmente', recibido:'Recibido', cancelado:'Cancelado'
  }[value] || value || '—');

  window.PedidosSucursalesHistorial = Object.freeze({
    render(orders) {
      return `
        <section class="ps-panel">
          <div class="ps-section-head"><div><h3>Pedidos realizados y enviados</h3>
            <p>Historial y trazabilidad desde la solicitud hasta la recepción.</p></div>
            <button class="ps-button ps-button-light" type="button" data-ps-action="actualizar-historial">Actualizar</button>
          </div>
          <div class="ps-list">
            ${orders.length ? orders.map(order => `
              <article class="ps-order-card">
                <div class="ps-order-head"><div><small>Pedido #${fmt(order.numero)} · ${new Date(order.creado_en).toLocaleString('es-CO')}</small>
                  <b>${order.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido sugerido'}</b></div>
                  <span class="ps-status">${status(order.estado)}</span></div>
                <div class="ps-order-lines">${(order.items || []).map(item => `
                  <div class="ps-order-line"><span>${esc(item.producto_nombre)}</span>
                    <small>Solicitado: ${fmt(item.cantidad_solicitada)} · Autorizado: ${fmt(item.cantidad_autorizada)} · Enviado: ${fmt(item.cantidad_despachada)} · Recibido: ${fmt(item.cantidad_recibida)}</small></div>
                `).join('')}</div>
                ${order.motivo_rechazo ? '<p class="ps-warning">Motivo del rechazo: ' + esc(order.motivo_rechazo) + '</p>' : ''}
                ${(order.despachos || []).map(dispatch => `
                  <div class="ps-dispatch">
                    <b>Despacho #${fmt(dispatch.numero)} · ${status(dispatch.estado)}</b>
                    ${(dispatch.items || []).map(item => `
                      <div class="ps-order-line"><span>${esc(item.producto_nombre)}</span>
                        <small>Enviado: ${fmt(item.unidades_enviadas)} · Recibido: ${fmt(item.unidades_recibidas)}</small>
                        ${dispatch.estado === 'despachado' ? `
                          <label class="ps-quantity">Unidades recibidas
                            <input type="number" min="0" max="${fmt(item.unidades_enviadas)}" step="1"
                              data-ps-receive-qty="${esc(item.id)}" value="${fmt(item.unidades_enviadas)}">
                          </label>` : ''}
                      </div>`).join('')}
                    ${dispatch.estado === 'despachado' ? `
                      <button class="ps-button" type="button" data-ps-action="confirmar-recepcion" data-despacho-id="${esc(dispatch.id)}">Confirmar recepción</button>` : ''}
                  </div>`).join('')}
              </article>`).join('') : '<p class="ps-empty">Todavía no hay pedidos registrados.</p>'}
          </div>
        </section>`;
    },
    receiptItems(root, dispatch) {
      return (dispatch.items || []).map(item => {
        const value = Number(root.querySelector('[data-ps-receive-qty="' + item.id + '"]')?.value);
        if (!Number.isInteger(value) || value < 0 || value > Number(item.unidades_enviadas)) {
          throw new Error('Revisa las cantidades recibidas.');
        }
        return { despacho_item_id: item.id, unidades_recibidas: value };
      });
    }
  });
})();
