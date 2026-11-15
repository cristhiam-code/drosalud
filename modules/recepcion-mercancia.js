/* Recepción de mercancía / remisiones de compra.
 * Una fila pendiente representa una orden aprobada con unidades por recibir.
 * Una fila cargada representa una recepción ya confirmada en inventario.
 * No mantiene inventario paralelo: la RPC registra la recepción y el Kardex existente.
 */
(() => {
  'use strict';
  const root = document.getElementById('recepcion-mercancia-app');
  if (!root) return;

  const $ = (selector, scope = root) => scope.querySelector(selector);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const money = value => '$' + Number(value || 0).toLocaleString('es-CO', {
    maximumFractionDigits: 2
  });
  const date = value => value ? new Date(value).toLocaleDateString('es-CO') : '—';
  let pending = [];
  let loaded = [];
  let busy = false;

  function status(message, error = false) {
    const el = $('[data-rm-status]');
    if (!el) return;
    el.textContent = message || '';
    el.classList.toggle('rm-error', !!error);
  }

  function exportExcel() {
    if (typeof XLSX === 'undefined' || !XLSX.utils?.aoa_to_sheet) {
      status('No está disponible la librería de Excel. Recarga la página e inténtalo de nuevo.', true);
      return;
    }
    const safe = value => {
      const text = String(value ?? '');
      return /^[=+@\-\t\r]/.test(text) ? "'" + text : text;
    };
    const rows = [
      ['N° Remisión/Factura','Fecha','Proveedor','Cantidad de Productos','Valor Total','Estado'],
      ...[
        ...pending.map(order => [
          order.documento_proveedor || ('Orden #' + order.numero + ' · pendiente de remisión'),
          order.creado_en, order.proveedor?.nombre || 'Proveedor',
          (order.items || []).filter(x => Number(x.unidades_solicitadas) > Number(x.unidades_recibidas)).length,
          (order.items || []).reduce((sum, x) => sum + Math.max(0, Number(x.unidades_solicitadas) - Number(x.unidades_recibidas)) * Number(x.costo_unitario_base || 0), 0),
          'Pendiente por cargar'
        ]),
        ...loaded.map(receipt => [
          receipt.documento_proveedor || ('Recepción #' + receipt.numero),
          receipt.recibido_en, receipt.proveedor?.nombre || 'Proveedor',
          (receipt.items || []).length,
          (receipt.items || []).reduce((sum, x) => sum + Number(x.unidades || 0) * Number(x.costo_unitario_base || 0), 0),
          'Cargado al inventario'
        ])
      ].map(row => row.map(safe))
    ];
    const workbook = XLSX.utils.book_new();
    const sheet = XLSX.utils.aoa_to_sheet(rows);
    sheet['!cols'] = [{wch:26},{wch:14},{wch:28},{wch:22},{wch:18},{wch:24}];
    XLSX.utils.book_append_sheet(workbook, sheet, 'Remisiones');
    XLSX.writeFile(workbook, 'remisiones-compra-drosalud.xlsx');
  }

  async function fetchData() {
    const [ordersResult, receiptsResult] = await Promise.all([
      sb.from('ordenes_compra')
        .select('id,numero,proveedor_id,estado,documento_proveedor,creado_en,proveedor:proveedores(nombre),items:ordenes_compra_items(id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base,producto:productos(nombre,codigo))')
        .in('estado', ['aprobada','parcial'])
        .order('creado_en', {ascending:false}),
      sb.from('recepciones_compra')
        .select('id,numero,orden_id,proveedor_id,documento_proveedor,recibido_en,proveedor:proveedores(nombre),items:recepciones_compra_items(id,producto_id,unidades,costo_unitario_base,producto:productos(nombre,codigo))')
        .order('recibido_en', {ascending:false})
        .limit(250)
    ]);
    if (ordersResult.error) throw ordersResult.error;
    if (receiptsResult.error) throw receiptsResult.error;
    pending = (ordersResult.data || []).filter(order =>
      (order.items || []).some(item => Number(item.unidades_solicitadas) > Number(item.unidades_recibidas))
    );
    loaded = receiptsResult.data || [];
  }

  function renderRows() {
    const rows = [
      ...pending.map(order => ({
        key: order.id, number: order.documento_proveedor || 'Orden #' + order.numero,
        date: order.creado_en, provider: order.proveedor?.nombre,
        count: (order.items || []).filter(x => Number(x.unidades_solicitadas) > Number(x.unidades_recibidas)).length,
        total: (order.items || []).reduce((sum, x) => sum + Math.max(0, Number(x.unidades_solicitadas) - Number(x.unidades_recibidas)) * Number(x.costo_unitario_base || 0), 0),
        state: 'Pendiente por cargar', action: '<button class="btn full" data-rm-open="' + esc(order.id) + '">Abrir y registrar recepción</button>'
      })),
      ...loaded.map(receipt => ({
        key: receipt.id, number: receipt.documento_proveedor || 'Recepción #' + receipt.numero,
        date: receipt.recibido_en, provider: receipt.proveedor?.nombre,
        count: (receipt.items || []).length,
        total: (receipt.items || []).reduce((sum, x) => sum + Number(x.unidades || 0) * Number(x.costo_unitario_base || 0), 0),
        state: 'Cargado al inventario',
        action: '<button class="btn alt full" data-rm-detail="' + esc(receipt.id) + '">Ver detalle</button>'
      }))
    ].sort((a,b) => new Date(b.date || 0) - new Date(a.date || 0));

    const body = $('[data-rm-rows]');
    body.innerHTML = rows.length ? rows.map(row => `
      <tr>
        <td><strong>${esc(row.number)}</strong></td>
        <td>${esc(date(row.date))}</td>
        <td>${esc(row.provider || '—')}</td>
        <td>${row.count}</td>
        <td>${money(row.total)}</td>
        <td><span class="rm-state ${row.state === 'Cargado al inventario' ? 'is-loaded' : 'is-pending'}">${esc(row.state)}</span></td>
        <td>${row.action}</td>
      </tr>`).join('') : '<tr><td colspan="7" class="rm-empty">No hay remisiones ni órdenes pendientes por recibir.</td></tr>';
    $('[data-rm-count]').textContent = rows.length + ' documento(s)';
  }

  function render() {
    root.innerHTML = `
      <section class="rm-module">
        <header class="rm-heading">
          <div><span class="rm-kicker">INVENTARIO · COMPRAS</span>
            <h2>Remisiones</h2>
            <p>Registra facturas y remisiones, compara lo solicitado con lo recibido y confirma el ingreso al inventario.</p>
          </div>
          <div class="rm-heading-actions">
            <button class="btn alt" type="button" data-rm-back-orders>← Pedidos</button>
            <button class="btn alt" type="button" data-rm-export><svg class="excel-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false"><path fill="currentColor" d="M3 2h9l5 5v11H3z"/><path fill="#fff" d="M12 2v5h5"/><path fill="none" stroke="#fff" stroke-width="1.5" d="m5.5 10 4 5m0-5-4 5"/></svg> Exportar a Excel</button>
          </div>
        </header>
        <p class="mut sm" data-rm-count></p>
        <p class="mut sm" data-rm-status role="status"></p>
        <div class="rm-table-wrap">
          <table class="rm-table">
            <thead><tr>
              <th>N° Remisión/Factura</th><th>Fecha</th><th>Proveedor</th>
              <th>Cantidad de Productos</th><th>Valor Total</th><th>Estado</th><th>Acción</th>
            </tr></thead>
            <tbody data-rm-rows></tbody>
          </table>
        </div>
      </section>`;
    renderRows();
  }

  function openReceipt(order) {
    const lines = (order.items || []).filter(item =>
      Number(item.unidades_solicitadas) > Number(item.unidades_recibidas)
    );
    const operationId = crypto.randomUUID();
    root.insertAdjacentHTML('beforeend', `
      <div class="rm-overlay" data-rm-overlay>
        <section class="rm-dialog" role="dialog" aria-modal="true" aria-labelledby="rm-dialog-title">
          <h2 id="rm-dialog-title">Registrar remisión del proveedor</h2>
          <p class="mut sm">Proveedor: <strong>${esc(order.proveedor?.nombre || '—')}</strong> · Orden #${order.numero}</p>
          <label>N° Remisión / Factura del proveedor</label>
          <input data-rm-document maxlength="120" placeholder="Número del documento" required>
          <label>Fecha de recepción</label>
          <input data-rm-date type="date" value="${new Date().toLocaleDateString('en-CA',{timeZone:'America/Bogota'})}" disabled>
          <div class="rm-lines">
            ${lines.map(item => `
              <article class="rm-line">
                <strong>${esc(item.producto?.nombre || 'Producto')}</strong>
                <small>Código: ${esc(item.producto?.codigo || '—')} · Pendiente: ${Number(item.unidades_solicitadas)-Number(item.unidades_recibidas)} unidades</small>
                <label>Cantidad recibida</label>
                <input type="number" min="0" max="${Number(item.unidades_solicitadas)-Number(item.unidades_recibidas)}" step="1" value="${Number(item.unidades_solicitadas)-Number(item.unidades_recibidas)}" data-rm-qty="${item.id}">
                <label>Costo real por unidad</label>
                <input type="number" min="0" step="0.01" value="${Number(item.costo_unitario_base || 0)}" data-rm-cost="${item.id}">
              </article>`).join('')}
          </div>
          <label>Observaciones (opcional)</label>
          <textarea data-rm-notes maxlength="500" rows="2"></textarea>
          <div class="rm-actions">
            <button class="btn full" type="button" data-rm-confirm>Confirmar recepción e ingreso al inventario</button>
            <button class="btn alt full" type="button" data-rm-close>Cancelar</button>
          </div>
        </section>
      </div>`);
    const overlay = $('[data-rm-overlay]');
    $('[data-rm-close]', overlay).onclick = () => overlay.remove();
    $('[data-rm-confirm]', overlay).onclick = async buttonEvent => {
      const button = buttonEvent.currentTarget;
      if (busy) return;
      const documentNumber = $('[data-rm-document]', overlay).value.trim();
      if (!documentNumber) { status('Escribe el número de remisión o factura.', true); return; }
      const items = lines.map(item => ({
        orden_item_id: item.id,
        unidades: Number($('[data-rm-qty="' + item.id + '"]', overlay).value),
        costo_unitario_base: Number($('[data-rm-cost="' + item.id + '"]', overlay).value)
      })).filter(item => item.unidades > 0);
      if (!items.length || items.some(item => !Number.isInteger(item.unidades) || item.unidades <= 0 || !Number.isFinite(item.costo_unitario_base) || item.costo_unitario_base < 0)) {
        status('Verifica cantidades y costos. Debes recibir al menos un producto.', true); return;
      }
      if (items.some(item => item.costo_unitario_base === 0) && !confirm('Hay productos con costo $0. ¿Confirmas que realmente son gratuitos?')) return;
      busy = true; button.disabled = true; button.textContent = 'Registrando…';
      try {
        const {error} = await sb.rpc('registrar_recepcion_compra', {
          p_orden_id: order.id, p_documento_proveedor: documentNumber,
          p_items: items, p_operacion_id: operationId,
          p_notas: $('[data-rm-notes]', overlay).value.trim() || null
        });
        if (error) throw error;
        overlay.remove();
        busy = false;
        await load();
        window.invCargarDatos?.();
        status('Recepción confirmada. El Kardex y el inventario ya reflejan las unidades recibidas.');
      } catch (error) {
        console.error('Recepción de mercancía:', error);
        status(error.message || 'No se pudo registrar la recepción.', true);
        button.disabled = false; button.textContent = 'Reintentar confirmación';
      } finally { busy = false; }
    };
  }

  function showDetail(receipt) {
    const items = receipt.items || [];
    root.insertAdjacentHTML('beforeend', `
      <div class="rm-overlay" data-rm-overlay>
        <section class="rm-dialog" role="dialog" aria-modal="true">
          <h2>Remisión ${esc(receipt.documento_proveedor || ('#' + receipt.numero))}</h2>
          <p class="mut sm">${esc(receipt.proveedor?.nombre || 'Proveedor')} · ${esc(date(receipt.recibido_en))}</p>
          ${items.map(item => `
            <article class="rm-line">
              <strong>${esc(item.producto?.nombre || 'Producto')}</strong>
              <small>${esc(item.producto?.codigo || '—')} · ${Number(item.unidades)} unidades · ${money(item.costo_unitario_base)} por unidad</small>
              <b>${money(Number(item.unidades) * Number(item.costo_unitario_base))}</b>
            </article>`).join('')}
          <div class="rm-actions"><button class="btn full" type="button" data-rm-close>Cerrar</button></div>
        </section>
      </div>`);
    $('[data-rm-close]', $('[data-rm-overlay]')).onclick = () => $('[data-rm-overlay]').remove();
  }

  async function load() {
    if (busy) return;
    status('Consultando órdenes y remisiones…');
    try { await fetchData(); render(); }
    catch (error) {
      console.error('Carga de remisiones:', error);
      root.innerHTML = '<p class="rm-error">No se pudo cargar recepción de mercancía: ' + esc(error.message || 'Error de conexión') + '</p>';
    }
  }

  root.addEventListener('click', event => {
    if (event.target.closest('[data-rm-back-orders]')) {
      if (typeof show === 'function') show('pedidos');
      return;
    }
    const exportButton = event.target.closest('[data-rm-export]');
    if (exportButton) return exportExcel();
    const openButton = event.target.closest('[data-rm-open]');
    if (openButton) {
      const order = pending.find(item => item.id === openButton.dataset.rmOpen);
      if (order) openReceipt(order);
      return;
    }
    const detailButton = event.target.closest('[data-rm-detail]');
    if (detailButton) {
      const receipt = loaded.find(item => item.id === detailButton.dataset.rmDetail);
      if (receipt) showDetail(receipt);
      return;
    }
    if (event.target.closest('[data-rm-close]')) $('[data-rm-overlay]')?.remove();
  });

  window.DrosaludRecepcionMercancia = Object.freeze({load});
})();