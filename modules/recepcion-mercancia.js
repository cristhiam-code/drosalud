/* DROSalud · Compras, documentos y recepción física. */
(() => {
  'use strict';
  const root = document.getElementById('recepcion-mercancia-app');
  if (!root) return;
  const $ = (s, scope=root) => scope.querySelector(s);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = v => '$' + Number(v || 0).toLocaleString('es-CO',{maximumFractionDigits:2});
  const date = v => v ? new Date(v).toLocaleDateString('es-CO',{year:'numeric',month:'short',day:'2-digit'}) : '—';
  const factor = p => Math.max(1,Number(p?.unidades_por_caja)||1);
  let orders=[], docs=[], receipts=[], costs=[], audit=[], busy=false, active='ordenes';

  function status(msg,error=false){
    const el=$('[data-rm-status]');
    if(el){el.textContent=msg||'';el.classList.toggle('rm-error',!!error)}
  }
  function pill(state){
    const map={aprobada:'Pendiente',parcial:'Parcial',recibida:'Recibida',registrado:'Registrado',conciliado:'Conciliado',con_diferencias:'Con diferencias',anulado:'Anulado'};
    const cls=['recibida','conciliado'].includes(state)?'is-loaded':(['con_diferencias','parcial'].includes(state)?'is-review':'is-pending');
    return '<span class="rm-state '+cls+'">'+esc(map[state]||state||'—')+'</span>';
  }
  async function fetchData(){
    const [o,d,l,r,c,a]=await Promise.all([
      sb.from('ordenes_compra').select('id,numero,proveedor_id,estado,documento_proveedor,creado_en,proveedor:proveedores(nombre),items:ordenes_compra_items(id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base,producto:productos(id,nombre,codigo,unidades_por_caja))').in('estado',['aprobada','parcial']).order('creado_en',{ascending:false}),
      sb.from('documentos_proveedor').select('id,proveedor_id,tipo_documento,numero_documento,fecha_emision,subtotal,descuentos,impuestos,flete,total,estado,notas,creado_en,proveedor:proveedores(nombre)').order('creado_en',{ascending:false}).limit(300),
      sb.from('documentos_proveedor_items').select('id,documento_id,orden_item_id,producto_id,descripcion_documento,presentacion_documento,unidades_por_presentacion,cantidad_documentada,unidades_documentadas,precio_por_presentacion,costo_unitario_base,producto:productos(nombre,codigo)').order('creado_en',{ascending:true}).limit(1500),
      sb.from('recepciones_compra').select('id,numero,orden_id,proveedor_id,documento_id,documento_proveedor,recibido_en,proveedor:proveedores(nombre),items:recepciones_compra_items(id,orden_item_id,producto_id,unidades,costo_unitario_base,producto:productos(nombre,codigo))').order('recibido_en',{ascending:false}).limit(500),
      sb.from('historial_costos').select('id,producto_id,proveedor_id,costo_unitario_base,costo_presentacion,unidades_por_presentacion,origen,referencia_id,registrado_por,registrado_en').order('registrado_en',{ascending:false}).limit(300),
      esAdminDrosalud() ? sb.from('auditoria_precios').select('id,producto_id,producto_nombre,campo,valor_anterior,valor_nuevo,usuario_email,rol,motivo,creado_en').order('creado_en',{ascending:false}).limit(300) : Promise.resolve({data:[],error:null})
    ]);
    for(const x of [o,d,l,r,c,a]) if(x.error) throw x.error;
    orders=o.data||[]; docs=d.data||[]; receipts=r.data||[]; costs=c.data||[]; audit=a.data||[];
    const links=await sb.from('documentos_proveedor_ordenes').select('documento_id,orden_id');
    if(links.error) throw links.error;
    const linesByDoc=new Map();
    (l.data||[]).forEach(x=>{if(!linesByDoc.has(x.documento_id))linesByDoc.set(x.documento_id,[]);linesByDoc.get(x.documento_id).push(x)});
    docs=docs.map(x=>({...x,items:linesByDoc.get(x.id)||[],ordenes:(links.data||[]).filter(y=>y.documento_id===x.id).map(y=>y.orden_id)}));
  }
  function exportExcel(){
    if(typeof XLSX==='undefined'||!XLSX.utils?.aoa_to_sheet){status('No está disponible la librería de Excel.',true);return}
    const rows=[['Tipo','Documento','Fecha','Proveedor','Orden','Producto','Cantidad documento','Unidades documento','Precio presentación','Costo por unidad']];
    docs.forEach(d=>(d.items||[]).forEach(i=>rows.push([d.tipo_documento,d.numero_documento,date(d.fecha_emision),d.proveedor?.nombre||'',d.ordenes?.join(', ')||'',i.descripcion_documento,i.cantidad_documentada,i.unidades_documentadas,i.precio_por_presentacion,i.costo_unitario_base])));
    const wb=XLSX.utils.book_new(),ws=XLSX.utils.aoa_to_sheet(rows);
    ws['!cols']=[{wch:14},{wch:22},{wch:15},{wch:28},{wch:30},{wch:42},{wch:18},{wch:18},{wch:20},{wch:18}];
    XLSX.utils.book_append_sheet(wb,ws,'Compras y recepción');XLSX.writeFile(wb,'compras-recepcion-drosalud.xlsx');
  }
  function render(){
    root.innerHTML=`
      <section class="rm-module">
        <header class="rm-heading">
          <div><span class="rm-kicker">INVENTARIO · ABASTECIMIENTO</span><h2>Compras y recepción</h2><p>Separa lo que se pidió, lo que el proveedor facturó y lo que realmente llegó.</p></div>
          <div class="rm-heading-actions"><button class="btn alt" data-rm-back>← Pedidos</button><button class="btn alt" data-rm-export>Exportar Excel</button></div>
        </header>
        <div class="rm-stats">
          <article><small>Órdenes abiertas</small><b>${orders.length}</b></article>
          <article><small>Documentos registrados</small><b>${docs.length}</b></article>
          <article><small>Recepciones físicas</small><b>${receipts.length}</b></article>
          <article><small>Costos históricos</small><b>${costs.length}</b></article>
        </div>
        <nav class="rm-tabs" aria-label="Secciones de compras">
          <button data-rm-tab="ordenes" class="${active==='ordenes'?'active':''}">Órdenes</button>
          <button data-rm-tab="documentos" class="${active==='documentos'?'active':''}">Facturas / remisiones</button>
          <button data-rm-tab="recepciones" class="${active==='recepciones'?'active':''}">Recepciones</button>
          <button data-rm-tab="historial" class="${active==='historial'?'active':''}">Historial de costos y precios</button>
        </nav>
        <p class="mut sm" data-rm-status role="status"></p>
        <section class="rm-view" data-rm-view="ordenes" ${active!=='ordenes'?'hidden':''}>
          <div class="rm-panel-head"><h3>Órdenes autorizadas por recibir</h3><small>El pedido sugerido permanece sin cambios.</small></div>
          <div class="rm-table-wrap"><table class="rm-table"><thead><tr><th>Orden</th><th>Proveedor</th><th>Fecha</th><th>Productos</th><th>Pendiente</th><th>Estado</th><th></th></tr></thead><tbody>
          ${orders.map(o=>{const rem=(o.items||[]).reduce((s,i)=>s+Math.max(0,Number(i.unidades_solicitadas)-Number(i.unidades_recibidas)),0);return '<tr><td><b>OC-'+esc(o.numero)+'</b></td><td>'+esc(o.proveedor?.nombre||'—')+'</td><td>'+date(o.creado_en)+'</td><td>'+((o.items||[]).length)+'</td><td>'+rem+' unidades</td><td>'+pill(o.estado)+'</td><td><button class="btn full" data-rm-doc="'+esc(o.id)+'">Registrar factura / remisión</button></td></tr>'}).join('')||'<tr><td colspan="7" class="rm-empty">No hay órdenes autorizadas pendientes.</td></tr>'}
          </tbody></table></div>
          <p class="rm-note">Primero se registra el documento comercial. Después se confirma la mercancía aceptada físicamente. Una factura no aumenta el inventario por sí sola.</p>
        </section>
        <section class="rm-view" data-rm-view="documentos" ${active!=='documentos'?'hidden':''}>
          <div class="rm-panel-head"><h3>Documentos del proveedor</h3><small>${docs.length} documento(s)</small></div>
          <div class="rm-table-wrap"><table class="rm-table"><thead><tr><th>Documento</th><th>Emisión</th><th>Proveedor</th><th>Valor</th><th>Orden</th><th>Estado</th><th></th></tr></thead><tbody>
          ${docs.map(d=>'<tr><td><b>'+esc(d.tipo_documento.toUpperCase())+' '+esc(d.numero_documento)+'</b></td><td>'+date(d.fecha_emision)+'</td><td>'+esc(d.proveedor?.nombre||'—')+'</td><td>'+money(d.total)+'</td><td>'+esc(d.ordenes?.map(id=>{const x=orders.find(o=>o.id===id);return x?'OC-'+x.numero:'Orden asociada'}) .join(', ')||'—')+'</td><td>'+pill(d.estado)+'</td><td><button class="btn alt full" data-rm-receive="'+esc(d.id)+'">Registrar recepción</button></td></tr>').join('')||'<tr><td colspan="7" class="rm-empty">Todavía no hay facturas o remisiones registradas.</td></tr>'}
          </tbody></table></div>
        </section>
        <section class="rm-view" data-rm-view="recepciones" ${active!=='recepciones'?'hidden':''}>
          <div class="rm-panel-head"><h3>Mercancía aceptada e ingresada</h3><small>Estas cantidades ya afectaron inventario y Kardex.</small></div>
          <div class="rm-table-wrap"><table class="rm-table"><thead><tr><th>Recepción</th><th>Fecha</th><th>Proveedor</th><th>Documento</th><th>Productos</th><th>Unidades aceptadas</th></tr></thead><tbody>
          ${receipts.map(r=>'<tr><td><b>REC-'+esc(r.numero)+'</b></td><td>'+date(r.recibido_en)+'</td><td>'+esc(r.proveedor?.nombre||'—')+'</td><td>'+esc(r.documento_proveedor||'—')+'</td><td>'+(r.items||[]).length+'</td><td>'+(r.items||[]).reduce((s,i)=>s+Number(i.unidades||0),0)+'</td></tr>').join('')||'<tr><td colspan="6" class="rm-empty">No hay recepciones registradas.</td></tr>'}
          </tbody></table></div>
        </section>
        <section class="rm-view" data-rm-view="historial" ${active!=='historial'?'hidden':''}>
          <div class="rm-panel-head"><h3>Historial de costos de compra</h3><small>Proveedor, costo por unidad y costo por empaque.</small></div>
          <div class="rm-table-wrap"><table class="rm-table"><thead><tr><th>Fecha</th><th>Producto</th><th>Origen</th><th>Proveedor</th><th>Costo unidad</th><th>Costo empaque</th><th>Presentación</th></tr></thead><tbody>
          ${costs.map(c=>'<tr><td>'+date(c.registrado_en)+'</td><td><b>'+esc((P.find(p=>p.id===c.producto_id)||{}).nombre||c.producto_id)+'</b></td><td>'+esc(c.origen)+'</td><td>'+esc((docs.find(d=>d.proveedor_id===c.proveedor_id)||{}).proveedor?.nombre||'—')+'</td><td>'+money(c.costo_unitario_base)+'</td><td>'+money(c.costo_presentacion)+'</td><td>'+esc(c.unidades_por_presentacion)+' unidades</td></tr>').join('')||'<tr><td colspan="7" class="rm-empty">No hay cambios de costo registrados.</td></tr>'}
          </tbody></table></div>
          ${esAdminDrosalud()?'<div class="rm-panel-head"><h3>Auditoría de precios del catálogo</h3><small>Incluye usuario, valor anterior, nuevo valor y motivo.</small></div><div class="rm-table-wrap"><table class="rm-table"><thead><tr><th>Fecha</th><th>Producto</th><th>Campo</th><th>Antes</th><th>Ahora</th><th>Usuario</th><th>Motivo</th></tr></thead><tbody>'+audit.map(a=>'<tr><td>'+date(a.creado_en)+'</td><td><b>'+esc(a.producto_nombre||a.producto_id)+'</b></td><td>'+esc(a.campo==='precio_compra'?'Costo compra':'Precio venta')+'</td><td>'+money(a.valor_anterior)+'</td><td>'+money(a.valor_nuevo)+'</td><td>'+esc(a.usuario_email||'—')+'</td><td>'+esc(a.motivo||'No indicado en el registro anterior')+'</td></tr>').join('')||'<tr><td colspan="7" class="rm-empty">No hay cambios de precios registrados.</td></tr>'+'</tbody></table></div>':'<p class="rm-note">La auditoría detallada de cambios de precio está disponible para administración.</p>'}
          <p class="rm-note">Los registros antiguos no tienen motivo porque antes el sistema no lo solicitaba. Los cambios nuevos hechos mediante el formulario de actualización con motivo sí quedarán identificados.</p>
        </section>
      </section>`;
  }
  function openDocument(order){
    const rows=(order.items||[]).map(i=>{
      const f=factor(i.producto),remaining=Math.max(0,Number(i.unidades_solicitadas)-Number(i.unidades_recibidas));
      return {i,f,remaining};
    });
    root.insertAdjacentHTML('beforeend',`
      <div class="rm-overlay" data-rm-overlay><section class="rm-dialog" role="dialog" aria-modal="true">
        <h2>Registrar factura o remisión</h2><p class="mut sm">Orden OC-${esc(order.numero)} · ${esc(order.proveedor?.nombre||'Proveedor')}</p>
        <div class="rm-form-grid">
          <div><label>Tipo</label><select data-doc-type><option value="factura">Factura</option><option value="remision">Remisión</option><option value="nota_credito">Nota crédito</option><option value="otro">Otro</option></select></div>
          <div><label>Número del documento</label><input data-doc-number maxlength="120" placeholder="Ej. DFPS204606"></div>
          <div><label>Fecha de emisión</label><input data-doc-date type="date" value="${new Date().toLocaleDateString('en-CA',{timeZone:'America/Bogota'})}"></div>
          <div><label>Subtotal (COP)</label><input data-doc-sub type="number" min="0" step=".01"></div>
          <div><label>Descuentos</label><input data-doc-discount type="number" min="0" step=".01" value="0"></div>
          <div><label>Impuestos</label><input data-doc-tax type="number" min="0" step=".01" value="0"></div>
          <div><label>Flete</label><input data-doc-freight type="number" min="0" step=".01" value="0"></div>
          <div><label>Total del documento</label><input data-doc-total type="number" min="0" step=".01"></div>
        </div>
        <h3>Productos que aparecen en el documento</h3>
        <p class="mut sm">Ingresa la cantidad facturada en empaques y el precio por empaque. Si el proveedor factura otra presentación, no la conviertas a ojo: debe revisarse antes de guardar.</p>
        <div class="rm-lines">
        ${rows.map(({i,f,remaining})=>'<article class="rm-line"><b>'+esc(i.producto?.nombre||'Producto')+'</b><small>Código '+esc(i.producto?.codigo||'—')+' · Pedido pendiente '+remaining+' unidades · Presentación catálogo '+f+' unidades</small><label>Cantidad documentada (empaques)</label><input type="number" min="0" step="1" value="'+(remaining?Math.ceil(remaining/f):0)+'" data-doc-qty="'+esc(i.id)+'"><label>Precio por empaque (COP)</label><input type="number" min="0" step=".01" value="'+Number(i.costo_unitario_base||0)*f+'" data-doc-price="'+esc(i.id)+'"></article>').join('')}
        </div>
        <label>Observaciones</label><textarea data-doc-notes rows="2" maxlength="500" placeholder="Descuentos, diferencias o notas del proveedor"></textarea>
        <p class="rm-note">Guardar el documento no modifica inventario ni el costo vigente. El costo se actualiza al confirmar la recepción aceptada.</p>
        <div class="rm-actions"><button class="btn full" data-doc-save>Guardar documento</button><button class="btn alt full" data-rm-close>Cancelar</button></div>
      </section></div>`);
    const overlay=$('[data-rm-overlay]');
    $('[data-rm-close]',overlay).onclick=()=>overlay.remove();
    $('[data-doc-save]',overlay).onclick=async e=>{
      if(busy)return;
      const b=e.currentTarget,number=$('[data-doc-number]',overlay).value.trim();
      if(!number){status('Escribe el número de factura o remisión.',true);return}
      const items=rows.map(({i,f})=>({orden_item_id:i.id,descripcion_documento:i.producto?.nombre||'Producto',presentacion_documento:'Empaque x '+f,unidades_por_presentacion:f,cantidad_documentada:Number($('[data-doc-qty="'+i.id+'"]',overlay).value),precio_por_presentacion:Number($('[data-doc-price="'+i.id+'"]',overlay).value)})).filter(x=>x.cantidad_documentada>0);
      if(!items.length||items.some(x=>!Number.isInteger(x.cantidad_documentada)||x.cantidad_documentada<1||!Number.isFinite(x.precio_por_presentacion)||x.precio_por_presentacion<0)){status('Revisa las cantidades y los precios de las líneas.',true);return}
      const vals=['[data-doc-sub]','[data-doc-discount]','[data-doc-tax]','[data-doc-freight]','[data-doc-total]'].map(s=>$(s,overlay).value);
      if(vals.some(v=>v!==''&&(!Number.isFinite(Number(v))||Number(v)<0))){status('Los importes no pueden ser negativos.',true);return}
      busy=true;b.disabled=true;b.textContent='Guardando documento…';
      try{
        const {error}=await sb.rpc('registrar_documento_proveedor',{p_orden_id:order.id,p_tipo_documento:$('[data-doc-type]',overlay).value,p_numero_documento:number,p_fecha_emision:$('[data-doc-date]',overlay).value||null,p_subtotal:vals[0]===''?null:Number(vals[0]),p_descuentos:Number(vals[1]||0),p_impuestos:Number(vals[2]||0),p_flete:Number(vals[3]||0),p_total:vals[4]===''?null:Number(vals[4]),p_notas:$('[data-doc-notes]',overlay).value.trim()||null,p_items:items});
        if(error)throw error;
        overlay.remove();active='documentos';await load();status('Documento guardado. Aún no se ha modificado el inventario.');
      }catch(err){status(err.message||'No se pudo guardar el documento.',true);b.disabled=false;b.textContent='Reintentar guardar'}
      finally{busy=false}
    };
  }
  function openReception(doc){
    const linked=orders.find(o=>doc.ordenes?.includes(o.id)) || null;
    const items=doc.items||[];
    const op=crypto.randomUUID();
    const receivedFor=orderItemId=>receipts.filter(r=>r.documento_id===doc.id).flatMap(r=>r.items||[]).filter(i=>i.orden_item_id===orderItemId).reduce((s,i)=>s+Number(i.unidades||0),0);
    root.insertAdjacentHTML('beforeend',`
      <div class="rm-overlay" data-rm-overlay><section class="rm-dialog" role="dialog" aria-modal="true">
        <h2>Confirmar recepción física</h2><p class="mut sm">${esc(doc.tipo_documento.toUpperCase())} ${esc(doc.numero_documento)} · ${esc(doc.proveedor?.nombre||'Proveedor')}</p>
        <p class="rm-note">Solo registra las unidades que llegaron y fueron aceptadas. No incluyas faltantes, averías ni mercancía rechazada como si hubiera ingresado.</p>
        <div class="rm-lines">${items.map(i=>{
          const got=receivedFor(i.orden_item_id),left=Math.max(0,Number(i.unidades_documentadas)-got),orderItem=linked?.items?.find(x=>x.id===i.orden_item_id),orderLeft=orderItem?Math.max(0,Number(orderItem.unidades_solicitadas)-Number(orderItem.unidades_recibidas)):left,max=Math.min(left,orderLeft);
          return '<article class="rm-line"><b>'+esc(i.descripcion_documento||i.producto?.nombre||'Producto')+'</b><small>Documento: '+i.unidades_documentadas+' unidades · Ya aceptadas: '+got+' · Costo: '+money(i.costo_unitario_base)+' por unidad</small><label>Unidades aceptadas hoy</label><input type="number" min="0" max="'+max+'" step="1" value="'+max+'" data-rcv="'+esc(i.orden_item_id)+'" data-cost="'+Number(i.costo_unitario_base)+'"><small>Máximo permitido ahora: '+max+' unidades</small></article>';
        }).join('')}</div>
        <label>Observaciones de recepción</label><textarea data-rcv-notes rows="2" maxlength="500" placeholder="Ej. llegaron 2 de 3 cajas; una queda pendiente"></textarea>
        <div class="rm-actions"><button class="btn full" data-rcv-save>Confirmar unidades aceptadas e ingresar al inventario</button><button class="btn alt full" data-rm-close>Cancelar</button></div>
      </section></div>`);
    const overlay=$('[data-rm-overlay]');$('[data-rm-close]',overlay).onclick=()=>overlay.remove();
    $('[data-rcv-save]',overlay).onclick=async e=>{
      if(busy)return;const b=e.currentTarget;
      const payload=items.map(i=>({orden_item_id:i.orden_item_id,unidades:Number($('[data-rcv="'+i.orden_item_id+'"]',overlay).value),costo_unitario_base:Number(i.costo_unitario_base)})).filter(x=>x.unidades>0);
      if(!payload.length||payload.some(x=>!Number.isInteger(x.unidades)||x.unidades<1)){status('Indica al menos una cantidad aceptada válida.',true);return}
      busy=true;b.disabled=true;b.textContent='Registrando recepción…';
      try{
        const {error}=await sb.rpc('registrar_recepcion_compra_documentada',{p_orden_id:linked?.id||doc.ordenes?.[0],p_documento_id:doc.id,p_items:payload,p_operacion_id:op,p_notas:$('[data-rcv-notes]',overlay).value.trim()||null});
        if(error)throw error;
        overlay.remove();active='recepciones';await load();window.invCargarDatos?.();status('Recepción confirmada. Las unidades aceptadas ingresaron al inventario y Kardex.');
      }catch(err){status(err.message||'No se pudo registrar la recepción.',true);b.disabled=false;b.textContent='Reintentar recepción'}
      finally{busy=false}
    };
  }
  async function load(){
    status('Consultando órdenes, documentos y recepciones…');
    try{await fetchData();render();status('Información actualizada. Los documentos y las recepciones se consultan por separado.')}
    catch(e){console.error('Compras y recepción:',e);root.innerHTML='<p class="rm-error">No se pudo cargar Compras y recepción: '+esc(e.message||'Error de conexión')+'</p>'}
  }
  root.addEventListener('click',e=>{
    const tab=e.target.closest('[data-rm-tab]');if(tab){active=tab.dataset.rmTab;render();return}
    if(e.target.closest('[data-rm-back]')){if(typeof show==='function')show('pedidos');return}
    if(e.target.closest('[data-rm-export]')){exportExcel();return}
    const docBtn=e.target.closest('[data-rm-doc]');if(docBtn){const order=orders.find(o=>o.id===docBtn.dataset.rmDoc);if(order)openDocument(order);return}
    const recBtn=e.target.closest('[data-rm-receive]');if(recBtn){const d=docs.find(x=>x.id===recBtn.dataset.rmReceive);if(d)openReception(d);return}
    if(e.target.closest('[data-rm-close]'))$('[data-rm-overlay]')?.remove();
  });
  window.DrosaludRecepcionMercancia=Object.freeze({load});
})();