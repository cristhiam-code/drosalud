(() => {
  'use strict';

  const root = document.getElementById('pedidos-app');
  if (!root) return;

  const state = {
    user: null, role: null, products: [], negativeProducts: [], providers: [], pedidos: [], items: [],
    orders: [], orderItems: [], suggested: [], formItems: [], editing: null,
    operationIds: {}, mode: 'inicio', loading: false, suggestedCalculatedAt: null, selectedPedidoId: null
  };

  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const norm = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const money = value => '$' + Math.round(Number(value) || 0).toLocaleString('es-CO');
  const units = value => (Number(value) || 0).toLocaleString('es-CO');
  const isAdmin = () => state.role === 'admin';
  const statusLabel = value => ({
    borrador:'Borrador',
    pendiente_autorizacion:'Pendiente de autorización',
    autorizado:'Autorizado',
    rechazado:'Rechazado',
    cancelado:'Cancelado',
    parcialmente_comprado:'Parcialmente comprado',
    en_compra:'En compra',
    parcialmente_recibido:'Parcialmente recibido',
    completado:'Completado'
  }[value] || value || '—');

  function message(text, error = false) {
    const el = root.querySelector('[data-pedidos-message]');
    if (!el) return;
    el.textContent = text;
    el.classList.toggle('is-error', !!error);
    el.hidden = !text;
  }

  async function getAll(build) {
    const rows = [];
    let from = 0;
    while (true) {
      const { data, error } = await build().range(from, from + 999);
      if (error) throw error;
      const page = data || [];
      rows.push(...page);
      if (page.length < 1000) break;
      from += 1000;
    }
    return rows;
  }

  async function loadSuggested() {
    const now = new Date();
    const since = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const receipts = await getAll(() => sb.from('recibos_app')
      .select('id').eq('anulado', false).gte('creado_en', since)
      .lte('creado_en', now.toISOString()).order('creado_en').order('id'));
    const sold = {};
    const receiptBatches = [];
    for (let offset = 0; offset < receipts.length; offset += 100) {
      receiptBatches.push(receipts.slice(offset, offset + 100).map(row => row.id));
    }
    const receiptLines = await Promise.all(receiptBatches.map(ids => getAll(() =>
      sb.from('recibo_items_app')
        .select('producto_id,cantidad,unidades_por_presentacion')
        .in('recibo_id', ids).order('id')
    )));
    receiptLines.flat().forEach(line => {
      if (!line.producto_id) return;
      sold[line.producto_id] = (sold[line.producto_id] || 0)
        + (Number(line.cantidad) || 0) * Math.max(1, Number(line.unidades_por_presentacion) || 1);
    });

    const [balances, allOrders, authorizedPedidos] = await Promise.all([
      getAll(() => sb.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id')),
      getAll(() => sb.from('ordenes_compra').select('id,pedido_id,estado').neq('estado', 'cancelada').order('creado_en')),
      getAll(() => sb.from('pedidos').select('id').eq('estado', 'autorizado').order('creado_en'))
    ]);
    const allOrderIds = allOrders.map(order => order.id);
    const orderItems = allOrderIds.length
      ? await getAll(() => sb.from('ordenes_compra_items')
          .select('orden_id,pedido_item_id,producto_id,unidades_solicitadas,unidades_recibidas')
          .in('orden_id', allOrderIds).order('creado_en'))
      : [];
    const orderById = new Map(allOrders.map(order => [order.id, order]));
    const stock = {};
    balances.forEach(row => { stock[row.producto_id] = Number(row.saldo_unidades) || 0; });
    const pending = {};
    const assignedByPedidoItem = {};
    orderItems.forEach(row => {
      if (!row.producto_id) return;
      const order = orderById.get(row.orden_id);
      if (!order) return;
      const ordered = Number(row.unidades_solicitadas) || 0;
      const received = Number(row.unidades_recibidas) || 0;
      if (['aprobada','parcial'].includes(order.estado)) {
        pending[row.producto_id] = (pending[row.producto_id] || 0) + Math.max(0, ordered - received);
      }
      if (row.pedido_item_id) {
        assignedByPedidoItem[row.pedido_item_id] = (assignedByPedidoItem[row.pedido_item_id] || 0) + ordered;
      }
    });

    // Lo autorizado y aún no asignado a proveedor también es compromiso de compra.
    // Así no vuelve a aparecer en el siguiente pedido sugerido.
    const authorizedPedidoIds = authorizedPedidos.map(row => row.id);
    if (authorizedPedidoIds.length) {
      const authorizedItems = await getAll(() => sb.from('pedidos_items')
        .select('id,producto_id,cantidad_autorizada')
        .in('pedido_id', authorizedPedidoIds).order('creado_en'));
      authorizedItems.forEach(item => {
        if (!item.producto_id) return;
        const authorized = Number(item.cantidad_autorizada) || 0;
        const alreadyAssigned = assignedByPedidoItem[item.id] || 0;
        const notYetOrdered = Math.max(0, authorized - alreadyAssigned);
        pending[item.producto_id] = (pending[item.producto_id] || 0) + notYetOrdered;
      });
    }

    state.suggested = state.products
      .map(product => {
        const soldUnits = sold[product.id] || 0;
        const stockUnits = stock[product.id] || 0;
        const pendingUnits = pending[product.id] || 0;
        // Si el saldo es negativo, primero se cubre ese déficit. Las ventas que lo originaron
        // ya están reflejadas en el saldo; sumarlas otra vez duplicaría la reposición.
        // Con saldo cero o positivo, se cubre la rotación de 7 días menos stock y compras pendientes.
        const suggestedUnits = Math.max(0, Math.ceil(
          stockUnits < 0 ? Math.abs(stockUnits) - pendingUnits : soldUnits - stockUnits - pendingUnits
        ));
        return { product, soldUnits, stockUnits, pendingUnits, suggestedUnits };
      })
      .filter(row => (row.soldUnits > 0 || row.stockUnits < 0) && row.suggestedUnits > 0)
      .sort((a,b) => (a.product.laboratorio || '').localeCompare(b.product.laboratorio || '', 'es')
        || a.product.nombre.localeCompare(b.product.nombre, 'es'));
    state.suggestedCalculatedAt = new Date();
  }

  async function loadData() {
    const { data: auth, error: authError } = await sb.auth.getUser();
    if (authError) throw authError;
    if (!auth?.user) throw new Error('Inicia sesión nuevamente.');
    state.user = auth.user;

    const { data: profile, error: profileError } = await sb.from('usuarios_drosalud')
      .select('rol,activo').eq('user_id', auth.user.id).maybeSingle();
    if (profileError) throw profileError;
    if (!profile || profile.activo !== true || !['admin','vendedor'].includes(profile.rol)) {
      throw new Error('Tu usuario no tiene un rol activo en Drosalud.');
    }
    state.role = profile.rol;

    const [products, providers, pedidos, balances] = await Promise.all([
      getAll(() => sb.from('productos_app')
        .select('id,codigo,nombre,laboratorio,precio_compra,unidades_por_caja,unidades_por_venta')
        .order('nombre').order('id')),
      getAll(() => sb.from('proveedores').select('id,nombre,activo')
        .eq('activo', true).order('nombre')),
      getAll(() => sb.from('pedidos_resumen').select('*').order('creado_en', { ascending:false })),
      getAll(() => sb.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id'))
    ]);
    state.products = products || [];
    const negativeIds = new Set((balances || [])
      .filter(row => Number(row.saldo_unidades) < 0)
      .map(row => row.producto_id));
    state.negativeProducts = state.products.filter(product => negativeIds.has(product.id));
    state.providers = providers || [];
    state.pedidos = pedidos || [];

    const ids = state.pedidos.map(row => row.id);
    if (ids.length) {
      state.items = await getAll(() => sb.from('pedidos_items')
        .select('*').in('pedido_id', ids).order('creado_en'));
    } else state.items = [];

    const pedidoIds = ids;
    state.orders = pedidoIds.length
      ? await getAll(() => sb.from('ordenes_compra')
          .select('id,numero,pedido_id,proveedor_id,estado,creado_en')
          .in('pedido_id', pedidoIds)
          .order('creado_en', { ascending:false }))
      : [];
    const orderIds = state.orders.map(order => order.id);
    state.orderItems = orderIds.length
      ? await getAll(() => sb.from('ordenes_compra_items')
          .select('id,orden_id,pedido_item_id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base')
          .in('orden_id', orderIds)
          .order('creado_en'))
      : [];
  }

  function itemsFor(pedidoId) {
    return state.items.filter(item => item.pedido_id === pedidoId);
  }
  function ordersFor(pedidoId) {
    return state.orders.filter(order => order.pedido_id === pedidoId && order.estado !== 'cancelada');
  }
  function alreadyOrdered(itemId) {
    const orderIds = new Set(state.orders.filter(order => order.estado !== 'cancelada').map(order => order.id));
    return state.orderItems.filter(item => item.pedido_item_id === itemId && orderIds.has(item.orden_id))
      .reduce((sum,item) => sum + (Number(item.unidades_solicitadas) || 0), 0);
  }

  function renderShell() {
    root.innerHTML = `
      <div class="pedidos-module">
        <header class="pedidos-heading">
          <div><span class="pedidos-kicker">ABASTECIMIENTO</span><h2>Pedidos</h2>
            <p>Gestiona las necesidades de compra del negocio.</p></div>
          <span class="pedidos-role">${isAdmin() ? 'Administrador' : 'Vendedor'}</span>
        </header>
        <p class="pedidos-message" data-pedidos-message role="status" hidden></p>
        <div data-pedidos-panel></div>
      </div>`;
  }

  function renderHome() {
    return `
      <section class="pedidos-home">
        <button type="button" class="pedidos-home-card pedidos-home-suggested" data-mode="sugerido">
          <span class="pedidos-home-icon" aria-hidden="true">↻</span>
          <span><b>Pedido sugerido</b><small>Reposición automática según rotación, existencias y compras pendientes.</small></span>
          <span class="pedidos-home-arrow" aria-hidden="true">›</span>
        </button>
        <button type="button" class="pedidos-home-card" data-mode="urgente">
          <span class="pedidos-home-icon" aria-hidden="true">!</span>
          <span><b>Pedido urgente</b><small>Solo productos con inventario negativo.</small></span>
          <span class="pedidos-home-arrow" aria-hidden="true">›</span>
        </button>
        <button type="button" class="pedidos-home-card" data-mode="extraordinario">
          <span class="pedidos-home-icon" aria-hidden="true">＋</span>
          <span><b>Pedido extraordinario</b><small>Ampliar inventario, incorporar productos u oportunidades comerciales.</small></span>
          <span class="pedidos-home-arrow" aria-hidden="true">›</span>
        </button>
        <button type="button" class="pedidos-home-history" data-mode="seguimiento">Ver seguimiento de pedidos <span>›</span></button>
      </section>`;
  }

  function renderTracking() {
    return `
      <section class="pedidos-panel">
        <div class="pedidos-section-title">
          <div><h3>Seguimiento de pedidos</h3><p>Consulta solicitudes, autorizaciones y órdenes generadas.</p></div>
          <div class="pedidos-heading-actions">
            <button type="button" class="btn alt" data-action="go-remisiones">Abrir Remisiones</button>
            <button type="button" class="btn alt" data-action="refresh">Actualizar</button>
          </div>
        </div>
        <div data-pedidos-list></div>
        <div class="pedidos-actions"><button type="button" class="btn alt" data-action="back-home">Volver a pedidos</button></div>
      </section>`;
  }

  function renderSuggested() {
    const total = state.suggested.reduce((sum,row) => sum + row.suggestedUnits, 0);
    const rows = state.suggested.map((row,index) => `
      <article class="pedidos-suggest-row">
        <div class="pedidos-product">
          <b>${esc(row.product.nombre)}</b>
          ${row.stockUnits < 0 ? '<span class="pedidos-stock-alert">Existencia negativa · déficit de ' + units(Math.abs(row.stockUnits)) + ' unidades</span>' : ''}
          <small>${esc(row.product.codigo || 'Sin código')} · ${esc(row.product.laboratorio || 'Sin laboratorio')}</small>
        </div>
        <div class="pedidos-metrics">
          <span>Vendido 7 días <b>${units(row.soldUnits)}</b></span>
          <span>Existencia <b>${units(row.stockUnits)}</b></span>
          <span>Por recibir <b>${units(row.pendingUnits)}</b></span>
        </div>
        <label class="pedidos-qty">Unidades a pedir
          <input type="number" min="0" step="1" value="${row.suggestedUnits}"
            data-suggested-qty="${index}" inputmode="numeric">
        </label>
      </article>`).join('');
    return `
      <section class="pedidos-panel">
        <div class="pedidos-section-title"><div><h3>Pedido sugerido</h3>
          <p>Propuesta de reposición basada en los últimos 7 días.</p></div>
          <button type="button" class="btn alt" data-action="recalc">Recalcular</button>
        </div>
        <button type="button" class="pedidos-back-link" data-action="back-home">‹ Volver a pedidos</button>
        <div class="pedidos-kpis">
          <div><small>Productos por reponer</small><b>${units(state.suggested.length)}</b></div>
          <div><small>Unidades sugeridas</small><b>${units(total)}</b></div>
          <div><small>Cobertura objetivo</small><b>7 días</b></div>
        </div>
        <p class="pedidos-note">Con saldo negativo, primero se cubre el déficit sin contar dos veces las ventas que lo generaron. Con saldo cero o positivo, se cubre la rotación de 7 días. Se descuentan las órdenes pendientes y los pedidos autorizados aún no asignados a proveedor. Recalcular consulta los datos; no crea pedidos.</p>
        ${state.suggestedCalculatedAt ? '<p class="pedidos-calculated-at">Última consulta: ' + state.suggestedCalculatedAt.toLocaleTimeString('es-CO',{hour:'2-digit',minute:'2-digit'}) + '</p>' : ''}
        <div class="pedidos-suggest-list">${rows || '<p class="pedidos-empty">No hay productos que requieran reposición según los datos actuales.</p>'}</div>
        <div class="pedidos-actions">
          <button type="button" class="btn alt" data-action="save-suggested">Guardar borrador</button>
          <button type="button" class="btn" data-action="send-suggested">Guardar y enviar a autorización</button>
        </div>
      </section>`;
  }

  function renderManualForm() {
    const editing = !!state.editing;
    const urgentMode = state.mode === 'urgente' || state.editing?.tipo === 'urgente';
    const selectableProducts = urgentMode ? state.negativeProducts : state.products;
    const options = selectableProducts.map(product =>
      `<option value="${esc(product.nombre)}" label="${esc([product.codigo,product.laboratorio].filter(Boolean).join(' · '))}"></option>`
      + (product.codigo ? `<option value="${esc(product.codigo)}" label="${esc(product.nombre)}"></option>` : '')
    ).join('');
    const formatBoxes = value => Number(value || 0).toLocaleString('es-CO',{maximumFractionDigits:2});
    const urgentRows = state.formItems.map((item,index) => {
      const product = state.products.find(row => row.id === item.producto_id);
      const packageUnits = Math.max(1,Number(product?.unidades_por_caja) || 1);
      return `<tr>
        <td><strong>${esc(product?.codigo || '—')}</strong></td>
        <td>${esc(product?.nombre || item.producto_nombre)}</td>
        <td>${units(packageUnits)}</td>
        <td>${formatBoxes(Number(item.cantidad_solicitada) / packageUnits)}</td>
        <td><button type="button" class="pedidos-remove" data-action="remove-line" data-index="${index}" aria-label="Quitar producto">×</button></td>
      </tr>`;
    }).join('');
    const urgentCards = state.formItems.map((item,index) => {
      const product = state.products.find(row => row.id === item.producto_id);
      const packageUnits = Math.max(1,Number(product?.unidades_por_caja) || 1);
      return `<article class="pedidos-urgent-card">
        <div class="pedidos-urgent-card-head"><div><small>CÓDIGO ${esc(product?.codigo || '—')}</small><b>${esc(product?.nombre || item.producto_nombre)}</b></div>
          <button type="button" class="pedidos-remove" data-action="remove-line" data-index="${index}" aria-label="Quitar ${esc(product?.nombre || item.producto_nombre)}">×</button></div>
        <div class="pedidos-urgent-card-data"><span><small>Unidades por caja</small><b>${units(packageUnits)}</b></span><span><small>Cajas solicitadas</small><b>${formatBoxes(Number(item.cantidad_solicitada) / packageUnits)}</b></span></div>
      </article>`;
    }).join('');
    const lines = urgentMode ? '' : state.formItems.map((item,index) => `<article class="pedidos-form-line">
      <div><b>${esc(item.producto_nombre)}</b><small>${item.producto_id ? 'Producto del catálogo' : 'Producto por vincular al catálogo'}</small></div>
      <span>${units(item.cantidad_solicitada)} unidades</span>
      <button type="button" class="pedidos-remove" data-action="remove-line" data-index="${index}" aria-label="Quitar producto">×</button>
    </article>`).join('');
    const modeLabel = state.editing ? (state.editing.tipo === 'sugerido' ? 'Pedido sugerido' : state.editing.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario')
      : state.mode === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario';
    return `
      <section class="pedidos-panel">
        <div class="pedidos-section-title"><div><h3>${modeLabel}</h3>
          <p>${urgentMode ? 'Selecciona únicamente productos con inventario negativo y define cuántas cajas necesitas.' : state.editing ? 'Edita el borrador y guarda los cambios.' : 'Solicita cantidades adicionales o incorpora productos.'}</p></div>
          ${editing ? '<span class="pedidos-tag">Editando borrador</span>' : ''}</div>
        <button type="button" class="pedidos-back-link" data-action="back-home">‹ Volver a pedidos</button>
        <div class="pedidos-form-grid">
          <div class="pedidos-field pedidos-field-wide">
            <label for="ped-product-name">${urgentMode ? 'Producto con inventario negativo' : 'Producto del catálogo o nombre libre'}</label>
            <input id="ped-product-name" list="ped-product-options" placeholder="${urgentMode ? 'Busca por código o nombre' : 'Busca por nombre o escribe el producto'}">
            <datalist id="ped-product-options">${options}</datalist>
            <small>${urgentMode ? 'La lista solo incluye productos cuyo saldo actual es menor que cero.' : 'Si no está en el catálogo, puedes escribirlo. Para generar una orden deberá vincularse después.'}</small>
          </div>
          <div class="pedidos-field">
            <label for="ped-product-qty">${urgentMode ? 'Cajas a solicitar' : 'Cantidad solicitada (unidades)'}</label>
            <input id="ped-product-qty" type="number" min="1" step="1" value="1" inputmode="numeric">
          </div>
        </div>
        <button type="button" class="btn alt" data-action="add-line">Agregar producto al pedido</button>
        ${urgentMode ? `
          <div class="pedidos-urgent-table-wrap">
            <table class="pedidos-urgent-table">
              <thead><tr><th>Producto</th><th>Descripción</th><th>Cant Empaq</th><th>Cajas</th><th aria-label="Quitar"></th></tr></thead>
              <tbody>${urgentRows || '<tr><td colspan="5" class="pedidos-empty">Agrega al menos un producto.</td></tr>'}</tbody>
            </table>
          </div>
          <div class="pedidos-urgent-cards">${urgentCards || '<p class="pedidos-empty">Agrega al menos un producto.</p>'}</div>` : `
          <div class="pedidos-form-lines">${lines || '<p class="pedidos-empty">Agrega al menos un producto.</p>'}</div>
          <div class="pedidos-field">
            <label for="ped-product-reason">Motivo / justificación</label>
            <input id="ped-product-reason" maxlength="500" placeholder="Ej. Nueva referencia / oportunidad comercial">
          </div>
          <div class="pedidos-field">
            <label for="ped-notes">Notas generales (opcional)</label>
            <textarea id="ped-notes" rows="2" maxlength="1000">${esc(state.editing?.notas || '')}</textarea>
          </div>`}
        <div class="pedidos-actions">
          <button type="button" class="btn alt" data-action="save-draft">Guardar borrador</button>
          <button type="button" class="btn" data-action="save-send">Guardar y enviar a autorización</button>
          ${editing ? '<button type="button" class="btn alt" data-action="cancel-edit">Salir de edición</button>' : ''}
        </div>
      </section>`;
  }

  function renderAuthorization(pedido, items) {
    const catalogOptions = state.products.map(product =>
      `<option value="${esc(product.nombre)}" label="${esc(product.codigo || '')}"></option>`
      + (product.codigo ? `<option value="${esc(product.codigo)}" label="${esc(product.nombre)}"></option>` : '')
    ).join('');
    return `
      <div class="pedidos-admin-box">
        <b>Revisión del administrador</b>
        <p>Modifica las cantidades que vas a autorizar. Si el producto se escribió como texto, vincúlalo al catálogo aquí.</p>
        <datalist id="ped-auth-catalog-${pedido.id}">${catalogOptions}</datalist>
        ${items.map(item => {
          const product = state.products.find(row => row.id === item.producto_id);
          return `
          <div class="pedidos-auth-line">
            <span>${esc(item.producto_nombre)}<small>Solicitado: ${units(item.cantidad_solicitada)} unidades</small></span>
            <input type="search" list="ped-auth-catalog-${pedido.id}" value="${esc(product?.nombre || '')}"
              placeholder="Vincular al catálogo" data-auth-product="${item.id}"
              aria-label="Producto de catálogo para ${esc(item.producto_nombre)}">
            <input type="number" min="0" max="${item.cantidad_solicitada}" step="1"
              value="${item.cantidad_solicitada}" data-auth-qty="${item.id}" aria-label="Cantidad autorizada para ${esc(item.producto_nombre)}">
          </div>`;
        }).join('')}
        <div class="pedidos-actions">
          <button type="button" class="btn" data-action="authorize" data-pedido-id="${pedido.id}">Autorizar pedido</button>
          <button type="button" class="btn bad" data-action="reject" data-pedido-id="${pedido.id}">Rechazar pedido</button>
        </div>
      </div>`;
  }

  function providerOptions(selected) {
    return state.providers.map(provider =>
      `<option value="${provider.id}" ${provider.id === selected ? 'selected' : ''}>${esc(provider.nombre)}</option>`
    ).join('');
  }

  function renderAllocation(pedido, item) {
    const approved = Number(item.cantidad_autorizada) || 0;
    const already = alreadyOrdered(item.id);
    const remaining = Math.max(0, approved - already);
    if (!item.producto_id) {
      return `<p class="pedidos-warning">Vincula “${esc(item.producto_nombre)}” al catálogo antes de generar una orden.</p>`;
    }
    if (!remaining) return `<p class="pedidos-done">Unidades autorizadas ya asignadas: ${units(already)} / ${units(approved)}</p>`;
    if (!state.providers.length) return '<p class="pedidos-warning">Registra al menos un proveedor activo antes de generar órdenes.</p>';
    const defaultCost = Number(item.costo_estimado) || 0;
    return `
      <div class="pedidos-allocation" data-allocation-item="${item.id}" data-remaining="${remaining}">
        <div class="pedidos-allocation-head"><b>Asignar a proveedor</b>
          <small>Por asignar: ${units(remaining)} unidades · Ya asignado: ${units(already)}</small></div>
        <div class="pedidos-allocation-rows">
          <div class="pedidos-allocation-row" data-allocation-row>
            <select data-alloc-provider aria-label="Proveedor">${providerOptions(state.providers[0].id)}</select>
            <input type="number" min="1" step="1" max="${remaining}" value="${remaining}" data-alloc-units aria-label="Unidades a comprar">
            <input type="number" min="0" step="0.01" value="${defaultCost}" data-alloc-cost aria-label="Costo unitario base">
          </div>
        </div>
        <button type="button" class="btn alt" data-action="add-allocation">Dividir con otro proveedor</button>
      </div>`;
  }

  function renderOrderGeneration(pedido, items) {
    const lines = items.filter(item => (Number(item.cantidad_autorizada) || 0) > 0)
      .map(item => `
        <article class="pedidos-order-line">
          <div><b>${esc(item.producto_nombre)}</b>
            <small>Autorizado: ${units(item.cantidad_autorizada)} unidades</small></div>
          ${renderAllocation(pedido,item)}
        </article>`).join('');
    return `
      <div class="pedidos-admin-box">
        <b>Generar órdenes de compra</b>
        <p>Este pedido ya está autorizado, pero todavía no aumenta el inventario. Asigna cada línea a uno o varios proveedores; Drosalud agrupará una orden por proveedor. El Kardex solo cambiará cuando registres la recepción física.</p>
        ${lines}
        ${items.some(item => item.producto_id && (Number(item.cantidad_autorizada)||0) > alreadyOrdered(item.id))
        ? `<button type="button" class="btn full" data-action="generate-orders" data-pedido-id="${pedido.id}">Asignar proveedores y generar órdenes</button>`
        : '<p class="pedidos-done">No quedan unidades autorizadas pendientes de asignar.</p>'}
      </div>`;
  }

  // Vista resumida: un pedido por fila, sin formularios mezclados.
  function renderPedidoSummary(pedido) {
    const status = pedido.estado_operativo || pedido.estado;
    const type = pedido.tipo === 'sugerido' ? 'Sugerido' : pedido.tipo === 'urgente' ? 'Urgente' : 'Extraordinario';
    const date = new Date(pedido.creado_en).toLocaleDateString('es-CO');
    const count = itemsFor(pedido.id).length;
    return `
      <article class="pedidos-card pedidos-summary-card">
        <div class="pedidos-card-head">
          <div>
            <span class="pedidos-number">Pedido #${esc(pedido.numero)}</span>
            <h4>${type}</h4>
            <small>${date} · ${count} producto(s)</small>
          </div>
          <span class="pedidos-status status-${esc(status)}">${statusLabel(status)}</span>
        </div>
        <button type="button" class="btn full" data-action="open-pedido" data-pedido-id="${pedido.id}">Abrir pedido</button>
      </article>`;
  }

  // Expediente individual: aquí viven los datos y las acciones de ESTE pedido.
  function renderPedidoCard(pedido) {
    const items = itemsFor(pedido.id);
    const canEdit = pedido.estado === 'borrador' && (isAdmin() || pedido.creado_por === state.user.id);
    const relatedOrders = ordersFor(pedido.id);
    const details = items.map(item =>
      `<tr><td>${esc(item.producto_nombre)}</td><td>${units(item.cantidad_solicitada)}</td><td>${units(item.cantidad_autorizada)}</td></tr>`
    ).join('');
    let controls = '';
    if (canEdit) {
      controls = `<div class="pedidos-actions">
        <button type="button" class="btn alt" data-action="edit" data-pedido-id="${pedido.id}">Editar borrador</button>
        <button type="button" class="btn" data-action="send" data-pedido-id="${pedido.id}">Enviar a autorización</button>
      </div>`;
    } else if (isAdmin() && pedido.estado === 'pendiente_autorizacion') {
      controls = renderAuthorization(pedido,items);
    } else if (isAdmin() && pedido.estado === 'autorizado') {
      controls = renderOrderGeneration(pedido,items);
    }
    const orderSummary = relatedOrders.length
      ? `<section class="pedidos-document-section"><h4>Órdenes de compra relacionadas</h4><ul>${relatedOrders.map(order => {
          const provider = state.providers.find(row => row.id === order.proveedor_id);
          return `<li>OC-${esc(order.numero)} · ${esc(provider?.nombre || 'Proveedor')} · ${statusLabel(order.estado)}</li>`;
        }).join('')}</ul></section>`
      : '<p class="pedidos-muted">Todavía no hay órdenes de compra relacionadas.</p>';
    const status = pedido.estado_operativo || pedido.estado;
    return `
      <article class="pedidos-card pedidos-document" data-pedido-document>
        <div class="pedidos-document-toolbar">
          <button type="button" class="btn alt" data-action="back-to-list">‹ Volver al seguimiento</button>
          <button type="button" class="btn" data-action="print-pedido" data-pedido-id="${pedido.id}">Descargar PDF / Imprimir</button>
        </div>
        <header class="pedidos-document-header">
          <div><span class="pedidos-number">DROSALUD · DOCUMENTO INTERNO</span><h2>Pedido #${esc(pedido.numero)}</h2><p>${pedido.tipo === 'sugerido' ? 'Pedido sugerido' : pedido.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario'}</p></div>
          <span class="pedidos-status status-${esc(status)}">${statusLabel(status)}</span>
        </header>
        <section class="pedidos-document-section pedidos-document-meta">
          <div><small>Fecha de creación</small><b>${new Date(pedido.creado_en).toLocaleString('es-CO')}</b></div>
          <div><small>Estado actual</small><b>${statusLabel(status)}</b></div>
          <div><small>Productos</small><b>${items.length}</b></div>
        </section>
        <section class="pedidos-document-section">
          <h4>Detalle de productos</h4>
          <div class="pedidos-document-table-wrap"><table class="pedidos-document-table"><thead><tr><th>Producto</th><th>Solicitado (unidades)</th><th>Autorizado (unidades)</th></tr></thead><tbody>${details || '<tr><td colspan="3">Sin productos registrados.</td></tr>'}</tbody></table></div>
        </section>
        ${pedido.notas ? `<section class="pedidos-document-section"><h4>Observaciones</h4><p>${esc(pedido.notas)}</p></section>` : ''}
        ${pedido.motivo_rechazo ? `<section class="pedidos-document-section pedidos-warning"><h4>Motivo del rechazo</h4><p>${esc(pedido.motivo_rechazo)}</p></section>` : ''}
        ${['autorizado','parcial','completado'].includes(status) ? `
          <section class="pedidos-document-section">
            <h4>Resumen de compra</h4>
            <div class="pedidos-summary"><span>Autorizado: <b>${units(pedido.unidades_autorizadas)}</b></span><span>Comprado: <b>${units(pedido.unidades_compradas)}</b></span><span>Recibido: <b>${units(pedido.unidades_recibidas)}</b></span></div>
          </section>` : ''}
        <section class="pedidos-document-section">${orderSummary}</section>
        <section class="pedidos-document-actions"><h4>Acciones disponibles</h4>${controls || '<p class="pedidos-muted">No hay acciones pendientes para este estado.</p>'}</section>
      </article>`;
  }

  function renderList() {
    const box = root.querySelector('[data-pedidos-list]');
    if (!box) return;
    if (state.selectedPedidoId) {
      const pedido = state.pedidos.find(row => row.id === state.selectedPedidoId);
      box.innerHTML = pedido
        ? renderPedidoCard(pedido)
        : '<p class="pedidos-empty">No se encontró el pedido seleccionado. Actualiza el seguimiento.</p>';
      return;
    }
    box.innerHTML = state.pedidos.length
      ? state.pedidos.map(renderPedidoSummary).join('')
      : '<p class="pedidos-empty">Todavía no hay pedidos registrados.</p>';
  }

  function printPedido(pedidoId) {
    const pedido = state.pedidos.find(row => row.id === pedidoId);
    if (!pedido) throw new Error('No se encontró el pedido que deseas imprimir.');
    const items = itemsFor(pedido.id);
    const orders = ordersFor(pedido.id);
    const status = pedido.estado_operativo || pedido.estado;
    const printWindow = window.open('', '_blank');
    if (!printWindow) throw new Error('El navegador bloqueó la ventana. Permite las ventanas emergentes para descargar el PDF.');
    const rows = items.map(item => `<tr><td>${esc(item.producto_nombre)}</td><td>${units(item.cantidad_solicitada)}</td><td>${units(item.cantidad_autorizada)}</td></tr>`).join('');
    const orderRows = orders.map(order => {
      const provider = state.providers.find(row => row.id === order.proveedor_id);
      return `<tr><td>OC-${esc(order.numero)}</td><td>${esc(provider?.nombre || 'Proveedor')}</td><td>${statusLabel(order.estado)}</td></tr>`;
    }).join('');
    printWindow.document.write(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Pedido ${esc(pedido.numero)} · Drosalud</title><style>
      *{box-sizing:border-box}body{font:13px Arial,sans-serif;color:#172033;margin:32px}header{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #243b64;padding-bottom:16px}h1{font-size:24px;margin:6px 0}h2{font-size:15px;margin:22px 0 9px}small{color:#667085}.status{border:1px solid #9aa4b2;border-radius:20px;padding:7px 11px;font-weight:bold} .meta{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin:18px 0}.meta div{padding:10px;background:#f4f6f8}.meta b{display:block;margin-top:5px}table{width:100%;border-collapse:collapse;margin-top:8px}th,td{text-align:left;padding:9px;border-bottom:1px solid #d8dde5}th{background:#f1f3f6}p{line-height:1.5}.foot{margin-top:32px;color:#667085;font-size:11px}@media print{body{margin:16mm}button{display:none}}
      </style></head><body><header><div><small>DROSALUD · DOCUMENTO INTERNO DE COMPRA</small><h1>Pedido #${esc(pedido.numero)}</h1><div>${pedido.tipo === 'sugerido' ? 'Pedido sugerido' : pedido.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario'}</div></div><span class="status">${statusLabel(status)}</span></header>
      <div class="meta"><div><small>Fecha de creación</small><b>${new Date(pedido.creado_en).toLocaleString('es-CO')}</b></div><div><small>Estado</small><b>${statusLabel(status)}</b></div><div><small>Total de productos</small><b>${items.length}</b></div></div>
      <h2>Detalle de productos</h2><table><thead><tr><th>Producto</th><th>Solicitado (unidades)</th><th>Autorizado (unidades)</th></tr></thead><tbody>${rows}</tbody></table>
      ${pedido.notas ? `<h2>Observaciones</h2><p>${esc(pedido.notas)}</p>` : ''}
      ${pedido.motivo_rechazo ? `<h2>Motivo del rechazo</h2><p>${esc(pedido.motivo_rechazo)}</p>` : ''}
      <h2>Órdenes de compra relacionadas</h2><table><thead><tr><th>Orden</th><th>Proveedor</th><th>Estado</th></tr></thead><tbody>${orderRows || '<tr><td colspan="3">No se han generado órdenes.</td></tr>'}</tbody></table>
      <p class="foot">Documento generado desde Drosalud. Este PDF representa el pedido interno y no sustituye las órdenes de compra ni los documentos del proveedor.</p><script>window.onload=()=>window.print();</script></body></html>`);
    printWindow.document.close();
  }

  function renderPanel() {
    const panel = root.querySelector('[data-pedidos-panel]');
    if (!panel) return;
    if (state.mode === 'inicio' && !state.editing) panel.innerHTML = renderHome();
    else if (state.mode === 'seguimiento' && !state.editing) panel.innerHTML = renderTracking();
    else if (state.mode === 'sugerido' && !state.editing) {
      panel.innerHTML = state.loading
        ? '<section class="pedidos-panel pedidos-loading">Analizando ventas, existencias y compras pendientes…</section>'
        : renderSuggested();
    } else panel.innerHTML = renderManualForm();
    if (state.mode === 'seguimiento') renderList();
  }

  function render() {
    renderShell();
    renderPanel();
  }

  function resolveProduct(value) {
    const q = norm(value);
    if (!q) return null;
    const digits = q.replace(/\D/g,'');
    return state.products.find(product =>
      norm(product.nombre) === q || norm(product.codigo) === q
      || (digits.length >= 4 && String(product.codigo || '').replace(/\D/g,'').includes(digits))
    ) || null;
  }

  function readSuggestedItems() {
    return state.suggested.map((row,index) => {
      const input = root.querySelector('[data-suggested-qty="' + index + '"]');
      const quantity = Number(input?.value);
      if (!Number.isInteger(quantity) || quantity <= 0) return null;
      return {
        producto_id: row.product.id,
        producto_nombre: row.product.nombre,
        cantidad_solicitada: quantity,
        justificacion: 'Reposición sugerida por rotación de los últimos 7 días',
        costo_estimado: Number(row.product.precio_compra) || null
      };
    }).filter(Boolean);
  }

  async function savePedido(items, tipo, notas, existingId = null) {
    if (!items.length) throw new Error('Agrega al menos un producto con cantidad mayor que cero.');
    const { data, error } = await sb.rpc('guardar_pedido', {
      p_pedido_id: existingId,
      p_tipo: tipo,
      p_notas: notas || null,
      p_items: items
    });
    if (error) throw error;
    return data;
  }

  async function saveSuggested(send) {
    const items = readSuggestedItems();
    const id = await savePedido(items,'sugerido','Propuesta automática de rotación · cobertura de 7 días');
    if (send) {
      const {error} = await sb.rpc('enviar_pedido',{p_pedido_id:id});
      if (error) {
        try {
          await loadData();
          const current = state.pedidos.find(pedido => pedido.id === id);
          if (current && current.estado !== 'borrador') {
            state.mode = 'seguimiento';
            await reload();
            message('Pedido sugerido enviado a autorización.');
            return;
          }
        } catch (reloadError) {
          console.warn('No se pudo verificar el estado del pedido sugerido:', reloadError);
        }
        state.mode = 'seguimiento';
        await reload();
        message('El borrador quedó guardado, pero no se pudo confirmar el envío. Verifica su estado en Seguimiento antes de reintentar.', true);
        return;
      }
    }
    state.mode = 'seguimiento';
    await reload();
    message(send ? 'Pedido sugerido enviado a autorización.' : 'Pedido sugerido guardado como borrador.');
  }

  async function saveManual(send) {
    const tipo = state.editing?.tipo || state.mode;
    const urgente = tipo === 'urgente';
    const notas = urgente ? '' : (root.querySelector('#ped-notes')?.value.trim() || '');
    const items = state.formItems.map(item => ({
      ...(item.id ? {id:item.id} : {}),
      producto_id:item.producto_id || null,
      producto_nombre:item.producto_nombre,
      cantidad_solicitada:item.cantidad_solicitada,
      justificacion:tipo === 'urgente' ? null : (item.justificacion || null),
      costo_estimado:item.costo_estimado ?? null
    }));
    const id = await savePedido(items,tipo,notas,state.editing?.id || null);
    if (send) {
      const {error} = await sb.rpc('enviar_pedido',{p_pedido_id:id});
      if (error) {
        try {
          await loadData();
          const current = state.pedidos.find(pedido => pedido.id === id);
          if (current && current.estado !== 'borrador') {
            state.editing = null;
            state.formItems = [];
            state.mode = 'seguimiento';
            render();
            message('Pedido enviado a autorización.');
            return;
          }
        } catch (reloadError) {
          console.warn('No se pudo verificar el estado del pedido:', reloadError);
        }
        state.editing = {id,tipo};
        message('El borrador quedó guardado, pero no se pudo confirmar el envío. Verifica su estado en Seguimiento antes de reintentar.', true);
        return;
      }
    }
    state.editing = null;
    state.formItems = [];
    state.mode = 'seguimiento';
    await reload();
    message(send ? 'Pedido enviado a autorización.' : 'Borrador guardado correctamente.');
  }

  async function reload() {
    await loadData();
    render();
  }

  async function authorize(pedidoId) {
    const items = itemsFor(pedidoId).map(item => {
      const input = root.querySelector('[data-auth-qty="' + item.id + '"]');
      const value = Number(input?.value);
      const productInput = root.querySelector('[data-auth-product="' + item.id + '"]');
      const productValue = productInput?.value.trim() || '';
      const product = productValue ? resolveProduct(productValue) : null;
      if (!Number.isInteger(value) || value < 0 || value > Number(item.cantidad_solicitada)) {
        throw new Error('Revisa las cantidades autorizadas.');
      }
      if (productValue && !product) throw new Error('Selecciona un producto válido del catálogo para vincularlo.');
      return {
        pedido_item_id:item.id,
        cantidad_autorizada:value,
        producto_id:product?.id || item.producto_id || null
      };
    });
    const {error} = await sb.rpc('autorizar_pedido',{
      p_pedido_id:pedidoId,p_items:items
    });
    if (error) throw error;
    await reload();
    message('Pedido autorizado. Ahora puedes asignarlo a proveedores.');
  }

  async function reject(pedidoId) {
    const reason = window.prompt('Motivo del rechazo:');
    if (reason === null) return;
    if (!reason.trim()) throw new Error('Escribe el motivo del rechazo.');
    const {error} = await sb.rpc('rechazar_pedido',{
      p_pedido_id:pedidoId,p_motivo:reason.trim()
    });
    if (error) throw error;
    await reload();
    message('Pedido rechazado. El motivo quedó registrado.');
  }

  async function generateOrders(pedidoId, card) {
    const assignments = [];
    card.querySelectorAll('[data-allocation-item]').forEach(itemBox => {
      const itemId = itemBox.dataset.allocationItem;
      itemBox.querySelectorAll('[data-allocation-row]').forEach(row => {
        const providerId = row.querySelector('[data-alloc-provider]')?.value;
        const quantity = Number(row.querySelector('[data-alloc-units]')?.value);
        const cost = Number(row.querySelector('[data-alloc-cost]')?.value);
        if (!providerId || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(cost) || cost < 0) {
          throw new Error('Revisa proveedor, unidades y costo de cada asignación.');
        }
        assignments.push({
          pedido_item_id:itemId,proveedor_id:providerId,unidades:quantity,costo_unitario_base:cost
        });
      });
    });
    if (!assignments.length) throw new Error('No hay cantidades pendientes para asignar.');
    const operationId = state.operationIds[pedidoId] || crypto.randomUUID();
    state.operationIds[pedidoId] = operationId;
    const {data,error} = await sb.rpc('generar_ordenes_compra_pedido',{
      p_pedido_id:pedidoId,p_asignaciones:assignments,p_operacion_id:operationId
    });
    if (error) throw error;
    await reload();
    delete state.operationIds[pedidoId];
    const count = Array.isArray(data?.ordenes) ? data.ordenes.length : 0;
    message(count + (count === 1 ? ' orden de compra generada.' : ' órdenes de compra generadas.'));
  }

  function addAllocation(button) {
    const box = button.closest('[data-allocation-item]');
    const rows = box?.querySelector('.pedidos-allocation-rows');
    if (!rows) return;
    const itemId = box.dataset.allocationItem;
    const item = state.items.find(row => row.id === itemId);
    const remaining = Number(box.dataset.remaining) || 0;
    if (remaining <= 1) {
      message('No hay unidades suficientes para dividir esta línea entre proveedores.',true);
      return;
    }
    const existingRows = [...rows.querySelectorAll('[data-allocation-row]')];
    const used = existingRows.reduce((sum,row) => sum + (Number(row.querySelector('[data-alloc-units]')?.value)||0),0);
    let nextUnits = remaining - used;
    if (nextUnits <= 0 && existingRows.length) {
      const first = existingRows[0].querySelector('[data-alloc-units]');
      const firstValue = Number(first?.value)||0;
      if (first && firstValue > 1) {
        first.value = String(firstValue - 1);
        nextUnits = 1;
      }
    }
    if (nextUnits <= 0) nextUnits = 1;
    const row = document.createElement('div');
    row.className = 'pedidos-allocation-row';
    row.setAttribute('data-allocation-row','');
    row.innerHTML = `
      <select data-alloc-provider aria-label="Proveedor">${providerOptions(state.providers[0]?.id)}</select>
      <input type="number" min="1" step="1" max="${remaining}" value="${nextUnits}" data-alloc-units aria-label="Unidades a comprar">
      <input type="number" min="0" step="0.01" value="${Number(item?.costo_estimado)||0}" data-alloc-cost aria-label="Costo unitario base">
      <button type="button" class="pedidos-remove-allocation" aria-label="Quitar asignación">×</button>`;
    rows.appendChild(row);
  }

  function editPedido(pedidoId) {
    const pedido = state.pedidos.find(row => row.id === pedidoId);
    if (!pedido) return;
    state.editing = pedido;
    state.formItems = itemsFor(pedidoId).map(item => ({...item}));
    state.mode = 'editor';
    renderPanel();
    root.querySelector('[data-pedidos-panel]')?.scrollIntoView({behavior:'smooth',block:'start'});
  }

  async function handleClick(event) {
    if (state.loading) return;
    const modeButton = event.target.closest('[data-mode]');
    if (modeButton) {
      state.editing = null;
      state.formItems = [];
      state.mode = modeButton.dataset.mode;
      message('');
      if (state.mode === 'sugerido') {
        state.loading = true;
        renderPanel();
        try {
          await loadSuggested();
        } catch (error) {
          console.error('PEDIDOS sugerido:',error);
          message(error?.message || 'No se pudo calcular el pedido sugerido.',true);
        } finally {
          state.loading = false;
          renderPanel();
        }
      } else {
        renderPanel();
      }
      return;
    }
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const action = button.dataset.action;
    try {
      button.disabled = true;
      if (action === 'go-remisiones') {
        if (typeof show === 'function') show('recepcion');
        return;
      } else if (action === 'open-pedido') {\n        state.selectedPedidoId = button.dataset.pedidoId;\n        renderPanel();\n      } else if (action === 'back-to-list') {\n        state.selectedPedidoId = null;\n        renderPanel();\n      } else if (action === 'print-pedido') {\n        printPedido(button.dataset.pedidoId);\n      } else if (action === 'back-home') {
        state.editing = null; state.formItems = []; state.selectedPedidoId = null; state.mode = 'inicio'; message(''); renderPanel();
      } else if (action === 'refresh') {
        if (state.mode === 'seguimiento') { await reload(); message('Datos actualizados.'); }
        else if (state.mode === 'sugerido') { await loadSuggested(); renderPanel(); message('Cálculo actualizado.'); }
        else { await loadData(); renderPanel(); message('Datos actualizados.'); }
      } else if (action === 'recalc') {
        if (state.loading) return;
        state.loading = true; renderPanel();
        try {
          await loadSuggested();
          message('Cálculo actualizado con los datos más recientes. No se creó ningún pedido.');
        } finally {
          state.loading = false;
          renderPanel();
        }
      } else if (action === 'save-suggested') {
        await saveSuggested(false);
      } else if (action === 'send-suggested') {
        await saveSuggested(true);
      } else if (action === 'add-line') {
        const nameInput = root.querySelector('#ped-product-name');
        const urgentMode = state.mode === 'urgente' || state.editing?.tipo === 'urgente';
        const quantity = Number(root.querySelector('#ped-product-qty')?.value);
        const reason = urgentMode ? '' : (root.querySelector('#ped-product-reason')?.value.trim() || '');
        const name = nameInput?.value.trim() || '';
        if (!name) throw new Error('Escribe o selecciona un producto.');
        if (!Number.isInteger(quantity) || quantity <= 0) throw new Error(urgentMode ? 'La cantidad de cajas debe ser un entero mayor que cero.' : 'La cantidad debe ser un entero mayor que cero.');
        const product = resolveProduct(name);
        if (urgentMode && (!product || !state.negativeProducts.some(row => row.id === product.id))) {
          throw new Error('El pedido urgente solo admite productos con inventario negativo. Actualiza los datos e inténtalo de nuevo.');
        }
        const productName = product?.nombre || name;
        const packageUnits = urgentMode ? Math.max(1,Number(product?.unidades_por_caja) || 1) : 1;
        const requestedUnits = urgentMode ? quantity * packageUnits : quantity;
        const existing = state.formItems.find(item => product
          ? item.producto_id === product.id
          : !item.producto_id && norm(item.producto_nombre) === norm(productName));
        if (existing) existing.cantidad_solicitada += requestedUnits;
        else state.formItems.push({
          producto_id:product?.id || null,producto_nombre:productName,
          cantidad_solicitada:requestedUnits,justificacion:reason || null,costo_estimado:null
        });
        renderPanel();
        message(product ? 'Producto agregado desde el catálogo.' : 'Producto agregado como texto; deberá vincularse al catálogo para generar una orden.');
      } else if (action === 'remove-line') {
        state.formItems.splice(Number(button.dataset.index),1);
        renderPanel();
      } else if (action === 'save-draft') {
        await saveManual(false);
      } else if (action === 'save-send') {
        await saveManual(true);
      } else if (action === 'cancel-edit') {
        state.editing = null; state.formItems = []; state.mode = 'inicio'; renderPanel(); message('');
      } else if (action === 'edit') {
        editPedido(button.dataset.pedidoId);
      } else if (action === 'send') {
        const {error} = await sb.rpc('enviar_pedido',{p_pedido_id:button.dataset.pedidoId});
        if (error) throw error;
        await reload(); message('Pedido enviado a autorización.');
      } else if (action === 'authorize') {
        await authorize(button.dataset.pedidoId);
      } else if (action === 'reject') {
        await reject(button.dataset.pedidoId);
      } else if (action === 'add-allocation') {
        addAllocation(button);
      } else if (action === 'generate-orders') {
        const card = button.closest('.pedidos-card');
        await generateOrders(button.dataset.pedidoId,card);
      }
    } catch (error) {
      console.error('PEDIDOS:',error);
      message(error?.message || 'No se pudo completar la operación.',true);
    } finally {
      if (button.isConnected) button.disabled = false;
    }
  }

  function handleInput(event) {
    if (event.target.matches('#ped-product-name')) {
      const product = resolveProduct(event.target.value);
      event.target.dataset.productId = product?.id || '';
    }
  }

  function handleChange(event) {
    if (event.target.matches('[data-alloc-provider],[data-alloc-units],[data-alloc-cost]')) {
      // La asignación se lee desde los controles al generar las órdenes.
    }
  }

  function handleRemoveAllocation(event) {
    const button = event.target.closest('.pedidos-remove-allocation');
    if (button) button.closest('[data-allocation-row]')?.remove();
  }

  async function load() {
    if (state.loading) return;
    state.loading = true;
    root.innerHTML = '<div class="pedidos-loading">Cargando pedidos y calculando reposición…</div>';
    try {
      if (!sb) throw new Error('No se encontró la conexión con Supabase.');
      await loadData();
      render();
    } catch (error) {
      console.error('Carga de PEDIDOS:',error);
      root.innerHTML = '<div class="pedidos-panel"><h3>No se pudo cargar PEDIDOS</h3><p class="pedidos-warning">' + esc(error?.message || 'Error de conexión') + '</p><button type="button" class="btn" data-action="refresh">Reintentar</button></div>';
    } finally {
      state.loading = false;
    }
  }

  root.addEventListener('click', event => {
    handleRemoveAllocation(event);
    handleClick(event);
  });
  root.addEventListener('input',handleInput);
  root.addEventListener('change',handleChange);

  window.DrosaludPedidos = { load, reload };
})();
