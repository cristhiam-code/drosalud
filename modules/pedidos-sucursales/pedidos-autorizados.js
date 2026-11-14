/* Vista de pedidos autorizados y bandeja central de revisión. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const fmt = value => (Number(value) || 0).toLocaleString('es-CO');
  const status = value => ({
    pendiente_autorizacion:'Pendiente', en_revision:'En revisión', aprobado:'Aprobado',
    rechazado:'Rechazado', en_preparacion:'En preparación',
    despachado:'Despachado', parcial:'Recibido parcialmente',
    recibido:'Recibido', cancelado:'Cancelado'
  }[value] || value || '—');

  window.PedidosSucursalesAutorizados = Object.freeze({
    render(orders, isAdmin) {
      const visible = orders.filter(order => isAdmin
        ? ['pendiente_autorizacion','en_revision','aprobado','en_preparacion'].includes(order.estado)
        : ['aprobado','en_preparacion','despachado','parcial'].includes(order.estado));
      return `
        <section class="ps-panel">
          <div class="ps-section-head"><div><h3>${isAdmin ? 'Revisión y pedidos autorizados' : 'Pedidos autorizados'}</h3>
            <p>${isAdmin ? 'Revisa solicitudes y gestiona la preparación en bodega central.' : 'Consulta las cantidades aprobadas y su preparación.'}</p></div>
            <button class="ps-button ps-button-light" type="button" data-ps-action="actualizar-autorizados">Actualizar</button>
          </div>
          <div class="ps-list">
            ${visible.length ? visible.map(order => `
              <article class="ps-order-card">
                <div class="ps-order-head"><div><small>Pedido #${fmt(order.numero)} · ${esc(order.sucursal_nombre || '')}</small>
                  <b>${order.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido sugerido'}</b></div>
                  <span class="ps-status">${status(order.estado)}</span></div>
                <div class="ps-order-lines">
                  ${(order.items || []).map(item => `
                    <div class="ps-order-line"><span>${esc(item.producto_nombre)}</span>
                      <small>Solicitado: ${fmt(item.cantidad_solicitada)} · Autorizado: ${fmt(item.cantidad_autorizada)}</small>
                      ${isAdmin && order.estado === 'en_revision' ? `
                        <label class="ps-quantity">Cantidad a autorizar
                          <input type="number" min="0" max="${fmt(item.cantidad_solicitada)}" step="1"
                            data-ps-authorize-qty="${esc(item.id)}" value="${fmt(item.cantidad_autorizada == null ? item.cantidad_solicitada : item.cantidad_autorizada)}">
                        </label>` : ''}
                    </div>`).join('')}
                </div>
                ${order.motivo_rechazo ? '<p class="ps-warning">Motivo: ' + esc(order.motivo_rechazo) + '</p>' : ''}
                ${isAdmin && order.estado === 'pendiente_autorizacion' ? `
                  <div class="ps-actions"><button class="ps-button" type="button" data-ps-action="iniciar-revision" data-pedido-id="${esc(order.id)}">Iniciar revisión</button></div>` : ''}
                ${isAdmin && order.estado === 'en_revision' ? `
                  <div class="ps-actions">
                    <button class="ps-button" type="button" data-ps-action="autorizar" data-pedido-id="${esc(order.id)}">Autorizar pedido</button>
                    <button class="ps-button ps-button-danger" type="button" data-ps-action="rechazar" data-pedido-id="${esc(order.id)}">Rechazar</button>
                  </div>` : ''}
                ${isAdmin && ['aprobado','en_preparacion'].includes(order.estado) ? `
                  <div class="ps-actions"><button class="ps-button" type="button" data-ps-action="despachar" data-pedido-id="${esc(order.id)}">Registrar despacho</button></div>` : ''}
              </article>`).join('') : '<p class="ps-empty">No hay pedidos para mostrar en esta sección.</p>'}
          </div>
        </section>`;
    },
    authorizationItems(root, order) {
      return (order.items || []).map(item => {
        const value = Number(root.querySelector('[data-ps-authorize-qty="' + item.id + '"]')?.value);
        if (!Number.isInteger(value) || value < 0 || value > Number(item.cantidad_solicitada)) {
          throw new Error('Revisa las cantidades que vas a autorizar.');
        }
        return { pedido_item_id: item.id, cantidad_autorizada: value };
      });
    }
  });
})();
