/* Orquestador del módulo Pedidos de Sucursales. */
(() => {
  'use strict';
  const root = document.getElementById('pedidos-sucursales-app');
  if (!root) return;

  const state = {
    context: null, mode: 'inicio', suggested: [], negatives: [], configuration: null,
    orders: [], loading: false, initialized: false, pendingOperation: null
  };
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));

  function message(value, error = false) {
    const el = root.querySelector('[data-ps-message]');
    if (!el) return;
    el.textContent = value || '';
    el.hidden = !value;
    el.classList.toggle('ps-message-error', !!error);
  }

  function shell() {
    const context = state.context || {};
    root.innerHTML = `
      <div class="ps-module">
        <header class="ps-heading">
          <div><span class="ps-kicker">ABASTECIMIENTO INTERNO</span>
            <h2>Pedidos de Sucursales</h2>
            <p>${esc(context.sucursal_nombre || 'Gestión central')}</p></div>
          <span class="ps-role">${context.es_admin ? 'Administración central' : 'Sucursal'}</span>
          ${context.es_admin ? '<button class="ps-button ps-button-light" type="button" data-ps-mode="config">Configurar sucursales</button>' : ''}
        </header>
        <p class="ps-message" data-ps-message role="status" hidden></p>
        <div data-ps-content></div>
      </div>`;
  }

  function home() {
    return `
      <section class="ps-home">
        <button class="ps-home-card ps-home-suggested" type="button" data-ps-mode="sugerido">
          <span class="ps-home-icon">↻</span><span><b>Pedido sugerido</b>
            <small>Reposición automática por ventas, existencias y pedidos pendientes.</small></span><span class="ps-arrow">›</span>
        </button>
        <button class="ps-home-card" type="button" data-ps-mode="urgente">
          <span class="ps-home-icon">!</span><span><b>Pedido urgente de productos en negativo</b>
            <small>Disponible cualquier día; solo productos con saldo menor que cero.</small></span><span class="ps-arrow">›</span>
        </button>
        <button class="ps-home-card" type="button" data-ps-mode="autorizados">
          <span class="ps-home-icon">✓</span><span><b>Pedidos autorizados</b>
            <small>Consulta aprobaciones y seguimiento de preparación.</small></span><span class="ps-arrow">›</span>
        </button>
        <button class="ps-home-card" type="button" data-ps-mode="historial">
          <span class="ps-home-icon">☷</span><span><b>Lista de pedidos realizados y enviados</b>
            <small>Historial, despachos y confirmación de recepción.</small></span><span class="ps-arrow">›</span>
        </button>
      </section>`;
  }

  function content() {
    if (state.loading) return '<div class="ps-loading">Consultando información de la sucursal…</div>';
    if (state.mode === 'inicio') return home();
    const back = '<button class="ps-back" type="button" data-ps-action="inicio">‹ Volver al menú de pedidos</button>';
    if (state.mode === 'sugerido') return back + window.PedidosSucursalesSugerido.render(state.suggested);
    if (state.mode === 'urgente') return back + window.PedidosSucursalesUrgente.render(state.negatives);
    if (state.mode === 'autorizados') return back + window.PedidosSucursalesAutorizados.render(state.orders, !!state.context?.es_admin);
    if (state.mode === 'historial') return back + window.PedidosSucursalesHistorial.render(state.orders);
    if (state.mode === 'config') return back + window.PedidosSucursalesConfiguracion.render(state.configuration || {});
    return home();
  }

  function render() {
    const panel = root.querySelector('[data-ps-content]');
    if (panel) panel.innerHTML = content();
  }

  async function loadContext() {
    state.context = await window.PedidosSucursalesAPI.contexto();
    if (!state.context || !state.context.sucursal_id) {
      throw new Error('Este usuario todavía no tiene una sucursal asignada. La administración debe configurarla antes de crear pedidos.');
    }
  }

  async function loadSuggested() {
    state.suggested = await window.PedidosSucursalesAPI.sugerido();
  }
  async function loadNegatives() {
    state.negatives = await window.PedidosSucursalesAPI.negativos();
  }
  async function loadOrders(filter) {
    state.orders = await window.PedidosSucursalesAPI.pedidos(filter || 'historial');
  }
  async function loadConfiguration() {
    state.configuration = await window.PedidosSucursalesAPI.configuracion();
  }

  async function openMode(mode) {
    state.mode = mode;
    state.loading = true;
    render();
    message('');
    try {
      if (mode === 'sugerido') await loadSuggested();
      if (mode === 'urgente') await loadNegatives();
      if (mode === 'autorizados') await loadOrders('autorizados');
      if (mode === 'historial') await loadOrders('historial');
      if (mode === 'config' && state.context?.es_admin) await loadConfiguration();
    } catch (error) {
      message(error?.message || 'No se pudo cargar la sección.', true);
    } finally {
      state.loading = false;
      render();
    }
  }

  function operationIdFor(tipo, payload) {
    const signature = tipo + ':' + JSON.stringify(payload);
    if (!state.pendingOperation || state.pendingOperation.signature !== signature) {
      const id = window.crypto?.randomUUID
        ? window.crypto.randomUUID()
        : 'ps-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
      state.pendingOperation = { signature, id };
    }
    return state.pendingOperation.id;
  }

  async function sendSuggested() {
    const items = window.PedidosSucursalesSugerido.collect(root, state.suggested);
    if (!items.length) throw new Error('Ajusta al menos una cantidad mayor que cero.');
    const operacionId = operationIdFor('sugerido', items);\n    await window.PedidosSucursalesAPI.crear('sugerido', items, null, operacionId);\n    state.pendingOperation = null;
    state.mode = 'historial';
    await loadOrders('historial');
    render();
    message('Pedido sugerido enviado correctamente.');
  }

  async function sendUrgent() {
    const items = window.PedidosSucursalesUrgente.collect(root, state.negatives);
    const reason = window.PedidosSucursalesUrgente.reason(root);
    if (!reason) throw new Error('Escribe el motivo de la urgencia.');
    const operacionId = operationIdFor('urgente', { items, reason });\n    await window.PedidosSucursalesAPI.crear('urgente', items, reason, operacionId);\n    state.pendingOperation = null;
    state.mode = 'historial';
    await loadOrders('historial');
    render();
    message('Pedido urgente enviado correctamente.');
  }

  async function authorize(orderId) {
    const order = state.orders.find(row => row.id === orderId);
    if (!order) throw new Error('No se encontró el pedido que intentas autorizar.');
    const items = window.PedidosSucursalesAutorizados.authorizationItems(root, order);
    await window.PedidosSucursalesAPI.autorizar(orderId, items);
    await loadOrders('autorizados');
    render();
    message('Pedido autorizado. Ya puede prepararse en bodega central.');
  }

  async function reject(orderId) {
    const reason = window.prompt('Motivo del rechazo:');
    if (reason === null) return;
    if (!reason.trim()) throw new Error('Debes indicar el motivo del rechazo.');
    await window.PedidosSucursalesAPI.rechazar(orderId, reason.trim());
    await loadOrders('autorizados');
    render();
    message('Pedido rechazado. El motivo quedó registrado.');
  }

  async function dispatch(orderId) {
    await window.PedidosSucursalesDespachos.despachar(orderId, state.orders);
    await loadOrders('autorizados');
    render();
    message('Despacho registrado. La sucursal ya puede confirmar la recepción.');
  }

  async function receive(dispatchId) {
    await window.PedidosSucursalesDespachos.confirmarRecepcion(dispatchId, state.orders, root);
    await loadOrders('historial');
    render();
    message('Recepción confirmada. Las cantidades recibidas se registraron en el inventario de la sucursal.');
  }

  async function handleClick(event) {
    const mode = event.target.closest('[data-ps-mode]');
    if (mode) return openMode(mode.dataset.psMode);
    const button = event.target.closest('[data-ps-action]');
    if (!button) return;
    const action = button.dataset.psAction;
    button.disabled = true;
    try {
      if (action === 'inicio') { state.mode = 'inicio'; render(); message(''); }
      else if (action === 'recalcular') { await loadSuggested(); render(); message('Pedido sugerido recalculado con los datos más recientes.'); }
      else if (action === 'recalcular-urgentes') { await loadNegatives(); render(); message('Inventario negativo actualizado.'); }
      else if (action === 'actualizar-autorizados') { await loadOrders('autorizados'); render(); }
      else if (action === 'actualizar-historial') { await loadOrders('historial'); render(); }
      else if (action === 'enviar-sugerido') await sendSuggested();
      else if (action === 'enviar-urgente') await sendUrgent();
      else if (action === 'autorizar') await authorize(button.dataset.pedidoId);
      else if (action === 'rechazar') await reject(button.dataset.pedidoId);
      else if (action === 'despachar') await dispatch(button.dataset.pedidoId);
      else if (action === 'confirmar-recepcion') await receive(button.dataset.despachoId);
      else if (action === 'crear-sucursal') {
        const values = window.PedidosSucursalesConfiguracion.newBranch(root);
        await window.PedidosSucursalesAPI.crearSucursal(values.codigo, values.nombre);
        await loadConfiguration(); render(); message('Sucursal y bodega creadas. Ahora asigna un usuario y configura sus días de pedido.');
      } else if (action === 'guardar-dias') {
        const id = button.dataset.sucursalId;
        await window.PedidosSucursalesAPI.configurarDias(id, window.PedidosSucursalesConfiguracion.selectedDays(root, id));
        await loadConfiguration(); render(); message('Días de pedido actualizados.');
      } else if (action === 'asignar-usuario') {
        const id = button.dataset.sucursalId;
        const userId = window.PedidosSucursalesConfiguracion.selectedUser(root, id);
        if (!userId) throw new Error('Selecciona un usuario activo.');
        await window.PedidosSucursalesAPI.asignarUsuario(userId, id);
        await loadConfiguration(); render(); message('Usuario asignado a la sucursal.');
      }
    } catch (error) {
      console.error('PEDIDOS DE SUCURSALES:', error);
      message(error?.message || 'No se pudo completar la operación.', true);
    } finally {
      if (button.isConnected) button.disabled = false;
    }
  }

  async function open() {
    if (!state.initialized) {
      root.innerHTML = '<div class="ps-loading">Abriendo Pedidos de Sucursales…</div>';
      try {
        await loadContext();
        state.initialized = true;
      } catch (error) {
        root.innerHTML = '<div class="ps-module"><p class="ps-message ps-message-error">' + esc(error?.message || 'No se pudo abrir el módulo.') + '</p></div>';
        return;
      }
    }
    shell();
    render();
  }

  root.addEventListener('click', handleClick);
  window.PedidosSucursalesApp = Object.freeze({ open });
})();
