(()=>{
 const $=s=>document.querySelector(s), esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let ordenes=[];
 async function cargarOrdenes(){
  const {data,error}=await sb.from('ordenes_compra').select('id,numero,proveedor_id,estado,documento_proveedor,creado_en').order('creado_en',{ascending:false}).limit(100);
  if(error)throw error;ordenes=data||[];renderOrdenes();
 }
 function renderOrdenes(){
  const box=$('#oc-list');if(!box)return;
  box.innerHTML=ordenes.length?ordenes.map(o=>{
   const p=(window.__ocProviders||[]).find(x=>x.id===o.proveedor_id);
   return '<article class="item"><div class="top"><b>Orden #'+o.numero+'</b><span>'+esc(o.estado)+'</span></div><p class="sm">'+esc(p?.nombre||'Proveedor')+' · '+esc(o.documento_proveedor||'Sin documento')+'</p><div class="acts">'+(o.estado==='borrador'&&window.__drosaludRole==='admin'?'<button class="btn alt full" data-oc-approve="'+o.id+'">Aprobar orden</button>':'')+(o.estado==='aprobada'||o.estado==='parcial'?'<button class="btn full" data-oc-receive="'+o.id+'">Registrar recepción</button>':'')+'</div></article>';
  }).join(''):'<p class="mut sm">Todavía no hay órdenes de compra.</p>';
 }
 async function cargarProveedores(){const {data,error}=await sb.from('proveedores').select('id,nombre,activo').eq('activo',true).order('nombre');if(error)throw error;window.__ocProviders=data||[];return data||[]}
 function modal(html){$('#modal').hidden=false;$('#sheet').innerHTML=html}
 function cerrar(){ $('#modal').hidden=true}
  function normalizarBusqueda(v){return String(v||'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().trim()}
  function coincideProducto(p,q){
   const n=normalizarBusqueda(q),codigo=String(p.codigo||'').toLowerCase().replace(/\\D/g,'');
   const dig=n.replace(/\\D/g,'');
   return !n||normalizarBusqueda([p.nombre,p.laboratorio,p.codigo].join(' ')).includes(n)||(dig.length>=4&&codigo.includes(dig));
  }
 async function nuevaOrden(){
  const providers=await cargarProveedores();
  if(!providers.length)throw new Error('Primero registra un proveedor activo.');
  if(!P.length)throw new Error('No se pudo cargar el catálogo.');
  modal('<h2>Crear orden de compra</h2><label>Proveedor</label><select id="oc-provider">'+providers.map(p=>'<option value="'+p.id+'">'+esc(p.nombre)+'</option>').join('')+'</select><label>Factura / documento proveedor (opcional)</label><input id="oc-doc" maxlength="100"><h3>Productos de la orden</h3><div id="oc-order-lines"></div><button type="button" class="btn alt full" id="oc-add-line">＋ Agregar producto</button><div class="acts"><button class="btn full" id="oc-save">Guardar borrador</button><button class="btn alt full" id="oc-cancel">Cancelar</button></div>');
  const lines=$('#oc-order-lines');
  function addLine(){
   const row=document.createElement('div');row.className='item oc-line';
   row.innerHTML='<label>Buscar producto por nombre o código</label><input type="search" data-oc-search placeholder="Escribe nombre o código…" autocomplete="off"><div data-oc-results class="oc-search-results" role="listbox"></div><input type="hidden" data-oc-product value=""><p class="mut sm" data-oc-selected>Selecciona un producto del catálogo.</p><label>Unidades individuales solicitadas</label><input data-oc-units type="number" min="1" step="1" value="1"><label>Costo por unidad individual</label><input data-oc-cost type="number" min="0" step="0.01" value="0"><button type="button" class="btn bad full" data-oc-remove>Quitar producto</button>';
   const search=row.querySelector('[data-oc-search]'),results=row.querySelector('[data-oc-results]');
   // Conserva también los productos consultados directamente en Supabase, aunque no estén en P.
   let productosEncontrados=[];
   const pintarResultados=productos=>{
    productosEncontrados=productos||[];
    results.innerHTML=productosEncontrados.map(p=>'<button type="button" class="btn alt full" data-oc-pick="'+p.id+'" style="text-align:left;margin:3px 0">'+esc(p.nombre)+' · '+esc(p.codigo||'Sin código')+' · '+esc(p.laboratorio||'')+'</button>').join('')||(search.value.trim()?'<p class="mut sm">No se encontraron coincidencias.</p>':'<p class="mut sm">Escribe al menos parte del nombre o código.</p>');
   };
   const render=()=>{const q=search.value.trim();if(!q){productosEncontrados=[];results.innerHTML='<p class="mut sm">Escribe el nombre o código del producto para buscarlo.</p>';return}const found=P.filter(p=>coincideProducto(p,q)).slice(0,12);pintarResultados(found)};
   let lookupSeq=0;
   async function buscarEnCatalogo(){
    const q=search.value.trim(),seq=++lookupSeq;
    row.querySelector('[data-oc-product]').value='';
    row.querySelector('[data-oc-selected]').textContent='Selecciona un producto del catálogo.';
    render();
    const digits=q.replace(/\D/g,'');
    if(digits.length<8)return;
    try{
     const {data,error}=await sb.from('productos_app')
      .select('id,codigo,nombre,laboratorio,linea,precio_compra,precio_venta,fraccionable,unidades_por_caja,unidades_por_venta')
      .eq('codigo',digits).limit(12);
     if(error)throw error;
     if(seq!==lookupSeq||search.value.trim()!==q)return;
     const merged=[...(data||[]),...P.filter(p=>String(p.codigo||'').replace(/\D/g,'')===digits)]
      .filter((p,i,a)=>a.findIndex(x=>String(x.id)===String(p.id))===i);
     if(merged.length){
      pintarResultados(merged);
     }else{
      productosEncontrados=[];
      results.innerHTML='<p class="mut sm">No se encontró ese código en el catálogo. Comprueba que esté registrado.</p>';
     }
    }catch(err){console.error('Búsqueda de código en compras:',err);if(seq===lookupSeq)results.innerHTML='<p class="mut sm">No se pudo consultar el catálogo. Revisa la conexión e intenta de nuevo.</p>'}
   }
   search.addEventListener('input',()=>{row.querySelector('[data-oc-product]').value='';row.querySelector('[data-oc-selected]').textContent='Selecciona un producto del catálogo.';render();if(search.value.replace(/\D/g,'').length>=8)buscarEnCatalogo()});
   search.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();buscarEnCatalogo()}});

   results.addEventListener('click',e=>{const btn=e.target.closest('[data-oc-pick]');if(!btn)return;const p=[...P,...productosEncontrados].find(x=>String(x.id)===btn.dataset.ocPick);if(!p)return;
    row.querySelector('[data-oc-product]').value=p.id;search.value=p.nombre;row.querySelector('[data-oc-selected]').textContent='Seleccionado: '+p.nombre+' · '+(p.codigo||'Sin código');productosEncontrados=[];results.innerHTML='';
   });
   row.querySelector('[data-oc-remove]').onclick=()=>row.remove();render();lines.appendChild(row);
  }
  addLine();$('#oc-add-line').onclick=addLine;$('#oc-cancel').onclick=cerrar;
  $('#oc-save').onclick=async()=>{
   const rows=[...lines.querySelectorAll('.oc-line')];
   const items=rows.map(row=>({producto_id:row.querySelector('[data-oc-product]').value,unidades_solicitadas:Number(row.querySelector('[data-oc-units]').value),costo_unitario_base:Number(row.querySelector('[data-oc-cost]').value)}));
   if(!items.length||items.some(x=>!x.producto_id||!Number.isInteger(x.unidades_solicitadas)||x.unidades_solicitadas<=0||!Number.isFinite(x.costo_unitario_base)||x.costo_unitario_base<0))throw new Error('Revisa productos, unidades y costos de todas las líneas.');
   const ids=items.map(x=>x.producto_id);if(new Set(ids).size!==ids.length)throw new Error('No repitas el mismo producto en la orden; combina sus unidades en una sola línea.');
   const {data,error}=await sb.rpc('crear_orden_compra',{p_proveedor_id:$('#oc-provider').value,p_items:items,p_documento:$('#oc-doc').value,p_notas:null});
   if(error)throw error;if(!data)throw new Error('Supabase no confirmó la creación de la orden.');
   cerrar();await cargarOrdenes();alert('Orden creada como borrador.');
  };
 }
 async function aprobar(id){const {error}=await sb.rpc('aprobar_orden_compra',{p_orden_id:id});if(error)throw error;await cargarOrdenes()}
 async function recibir(id){
  const operationId=crypto.randomUUID();
  const {data:items,error}=await sb.from('ordenes_compra_items').select('id,producto_id,unidades_solicitadas,unidades_recibidas,costo_unitario_base,productos(nombre,codigo)').eq('orden_id',id);
  if(error)throw error;
  const pendiente=(items||[]).filter(x=>x.unidades_solicitadas>x.unidades_recibidas);
  if(!pendiente.length)throw new Error('Esta orden ya está recibida completamente.');
  modal('<h2>Recepción física</h2><p class="mut sm">Registra solo lo que llegó. Los costos pueden variar frente a la orden.</p><label>Factura / documento proveedor</label><input id="oc-receipt-doc" maxlength="100"><label>Filtrar productos de esta orden por nombre o código</label><input id="oc-receipt-search" type="search" placeholder="Buscar en los productos pendientes…" autocomplete="off"><p class="mut sm">El filtro solo oculta líneas; no elimina cantidades ni productos de la recepción.</p><div id="oc-receipt-lines">'+pendiente.map(x=>'<div class="item oc-receipt-line" data-oc-filter="'+esc([x.productos?.nombre,x.productos?.codigo].join(' '))+'"><b>'+esc(x.productos?.nombre||'Producto')+'</b><p class="mut sm">Código: '+esc(x.productos?.codigo||'Sin código')+' · Pendiente: '+(x.unidades_solicitadas-x.unidades_recibidas)+' unidades</p><label>Unidades recibidas ahora</label><input type="number" min="0" max="'+(x.unidades_solicitadas-x.unidades_recibidas)+'" step="1" value="'+(x.unidades_solicitadas-x.unidades_recibidas)+'" data-oc-qty="'+x.id+'"><label>Costo real por unidad</label><input type="number" min="0" step="0.01" value="'+x.costo_unitario_base+'" data-oc-unitcost="'+x.id+'"></div>').join('')+'</div><div class="acts"><button class="btn full" id="oc-save-receipt">Confirmar recepción</button><button class="btn alt full" id="oc-cancel">Cancelar</button></div>');
  $('#oc-cancel').onclick=cerrar;
  $('#oc-receipt-search').addEventListener('input',e=>{const normalizarFiltro=valor=>String(valor||'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().trim();const q=normalizarFiltro(e.target.value);document.querySelectorAll('#oc-receipt-lines .oc-receipt-line').forEach(el=>{el.hidden=!normalizarFiltro(el.dataset.ocFilter).includes(q)})});
  $('#oc-save-receipt').onclick=async()=>{
   const lines=pendiente.map(x=>({orden_item_id:x.id,unidades:Number($('[data-oc-qty="'+x.id+'"]').value),costo_unitario_base:Number($('[data-oc-unitcost="'+x.id+'"]').value)})).filter(x=>x.unidades>0);
   if(!lines.length||lines.some(x=>!Number.isInteger(x.unidades)||x.unidades<0||!Number.isFinite(x.costo_unitario_base)||x.costo_unitario_base<0))throw new Error('Ingresa al menos una línea con cantidades y costos válidos.');
   if(lines.some(x=>x.costo_unitario_base===0)&&!confirm('Hay productos con costo $0. Si no es una muestra gratuita, corrige el costo antes de continuar. ¿Confirmas que realmente tienen costo cero?'))return;
   const save=$('#oc-save-receipt');if(save.disabled)return;save.disabled=true;save.textContent='Registrando…';
   try{const {error}=await sb.rpc('registrar_recepcion_compra',{p_orden_id:id,p_documento_proveedor:$('#oc-receipt-doc').value,p_items:lines,p_operacion_id:operationId,p_notas:null});
    if(error)throw error;cerrar();await cargarOrdenes();await invCargarDatos();alert('Recepción registrada. Kardex y costos actualizados.');
   }catch(err){save.disabled=false;save.textContent='Reintentar recepción';alert(err.message||'No se pudo confirmar la recepción. Puedes reintentar sin duplicar el movimiento.');}
  };
 }
 document.addEventListener('click',async e=>{
  const b=e.target.closest('button');if(!b)return;
  try{
   if(b.id==='oc-new')await nuevaOrden();
   if(b.dataset.ocApprove)await aprobar(b.dataset.ocApprove);
   if(b.dataset.ocReceive)await recibir(b.dataset.ocReceive);
  }catch(err){console.error(err);alert(err.message||'Error en compras');}
 });
 document.addEventListener('click',e=>{const b=e.target.closest('[data-home="neg"]');if(b)setTimeout(()=>{cargarOrdenes().catch(err=>console.error(err));cargarProveedores().catch(()=>{})},50)});
 document.addEventListener('click',e=>{if(e.target.closest('#more-menu [data-v="neg"]'))setTimeout(()=>{cargarOrdenes().catch(err=>console.error(err));cargarProveedores().catch(()=>{})},50)});
})();
