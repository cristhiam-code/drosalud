/* Pantalla de conteo físico ciego. La base valida permisos y estados. */
(() => {
  'use strict';
  const root = document.getElementById('conteo-fisico-app');
  if (!root || !window.DrosaludConteoApi) return;
  const api = window.DrosaludConteoApi;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  let rights={count:false,approve:false,admin:false}, userId=null, products=[], sessions=[], selected=new Set();
  let sessionId=null, items=[], review=[], query='', reason='', busy=false, errorMessage='', refreshStale=false;
  const labelState = { abierto:'Abierto', cerrado:'Cerrado', cancelado:'Cancelado', seleccionado:'Por iniciar', contando:'Conteo iniciado', pendiente_reconteo:'Requiere reconteo', pendiente_aprobacion:'Pendiente de aprobación', aprobado:'Aprobado', cancelado_item:'Cancelado' };
  function productMatches(p){const q=query.trim().toLocaleLowerCase();return !q||[p.nombre,p.codigo,p.laboratorio].some(x=>String(x||'').toLocaleLowerCase().includes(q))}
  function statusBox(){return `${errorMessage?`<p class="cf-alert" role="alert">${esc(errorMessage)}</p>`:''}${refreshStale?'<p class="cf-alert" role="status">La operación pudo guardarse, pero no se pudo actualizar la pantalla. Actualiza antes de continuar para evitar repetirla.</p>':''}`}
  function renderHome(){
    root.innerHTML=`<section class="cf-module">
      <header class="cf-heading"><div><span class="cf-kicker">INVENTARIO · CONTROL FÍSICO</span><h2>Conteo físico</h2><p>Cuenta sin ver el saldo del sistema. Las diferencias requieren otro contador antes de aprobar.</p></div></header>
      ${statusBox()}
      ${rights.count?`<section class="cf-panel"><h3>Iniciar un conteo</h3><label for="cf-search">Buscar producto</label><input id="cf-search" type="search" autocomplete="off" placeholder="Nombre, código o laboratorio" value="${esc(query)}">
        <div class="cf-products">${products.filter(productMatches).slice(0,30).map(p=>`<button type="button" class="cf-product ${selected.has(p.id)?'is-selected':''}" data-cf-product="${esc(p.id)}" aria-pressed="${selected.has(p.id)}"><span>${esc(p.nombre)}</span><small>${esc(p.codigo||'Sin código')} · ${esc(p.laboratorio||'')}</small></button>`).join('')||'<p class="cf-muted">No se encontraron productos.</p>'}</div>
        <div class="cf-selected"><b>Seleccionados: ${selected.size}</b>${[...selected].map(id=>{const p=products.find(x=>x.id===id);return `<span>${esc(p?.nombre||id)} <button type="button" aria-label="Quitar ${esc(p?.nombre||'producto')}" data-cf-remove="${esc(id)}">×</button></span>`}).join('')}</div>
        <label for="cf-reason">Motivo del conteo</label><input id="cf-reason" maxlength="500" placeholder="Ej. verificación mensual" value="${esc(reason)}">
        <button type="button" class="btn full" data-cf-create ${busy||!selected.size||reason.trim().length<3?'disabled':''}>Crear sesión</button>
      </section>`:''}
      ${rights.admin?renderPermissionPanel():''}
      <section class="cf-panel"><div class="cf-panel-title"><h3>Sesiones de conteo</h3><button type="button" class="btn alt" data-cf-refresh ${busy?'disabled':''}>Actualizar</button></div>
        <div class="cf-sessions">${sessions.map(s=>`<button class="cf-session" type="button" data-cf-open="${esc(s.conteo_id)}"><span><b>${esc(s.motivo)}</b><small>${new Date(s.creado_en).toLocaleString('es-CO')} · ${s.total_items} productos</small></span><span class="cf-state">${esc(labelState[s.estado]||s.estado)}<small>${s.pendientes} pendientes · ${s.aprobados} aprobados</small></span></button>`).join('')||'<p class="cf-muted">Todavía no hay sesiones.</p>'}</div>
      </section></section>`;
  }
  function renderPermissionPanel(){
    return `<details class="cf-panel"><summary><b>Permisos de conteo</b><small>Solo asigna capacidades de este módulo. No cambia el rol general del usuario.</small></summary>
      <label for="cf-user">ID del usuario activo en Drosalud</label><input id="cf-user" autocomplete="off" placeholder="UUID del usuario">
      <label class="cf-check"><input id="cf-can-count" type="checkbox"> Puede contar y recontar</label>
      <label class="cf-check"><input id="cf-can-approve" type="checkbox"> Puede revisar y aprobar</label>
      <button type="button" class="btn alt" data-cf-permission ${busy?'disabled':''}>Guardar permisos</button></details>`;
  }
  function reviewMap(){return new Map(review.map(x=>[x.item_id,x]))}
  function renderSession(){
    const byId=reviewMap();
    const cards=items.map(item=>{
      const r=byId.get(item.item_id);
      const canAudit=rights.approve&&r&&['pendiente_aprobacion','aprobado'].includes(r.estado);
      const canApprove=canAudit&&r.estado==='pendiente_aprobacion'&&!(r.capturas||[]).some(c=>c.usuario===userId);
      let action='';
      if(rights.count&&item.estado==='seleccionado') action=`<button class="btn full" type="button" data-cf-start="${esc(item.item_id)}" ${busy?'disabled':''}>Empezar a contar</button>`;
      if(rights.count&&item.estado==='contando'&&item.contador_asignado===userId){
        action=item.mi_captura==null?`<form class="cf-action" data-cf-save-form="${esc(item.item_id)}"><label for="cf-q-${esc(item.item_id)}">Cantidad física (unidades)</label><input id="cf-q-${esc(item.item_id)}" name="quantity" inputmode="numeric" pattern="[0-9]*" min="0" step="1" required><button class="btn full" ${busy?'disabled':''}>Guardar conteo</button></form>`:`<p class="cf-muted">Conteo guardado: <b>${esc(item.mi_captura)}</b></p><button class="btn alt full" type="button" data-cf-submit="${esc(item.item_id)}" ${busy?'disabled':''}>Enviar a revisión</button>`;
      }
      if(rights.count&&item.estado==='pendiente_reconteo'){
        action=item.mi_captura==null?`<form class="cf-action" data-cf-recount-form="${esc(item.item_id)}"><p>El sistema necesita un nuevo conteo independiente. No se muestran resultados anteriores.</p><label for="cf-rq-${esc(item.item_id)}">Vuelve a contar (unidades)</label><input id="cf-rq-${esc(item.item_id)}" name="quantity" inputmode="numeric" pattern="[0-9]*" min="0" step="1" required><label for="cf-rm-${esc(item.item_id)}">Nota opcional</label><input id="cf-rm-${esc(item.item_id)}" name="reason" maxlength="500"><button class="btn full" ${busy?'disabled':''}>Guardar reconteo</button></form>`:'<p class="cf-muted">Ya registraste un conteo de esta línea. Debe continuar otra persona.</p>';
      }
      if(canAudit) action+=`<div class="cf-review"><p><b>Saldo de corte:</b> ${esc(r.saldo_corte)} · <b>Confirmado:</b> ${esc(r.cantidad_confirmada)} · <b>Diferencia:</b> ${esc(r.diferencia)}</p><details><summary>Ver conteos y responsables</summary><ul>${(r.capturas||[]).map(c=>`<li>Conteo ${c.numero}: ${esc(c.cantidad)} · ${esc(c.correo||c.usuario)} · ${new Date(c.fecha).toLocaleString('es-CO')}${c.motivo?' · '+esc(c.motivo):''}</li>`).join('')}</ul></details>${canApprove?`<label for="cf-ap-${esc(item.item_id)}">Motivo de aprobación</label><input id="cf-ap-${esc(item.item_id)}" maxlength="500" placeholder="Revisión realizada" required><button class="btn full" type="button" data-cf-approve="${esc(item.item_id)}" ${busy?'disabled':''}>Aprobar y liberar producto</button>`:'<p class="cf-muted">Ajuste aprobado. El historial de conteo se conserva.</p>'}</div>`;
      if(rights.approve&&item.estado==='pendiente_aprobacion'&&!canApprove) action+='<p class="cf-muted">Una persona que participó en el conteo no puede aprobarlo.</p>';
      return `<article class="cf-item"><div class="cf-item-head"><div><b>${esc(item.nombre)}</b><small>${esc(item.codigo||'')} · ${esc(item.laboratorio||'')}${item.fraccionable?' · Caja de '+item.unidades_por_caja+' unidades':''}</small></div><span class="cf-state">${esc(labelState[item.estado]||item.estado)}</span></div>${action}</article>`;
    }).join('');
    const currentSession=sessions.find(s=>s.conteo_id===sessionId);
    root.innerHTML=`<section class="cf-module"><header class="cf-heading"><div><span class="cf-kicker">SESIÓN DE CONTEO</span><h2>${esc(currentSession?.motivo||'Conteo físico')}</h2><p>Las operaciones de inventario quedan bloqueadas para cada producto iniciado.</p></div><div class="cf-heading-actions"><button type="button" class="btn alt" data-cf-refresh ${busy?'disabled':''}>Actualizar</button><button type="button" class="btn alt" data-cf-home>Volver</button>${rights.admin&&currentSession?.estado==='abierto'?'<button type="button" class="btn bad" data-cf-cancel>Cancelar sesión</button>':''}</div></header>${statusBox()}<div class="cf-items">${cards||'<p class="cf-muted">No hay productos en esta sesión.</p>'}</div></section>`;
  }
  async function refresh(){
    const [s, it] = await Promise.all([api.list(), sessionId?api.items(sessionId):Promise.resolve({data:[],error:null})]);
    if(s.error) throw s.error;
    if(it.error) throw it.error;
    sessions=s.data||[]; items=it.data||[];
    if(sessionId&&rights.approve){const r=await api.review(sessionId);if(r.error)throw r.error;review=r.data||[]}else review=[];
    errorMessage=''; refreshStale=false;
    sessionId?renderSession():renderHome();
  }
  async function run(task,{refreshAfter=true,refreshOnly=false}={}){
    if(busy)return;
    busy=true;errorMessage='';
    sessionId?renderSession():renderHome();
    try{
      if(refreshOnly){await refresh();return}
      await task();
      if(refreshAfter){try{await refresh()}catch(error){console.error('Recarga de conteo físico:',error);refreshStale=true;errorMessage='La operación se realizó, pero la actualización falló. Actualiza la pantalla antes de continuar.'}}
    }
    catch(error){console.error('Conteo físico:',error);errorMessage=error?.message||'No se pudo completar la operación.';sessionId?renderSession():renderHome()}
    finally{busy=false;sessionId?renderSession():renderHome()}
  }
  function parseQuantity(form){const raw=new FormData(form).get('quantity');if(!/^\d+$/.test(String(raw||'')))throw new Error('Escribe una cantidad entera igual o mayor que cero.');return String(raw)}
  root.addEventListener('input',e=>{if(e.target.id==='cf-search'){query=e.target.value;renderHome();const input=root.querySelector('#cf-search');input?.focus();input?.setSelectionRange(query.length,query.length)}if(e.target.id==='cf-reason')reason=e.target.value});
  root.addEventListener('click',e=>{
    const button=e.target.closest('button');if(!button)return;
    if(refreshStale&&!button.hasAttribute('data-cf-refresh')){errorMessage='Actualiza la pantalla antes de continuar.';sessionId?renderSession():renderHome();return}
    if(button.hasAttribute('data-cf-product')){const id=button.dataset.cfProduct;selected.has(id)?selected.delete(id):selected.add(id);renderHome();return}
    if(button.hasAttribute('data-cf-remove')){selected.delete(button.dataset.cfRemove);renderHome();return}
    if(button.hasAttribute('data-cf-refresh')){run(refresh,{refreshOnly:true});return}
    if(button.hasAttribute('data-cf-create')){run(async()=>{const r=await api.create([...selected],reason);sessionId=r;selected.clear();query='';reason=''});return}
    if(button.hasAttribute('data-cf-open')){sessionId=button.dataset.cfOpen;run(refresh,{refreshOnly:true});return}
    if(button.hasAttribute('data-cf-home')){sessionId=null;run(refresh,{refreshOnly:true});return}
    if(button.hasAttribute('data-cf-start')){run(()=>api.start(button.dataset.cfStart));return}
    if(button.hasAttribute('data-cf-submit')){run(()=>api.submit(button.dataset.cfSubmit));return}
    if(button.hasAttribute('data-cf-approve')){const id=button.dataset.cfApprove, why=root.querySelector(`#cf-ap-${CSS.escape(id)}`)?.value||'';if(why.trim().length<3){errorMessage='Escribe el motivo de aprobación.';renderSession();return}run(()=>api.approve(id,why));return}
    if(button.hasAttribute('data-cf-cancel')){const why=window.prompt('Motivo para cancelar y liberar los productos:');if(!why||why.trim().length<3)return;run(()=>api.cancel(sessionId,why));return}
    if(button.hasAttribute('data-cf-permission')){const id=root.querySelector('#cf-user')?.value.trim(),count=!!root.querySelector('#cf-can-count')?.checked,approve=!!root.querySelector('#cf-can-approve')?.checked;if(!id){errorMessage='Escribe el ID del usuario.';renderHome();return}run(()=>api.setPermission(id,count,approve));return}
  });
  root.addEventListener('submit',e=>{
    if(refreshStale){e.preventDefault();errorMessage='Actualiza la pantalla antes de continuar.';renderSession();return}
    if(e.target.matches('[data-cf-save-form]')){e.preventDefault();const id=e.target.dataset.cfSaveForm;let q;try{q=parseQuantity(e.target)}catch(error){errorMessage=error.message;renderSession();return}run(()=>api.save(id,q));}
    if(e.target.matches('[data-cf-recount-form]')){e.preventDefault();const id=e.target.dataset.cfRecountForm;let q;try{q=parseQuantity(e.target)}catch(error){errorMessage=error.message;renderSession();return}const why=new FormData(e.target).get('reason');run(()=>api.recount(id,q,why));}
  });
  window.DrosaludConteoApp=Object.freeze({load:async()=>{
    try{
      const [cap,user,prod]=await Promise.all([api.capabilities(),sb.auth.getUser(),api.products()]);
      if(cap.error)throw cap.error;if(user.error)throw user.error;
      rights={count:!!cap.data?.puede_contar,approve:!!cap.data?.puede_aprobar,admin:!!cap.data?.es_admin};
      userId=user.data?.user?.id||null;products=prod;
      if(!rights.count&&!rights.approve)throw new Error('Tu usuario no tiene permisos para el conteo físico.');
      await refresh();
    }catch(error){errorMessage=error?.message||'No se pudo abrir el conteo.';root.innerHTML=`<section class="cf-module"><h2>Conteo físico</h2>${statusBox()}</section>`}
  }});
})();
