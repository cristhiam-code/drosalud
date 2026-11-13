(() => {
  'use strict';

  const root = document.getElementById('pedidos-app');
  if (!root) return;

  const state = {
    user: null, role: null, products: [], providers: [], pedidos: [], items: [],
    orders: [], orderItems: [], suggested: [], formItems: [], editing: null,
    mode: 'sugerido', loading: false
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
    const receipts = await getAll(() => window.sb.from('recibos_app')
      .select('id').eq('anulado', false).gte('creado_en', since)
      .lte('creado_en', now.toISOString()).order('creado_en').order('id'));
    const sold = {};
    for (let offset = 0; offset < receipts.length; offset += 100) {
      const ids = receipts.slice(offset, offset + 100).map(row => row.id);
      const lines = await getAll(() => window.sb.from('recibo_items_app')
        .select('producto_id,cantidad,unidades_por_presentacion')
        .in('recibo_id', ids).order('id'));
      lines.forEach(line => {
        if (!line.producto_id) return;
        sold[line.producto_id] = (sold[line.producto_id] || 0)
          + (Number(line.cantidad) || 0) * Math.max(1, Number(line.unidades_por_presentacion) || 1);
      });
    }

    const [balances, orders, orderItems] = await Promise.all([
      getAll(() => window.sb.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id')),
      getAll(() => window.sb.from('ordenes_compra').select('id,estado').order('creado_en')),
      getAll(() => window.sb.from('ordenes_compra_items').select('orden_id,producto_id,unidades_solicitadas,unidades_recibidas').order('creado_en'))
    ]);
    const activeOrders = new Set(orders.filter(order => ['aprobada','parcial'].includes(order.estado)).map(order => order.id));
    const stock = {};
    balances.forEach(row => { stock[row.producto_id] = Number(row.saldo_unidades) || 0; });
    const pending = {};
    orderItems.forEach(row => {
      if (!activeOrders.has(row.orden_id) || !row.producto_id) return;
      pending[row.producto_id] = (pending[row.producto_id] || 0)
        + Math.max(0, (Number(row.unidades_solicitadas) || 0) - (Number(row.unidades_recibidas) || 0));
    });

    state.suggested = state.products
      .filter(product => (sold[product.id] || 0) > 0)
      .map(product => {
        const soldUnits = sold[product.id] || 0;
        const stockUnits = stock[product.id] || 0;
        const pendingUnits = pending[product.id] || 0;
        // Cobertura inicial: 7 días. Sin stock de seguridad inventado.
        const suggestedUnits = Math.max(0, Math.ceil(soldUnits - stockUnits - pendingUnits));
        return { product, soldUnits, stockUnits, pendingUnits, suggestedUnits };
      })
      .filter(row => row.suggestedUnits > 0)
      .sort((a,b) => (a.product.laboratorio || '').localeCompare(b.product.laboratorio || '', 'es')
        || a.product.nombre.localeCompare(b.product.nombre, 'es'));
  }

  async function loadData() {
    const { data: auth, error: authError } = await window.sb.auth.getUser();
    if (authError) throw authError;
    if (!auth?.user) throw new Error('Inicia sesión nuevamente.');
    state.user = auth.user;

    const { data: profile, error: profileError } = await window.sb.from('usuarios_drosalud')
      .select('rol,activo').eq('user_id', auth.user.id).maybeSingle();
    if (profileError) throw profileError;
    if (!profile || profile.activo !== true || !['admin','vendedor'].includes(profile.rol)) {
      throw new Error('Tu usuario no tiene un rol activo en Drosalud.');
    }
    state.role = profile.rol;

    const [products, providers, pedidos] = await Promise.all([
      getAll(() => window.sb.from('productos_app')
        .select('id,codigo,nombre,laboratorio,precio_compra,unidades_por_caja,unidades_por_venta')
        .order('nombre').order('id')),
      getAll(() => window.sb.from('proveedores').select('id,nombre,activo')
        .eq('activo', true).order('nombre')),
      getAll(() => window.sb.from('pedidos_resumen').select('*').order('creado_en', { ascending:false }))
    ]);
    state.products = products || [];
    state.providers = providers || [];
    state.pedidos = pedidos || [];

    const ids = state.pedidos.map(row => row.id);
    if (ids.length) {
      state.items = await getAll(() => window.sb.from('pedidos_items')
        .select('*').in('pedido_id', ids).order('creado_en'));
    } else state.items = [];

    const [orders, orderItems] = await Promise.all([
      getAll(() => window.sb.from('ordenes_compra').select('id,numero,pedido_id,proveedor_id,estado,creado_en')
        .order('creado_en', { ascending:false })),
      getAll(() => window.sb.from('ordenes_compra_items')
        .select('id,orden_id,pedido_item_id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base')
        .order('creado_en'))
    ]);
    state.orders = orders || [];
    state.orderItems = orderItems || [];
    await loadSuggested();
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
            <p>Solicitudes internas, autorización y órdenes a proveedores.</p></div>
          <span class="pedidos-role">${isAdmin() ? 'Administrador' : 'Vendedor'}</span>
        </header>
        <nav class="pedidos-modes" aria-label="Tipos de pedido">
          <button type="button" data-mode="sugerido" class="pedidos-mode">
            <b>Pedido sugerido</b><small>Automático por rotación</small>
          </button>
          <button type="button" data-mode="urgente" class="pedidos-mode">
            <b>Pedido urgente</b><small>Necesidad inmediata</small>
          </button>
          <button type="button" data-mode="extraordinario" class="pedidos-mode">
            <b>Pedido extraordinario</b><small>Ampliación de inventario</small>
          </button>
        </nav>
        <p class="pedidos-message" data-pedidos-message role="status" hidden></p>
        <div data-pedidos-panel></div>
        <section class="pedidos-history">
          <div class="pedidos-section-title"><div><h3>Seguimiento de pedidos</h3>
            <p>Historial compartido de solicitudes y abastecimiento.</p></div>
            <button type="button" class="btn alt" data-action="refresh">Actualizar</button>
          </div>
          <div data-pedidos-list></div>
        </section>
      </div>`;
    root.querySelectorAll('[data-mode]').forEach(button => {
      button.classList.toggle('is-active', button.dataset.mode === state.mode);
    });
  }

  function renderSuggested() {
    const total = state.suggested.reduce((sum,row) => sum + row.suggestedUnits, 0);
    const rows = state.suggested.map((row,index) => `
      <article class="pedidos-suggest-row">
        <div class="pedidos-product">
          <b>${esc(row.product.nombre)}</b>
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
        <div class="pedidos-section-title"><div><h3>Pedido sugerido por rotación</h3>
          <p>Ventas móviles de los últimos 7 días, saldo disponible y compras pendientes de recibir.</p></div>
          <button type="button" class="btn alt" data-action="recalc">Recalcular</button>
        </div>
        <div class="pedidos-kpis">
          <div><small>Productos por reponer</small><b>${units(state.suggested.length)}</b></div>
          <div><small>Unidades sugeridas</small><b>${units(total)}</b></div>
          <div><small>Cobertura objetivo</small><b>7 días</b></div>
        </div>
        <p class="pedidos-note">Cálculo inicial: ventas de 7 días − existencia − unidades pendientes de recibir. No se inventa un stock mínimo; puedes ajustar cada cantidad.</p>
        <div class="pedidos-suggest-list">${rows || '<p class="pedidos-empty">No hay productos que requieran reposición según los datos actuales.</p>'}</div>
        <div class="pedidos-actions">
          <button type="button" class="btn alt" data-action="save-suggested">Guardar borrador</button>
          <button type="button" class="btn" data-action="send-suggested">Guardar y enviar a autorización</button>
        </div>
      </section>`;
  }

  function renderManualForm() {
    const editing = !!state.editing;
    const options = state.products.map(product =>
      `<option value="${esc(product.nombre)}" label="${esc([product.codigo,product.laboratorio].filter(Boolean).join(' · '))}"></option>`
      + (product.codigo ? `<option value="${esc(product.codigo)}" label="${esc(product.nombre)}"></option>` : '')
    ).join('');
    const lines = state.formItems.map((item,index) => `
      <article class="pedidos-form-line">
        <div><b>${esc(item.producto_nombre)}</b><small>${item.producto_id ? 'Producto del catálogo' : 'Producto por vincular al catálogo'}</small></div>
        <span>${units(item.cantidad_solicitada)} unidades</span>
        <button type="button" class="pedidos-remove" data-action="remove-line" data-index="${index}" aria-label="Quitar producto">×</button>
      </article>`).join('');
    const modeLabel = state.editing ? (state.editing.tipo === 'sugerido' ? 'Pedido sugerido' : state.editing.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario')
      : state.mode === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario';
    return `
      <section class="pedidos-panel">
        <div class="pedidos-section-title"><div><h3>${modeLabel}</h3>
          <p>${state.editing ? 'Edita el borrador y guarda los cambios.' : state.mode === 'urgente' ? 'Registra un agotado o una solicitud inmediata de un cliente.' : 'Solicita cantidades adicionales o incorpora productos.'}</p></div>
          ${editing ? '<span class="pedidos-tag">Editando borrador</span>' : ''}</div>
        <div class="pedidos-form-grid">
          <div class="pedidos-field pedidos-field-wide">
            <label for="ped-product-name">Producto del catálogo o nombre libre</label>
            <input id="ped-product-name" list="ped-product-options" placeholder="Busca por nombre o escribe el producto">
            <datalist id="ped-product-options">${options}</datalist>
            <small>Si no está en el catálogo, puedes escribirlo. Para generar una orden deberá vincularse después.</small>
          </div>
          <div class="pedidos-field">
            <label for="ped-product-qty">Cantidad solicitada (unidades)</label>
            <input id="ped-product-qty" type="number" min="1" step="1" value="1" inputmode="numeric">
          </div>
          <div class="pedidos-field pedidos-field-wide">
            <label for="ped-product-reason">Motivo / justificación</label>
            <input id="ped-product-reason" maxlength="500" placeholder="Ej. Cliente lo solicitó / producto agotado">
          </div>
        </div>
        <button type="button" class="btn alt" data-action="add-line">Agregar producto al pedido</button>
        <div class="pedidos-form-lines">${lines || '<p class="pedidos-empty">Agrega al menos un producto.</p>'}</div>
        <div class="pedidos-field">
          <label for="ped-notes">Notas generales (opcional)</label>
          <textarea id="ped-notes" rows="2" maxlength="1000">${esc(state.editing?.notas || '')}</textarea>
        </div>
        <div class="pedidos-actions">
          <button type="button" class="btn alt" data-action="save-draft">Guardar borrador</button>
          <button type="button" class="btn" data-action="save-send">Guardar y enviar a autorización</button>
          ${editing ? '<button type="button" class="btn alt" data-action="cancel-edit">Salir de edición</button>' : ''}
        </div>
      </section>`;
  }

  function renderAuthorization(pedido, items) {
    return `
      <div class="pedidos-admin-box">
        <b>Revisión del administrador</b>
        <p>Modifica las cantidades que vas a autorizar. Puedes autorizar menos de lo solicitado.</p>
        ${items.map(item => `
          <label class="pedidos-auth-line"><span>${esc(item.producto_nombre)}<small>Solicitado: ${units(item.cantidad_solicitada)} unidades</small></span>
            <input type="number" min="0" max="${item.cantidad_solicitada}" step="1"
              value="${item.cantidad_solicitada}" data-auth-qty="${item.id}" aria-label="Cantidad autorizada para ${esc(item.producto_nombre)}">
          </label>`).join('')}
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
        <p>Asigna cada línea a uno o varios proveedores. El sistema agrupa automáticamente una orden por proveedor.</p>
        ${lines}
        ${items.some(item => item.producto_id && (Number(item.cantidad_autorizada)||0) > alreadyOrdered(item.id))
        ? `<button type="button" class="btn full" data-action="generate-orders" data-pedido-id="${pedido.id}">Generar órdenes de compra</button>`
        : '<p class="pedidos-done">No quedan unidades autorizadas pendientes de asignar.</p>'}
      </div>`;
  }

  function renderPedidoCard(pedido) {
    const items = itemsFor(pedido.id);
    const canEdit = pedido.estado === 'borrador' && (isAdmin() || pedido.creado_por === state.user.id);
    const relatedOrders = ordersFor(pedido.id);
    const details = items.map(item => {
      const approved = item.cantidad_autorizada == null ? '' : ` · Autorizado: ${units(item.cantidad_autorizada)}`;
      return `<li><span>${esc(item.producto_nombre)}</span><small>Solicitado: ${units(item.cantidad_solicitada)}${approved} unidades</small></li>`;
    }).join('');
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
      ? `<div class="pedidos-related-orders"><b>Órdenes generadas</b>${relatedOrders.map(order => {
          const provider = state.providers.find(row => row.id === order.proveedor_id);
          return `<span>Orden #${order.numero} · ${esc(provider?.nombre || 'Proveedor')} · ${statusLabel(order.estado)}</span>`;
        }).join('')}</div>`
      : '';
    return `
      <article class="pedidos-card">
        <div class="pedidos-card-head">
          <div><span class="pedidos-number">Pedido #${pedido.numero}</span>
            <h4>${pedido.tipo === 'sugerido' ? 'Pedido sugerido' : pedido.tipo === 'urgente' ? 'Pedido urgente' : 'Pedido extraordinario'}</h4>
            <small>${new Date(pedido.creado_en).toLocaleString('es-CO')}</small></div>
          <span class="pedidos-status status-${esc(pedido.estado_operativo || pedido.estado)}">${statusLabel(pedido.estado_operativo || pedido.estado)}</span>
        </div>
        <ul class="pedidos-item-list">${details}</ul>
        ${pedido.notas ? `<p class="pedidos-muted">${esc(pedido.notas)}</p>` : ''}
        ${pedido.motivo_rechazo ? `<p class="pedidos-warning">Motivo: ${esc(pedido.motivo_rechazo)}</p>` : ''}
        <div class="pedidos-summary">
          <span>Autorizado: <b>${units(pedido.unidades_autorizadas)}</b></span>
          <span>Comprado: <b>${units(pedido.unidades_compradas)}</b></span>
          <span>Recibido: <b>${units(pedido.unidades_recibidas)}</b></span>
        </div>
        ${orderSummary}${controls}
      </article>`;
  }

  function renderList() {
    const box = root.querySelector('[data-pedidos-list]');
    if (!box) return;
    box.innerHTML = state.pedidos.length
      ? state.pedidos.map(renderPedidoCard).join('')
      : '<p class="pedidos-empty">Todavía no hay pedidos registrados.</p>';
  }

  function renderPanel() {
    const panel = root.querySelector('[data-pedidos-panel]');
    if (!panel) return;
    panel.innerHTML = state.mode === 'sugerido' && !state.editing
      ? renderSuggested()
      : renderManualForm();
    root.querySelectorAll('[data-mode]').forEach(button => {
      button.classList.toggle('is-active', button.dataset.mode === state.mode && !state.editing);
    });
  }

  function render() {
    renderShell();
    renderPanel();
    renderList();
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
    const { data, error } = await window.sb.rpc('guardar_pedido', {
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
    if (send) await window.sb.rpc('enviar_pedido',{p_pedido_id:id}).then(({error}) => { if(error) throw error; });
    state.mode = 'sugerido';
    await reload();
    message(send ? 'Pedido sugerido enviado a autorización.' : 'Pedido sugerido guardado como borrador.');
  }

  async function saveManual(send) {
    const tipo = state.editing?.tipo || state.mode;
    const notas = root.querySelector('#ped-notes')?.value.trim() || '';
    const items = state.formItems.map(item => ({
      ...(item.id ? {id:item.id} : {}),
      producto_id:item.producto_id || null,
      producto_nombre:item.producto_nombre,
      cantidad_solicitada:item.cantidad_solicitada,
      justificacion:item.justificacion || null,
      costo_estimado:item.costo_estimado ?? null
    }));
    const id = await savePedido(items,tipo,notas,state.editing?.id || null);
    if (send) {
      const {error} = await window.sb.rpc('enviar_pedido',{p_pedido_id:id});
      if (error) throw error;
    }
    state.editing = null;
    state.formItems = [];
    state.mode = tipo === 'sugerido' ? 'sugerido' : tipo;
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
      if (!Number.isInteger(value) || value < 0 || value > Number(item.cantidad_solicitada)) {
        throw new Error('Revisa las cantidades autorizadas.');
      }
      return {pedido_item_id:item.id,cantidad_autorizada:value};
    });
    const {error} = await window.sb.rpc('autorizar_pedido',{
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
    const {error} = await window.sb.rpc('rechazar_pedido',{
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
    const {data,error} = await window.sb.rpc('generar_ordenes_compra_pedido',{
      p_pedido_id:pedidoId,p_asignaciones:assignments
    });
    if (error) throw error;
    await reload();
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
    const modeButton = event.target.closest('[data-mode]');
    if (modeButton) {
      state.editing = null;
      state.formItems = [];
      state.mode = modeButton.dataset.mode;
      renderPanel();
      message('');
      return;
    }
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const action = button.dataset.action;
    try {
      button.disabled = true;
      if (action === 'refresh') {
        await reload(); message('Datos actualizados.');
      } else if (action === 'recalc') {
        await loadSuggested(); renderPanel(); message('Cálculo actualizado con los datos más recientes.');
      } else if (action === 'save-suggested') {
        await saveSuggested(false);
      } else if (action === 'send-suggested') {
        await saveSuggested(true);
      } else if (action === 'add-line') {
        const nameInput = root.querySelector('#ped-product-name');
        const quantity = Number(root.querySelector('#ped-product-qty')?.value);
        const reason = root.querySelector('#ped-product-reason')?.value.trim() || '';
        const name = nameInput?.value.trim() || '';
        if (!name) throw new Error('Escribe o selecciona un producto.');
        if (!Number.isInteger(quantity) || quantity <= 0) throw new Error('La cantidad debe ser un entero mayor que cero.');
        const product = resolveProduct(name);
        const productName = product?.nombre || name;
        const existing = state.formItems.find(item => product
          ? item.producto_id === product.id
          : !item.producto_id && norm(item.producto_nombre) === norm(productName));
        if (existing) existing.cantidad_solicitada += quantity;
        else state.formItems.push({
          producto_id:product?.id || null,producto_nombre:productName,
          cantidad_solicitada:quantity,justificacion:reason,costo_estimado:null
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
        state.editing = null; state.formItems = []; state.mode = 'sugerido'; renderPanel(); message('');
      } else if (action === 'edit') {
        editPedido(button.dataset.pedidoId);
      } else if (action === 'send') {
        const {error} = await window.sb.rpc('enviar_pedido',{p_pedido_id:button.dataset.pedidoId});
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
      if (!window.sb) throw new Error('No se encontró la conexión con Supabase.');
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
