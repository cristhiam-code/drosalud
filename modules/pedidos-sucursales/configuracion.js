/* Configuración administrativa de sucursales, usuarios y días de pedido. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const days = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];

  window.PedidosSucursalesConfiguracion = Object.freeze({
    render(data) {
      const branches = data?.sucursales || [];
      const users = data?.usuarios || [];
      return `
        <section class="ps-panel">
          <div class="ps-section-head"><div><h3>Configuración de sucursales</h3>
            <p>Crea sucursales, asigna usuarios y define los días habilitados para el Pedido Sugerido.</p></div></div>
          <div class="ps-config-create">
            <label class="ps-field">Código de sucursal
              <input type="text" maxlength="24" data-ps-branch-code placeholder="Ej. NORTE"></label>
            <label class="ps-field">Nombre de sucursal
              <input type="text" maxlength="100" data-ps-branch-name placeholder="Ej. Sucursal Norte"></label>
            <button class="ps-button" type="button" data-ps-action="crear-sucursal">Crear sucursal y bodega</button>
          </div>
          <div class="ps-list">
            ${branches.map(branch => `
              <article class="ps-order-card">
                <div class="ps-order-head"><div><b>${esc(branch.nombre)}</b><small>${esc(branch.codigo)} · ${branch.es_central ? 'Bodega central' : 'Sucursal'}</small></div>
                  <span class="ps-status">${branch.activa ? 'Activa' : 'Inactiva'}</span></div>
                ${branch.es_central ? '<p class="ps-note">Esta bodega concentra las existencias desde las que se despachan los pedidos.</p>' : `
                  <div class="ps-config-days">
                    <b>Días habilitados para pedido sugerido</b>
                    <div class="ps-day-grid">${days.map((day,i) => `
                      <label><input type="checkbox" data-ps-day="${i}" data-ps-branch="${esc(branch.id)}" ${(branch.dias_pedido || []).includes(i) ? 'checked' : ''}> ${day}</label>
                    `).join('')}</div>
                    <button class="ps-button ps-button-light" type="button" data-ps-action="guardar-dias" data-sucursal-id="${esc(branch.id)}">Guardar días</button>
                  </div>
                  <div class="ps-config-assign">
                    <label class="ps-field">Asignar usuario
                      <select data-ps-user-select="${esc(branch.id)}">
                        <option value="">Selecciona un usuario activo</option>
                        ${users.filter(user => user.activo).map(user => `
                          <option value="${esc(user.user_id)}" ${user.sucursal_id === branch.id ? 'selected' : ''}>
                            ${esc(user.email || user.user_id)} · ${esc(user.rol)}
                          </option>`).join('')}
                      </select>
                    </label>
                    <button class="ps-button ps-button-light" type="button" data-ps-action="asignar-usuario" data-sucursal-id="${esc(branch.id)}">Guardar asignación</button>
                  </div>`}
              </article>`).join('')}
          </div>
        </section>`;
    },
    selectedDays(root, branchId) {
      return [...root.querySelectorAll('[data-ps-day][data-ps-branch="' + branchId + '"]:checked')]
        .map(input => Number(input.dataset.psDay));
    },
    selectedUser(root, branchId) {
      return root.querySelector('[data-ps-user-select="' + branchId + '"]')?.value || '';
    },
    newBranch(root) {
      const codigo = root.querySelector('[data-ps-branch-code]')?.value.trim() || '';
      const nombre = root.querySelector('[data-ps-branch-name]')?.value.trim() || '';
      if (!codigo || !nombre) throw new Error('Escribe el código y el nombre de la sucursal.');
      return { codigo, nombre };
    }
  });
})();
