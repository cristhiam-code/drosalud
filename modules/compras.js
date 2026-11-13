(()=>{
 const $n=s=>document.querySelector(s), moneyN=n=>'$'+Math.round(Number(n)||0).toLocaleString('es-CO'); 
 let tab='pend',providers=[],buys=[],quotes=[];
 const escN=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 async function owner(){const {data,error}=await sb.auth.getUser();if(error)throw error;if(!data.user)throw new Error('Inicia sesión nuevamente.');return data.user.id}
 async function load(){
  const uid=await owner();
  const [p,b,q]=await Promise.all([
   sb.from('proveedores').select('*').order('nombre'),
   sb.from('compras_pendientes').select('*').eq('owner_id',uid).order('creado_en',{ascending:false}),
   sb.from('cotizaciones_proveedor').select('*').eq('owner_id',uid).order('consultado_en',{ascending:false})
  ]);
  for(const x of [p,b,q])if(x.error)throw x.error;
  providers=p.data||[];buys=b.data||[];quotes=q.data||[];
  render();
 }
 function render(){
  const open=buys.filter(x=>!['entregado','cancelado'].includes(x.estado));
  $n('#neg-kpi').innerHTML='<div>Solicitudes abiertas<b>'+open.length+'</b></div><div>Compras registradas<b>'+buys.filter(x=>x.costo_real!=null).length+'</b></div>';
  $n('#neg-provider-list').innerHTML=providers.length?providers.map(p=>'<div class="item"><div class="top"><span>'+escN(p.nombre)+'</span><span class="mut">'+(p.activo?'Activo':'Inactivo')+'</span></div><p class="sm mut">'+[p.contacto,p.telefono,p.whatsapp,p.email].filter(Boolean).map(escN).join(' · ')+'</p>'+(p.notas?'<p class="sm">'+escN(p.notas)+'</p>':'')+'<div class="acts"><button class="btn alt full" data-neg-edit-provider="'+p.id+'">Editar proveedor</button><button class="btn bad full" data-neg-delete-provider="'+p.id+'">Eliminar proveedor</button></div></div>').join(''):'<p class="mut">Todavía no tienes proveedores registrados.</p>';
  $n('#neg-buy-list').innerHTML=buys.length?buys.map(b=>{
   const p=providers.find(x=>x.id===b.proveedor_id),qs=quotes.filter(q=>q.compra_id===b.id);
   return '<div class="item"><div class="top"><span>'+escN(b.producto_nombre)+'</span><span>'+escN(b.estado)+'</span></div><p class="sm mut">Cantidad: '+b.cantidad+' · '+(p?escN(p.nombre):'Sin proveedor asignado')+'</p><p class="sm">Costo estimado: '+(b.costo_estimado==null?'—':moneyN(b.costo_estimado))+' · Costo real: '+(b.costo_real==null?'Pendiente':moneyN(b.costo_real))+'</p><p class="sm mut">'+qs.length+' cotización(es)</p><div class="acts"><button class="btn alt full" data-neg-quote="'+b.id+'">Registrar cotización</button><button class="btn alt full" data-neg-edit-buy="'+b.id+'">Actualizar compra</button></div></div>'
  }).join(''):'<p class="mut">No tienes medicamentos pendientes por conseguir.</p>';
 }
 function form(title,fields,values={}){return '<h2 style="margin-top:0">'+title+'</h2>'+fields.map(f=>'<label>'+f.label+'</label>'+ (f.type==='select'?'<select id="nf-'+f.key+'">'+f.options.map(o=>'<option value="'+escN(o.value)+'" '+(String(values[f.key]??f.default??'')===String(o.value)?'selected':'')+'>'+escN(o.label)+'</option>').join('')+'</select>':'<input id="nf-'+f.key+'" type="'+(f.type||'text')+'" value="'+escN(values[f.key]??'')+'" '+(f.required?'required':'')+' '+(f.min!==undefined?'min="'+f.min+'"':'')+'>')).join('')+'<div class="acts"><button class="btn full" id="neg-save">Guardar</button><button class="btn alt full" id="neg-cancel">Cancelar</button></div>'}
 function modal(content){$n('#modal').hidden=false;$n('#sheet').innerHTML=content;$n('#neg-cancel').onclick=()=>{$n('#modal').hidden=true};}
 async function saveProvider(id){
  const uid=await owner(),v=k=>$n('#nf-'+k).value.trim();
  const row={owner_id:uid,nombre:v('nombre'),contacto:v('contacto'),telefono:v('telefono'),whatsapp:v('whatsapp'),email:v('email'),notas:v('notas'),activo:v('activo')==='true'};
  if(!row.nombre)throw new Error('Escribe el nombre del proveedor.');
  const clean=s=>String(s||'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
  const phone=s=>String(s||'').replace(/\\D/g,'');
  const duplicate=providers.find(p=>p.id!==id&&(
   clean(p.nombre)===clean(row.nombre)||
   (phone(row.telefono).length>=7&&phone(p.telefono)===phone(row.telefono))||
   (phone(row.whatsapp).length>=7&&(phone(p.whatsapp)===phone(row.whatsapp)||phone(p.telefono)===phone(row.whatsapp)))||
   (phone(row.telefono).length>=7&&phone(p.whatsapp)===phone(row.telefono))
  ));
  if(duplicate)throw new Error('Este proveedor ya está registrado ('+duplicate.nombre+'). Busca el registro existente y edítalo; no crees otro.');
  const res=id?await sb.from('proveedores').update(row).eq('id',id).eq('owner_id',uid).select('id').maybeSingle():await sb.from('proveedores').insert(row).select('id').single();
  if(res.error)throw res.error;if(id&&!res.data)throw new Error('El proveedor no se actualizó. No se encontró el registro o tu usuario no tiene permiso.');$n('#modal').hidden=true;await load();
 }
 async function deleteProvider(id){
  const uid=await owner(),p=providers.find(x=>x.id===id);if(!p)return;
  const hasBuys=buys.some(x=>x.proveedor_id===id),hasQuotes=quotes.some(x=>x.proveedor_id===id);
  if(hasBuys||hasQuotes)throw new Error('No se puede eliminar '+p.nombre+' porque tiene compras o cotizaciones asociadas. Edítalo y cámbialo a Inactivo para conservar el historial.');
  if(!confirm('¿Eliminar definitivamente al proveedor "'+p.nombre+'"? Esta acción no se puede deshacer.'))return;
  const {error}=await sb.from('proveedores').delete().eq('id',id).eq('owner_id',uid);
  if(error)throw error;
  await load();
 }
 function providerForm(id){const p=providers.find(x=>x.id===id)||{};modal(form(id?'Editar proveedor':'Nuevo proveedor',[
  {key:'nombre',label:'Nombre del proveedor',required:true},{key:'contacto',label:'Persona de contacto'},{key:'telefono',label:'Teléfono'},{key:'whatsapp',label:'WhatsApp'},{key:'email',label:'Correo',type:'email'},{key:'notas',label:'Notas'},
  {key:'activo',label:'Estado',type:'select',default:'true',options:[{value:'true',label:'Activo'},{value:'false',label:'Inactivo'}]}
 ],p));$n('#neg-save').onclick=()=>run(()=>saveProvider(id));}
 async function saveBuy(id){
  const uid=await owner(),v=k=>$n('#nf-'+k).value.trim(),n=k=>v(k)===''?null:Number(v(k));
  const costoReal=n('costo_real'), reciboItemId=v('recibo_item_id')||null, reciboId=v('recibo_id')||null;
  const anterior=buys.find(x=>x.id===id);
  if(anterior?.recibo_item_id && anterior.costo_real!=null &&
     (anterior.recibo_item_id!==reciboItemId || anterior.recibo_id!==reciboId || costoReal===null)){
   throw new Error('Esta compra ya actualizó la ganancia de un recibo. Conserva el mismo recibo y la misma línea; no borres el costo real.');
  }
  const row={owner_id:uid,producto_nombre:v('producto_nombre'),cantidad:n('cantidad')||1,proveedor_id:v('proveedor_id')||null,costo_estimado:n('costo_estimado'),costo_real:reciboItemId?null:costoReal,estado:v('estado'),notas:v('notas'),recibo_id:reciboId,recibo_item_id:reciboItemId};
  if(!row.producto_nombre)throw new Error('Escribe el medicamento.');
  if(costoReal!==null&&reciboItemId){
   const {error}=await sb.rpc('guardar_compra_con_costo_real',{
    p_compra_id:id||null,p_producto_nombre:row.producto_nombre,p_cantidad:row.cantidad,
    p_proveedor_id:row.proveedor_id,p_costo_estimado:row.costo_estimado,
    p_estado:row.estado,p_notas:row.notas,p_recibo_id:reciboId,
    p_recibo_item_id:reciboItemId,p_costo_real:costoReal
   });
   if(error)throw error;
  }else{
   const {error}=await sb.rpc('guardar_compra_pendiente',{
    p_compra_id:id||null,p_producto_nombre:row.producto_nombre,p_cantidad:row.cantidad,
    p_proveedor_id:row.proveedor_id,p_costo_estimado:row.costo_estimado,
    p_estado:row.estado,p_notas:row.notas,p_recibo_id:row.recibo_id,
    p_recibo_item_id:row.recibo_item_id,p_costo_real:row.costo_real,
    p_actualizar_costo_real:true
   });
   if(error)throw error;
  }
  $n('#modal').hidden=true;await load();
 }
 async function buyForm(id){
  const b=buys.find(x=>x.id===id)||{};
  const {data:receipts,error}=await sb.from('recibos').select('id,numero,cliente_nombre,creado_en').order('creado_en',{ascending:false}).limit(100);
  if(error)throw error;
  const opts=[{value:'',label:'Sin vincular a un recibo'},...(receipts||[]).map(r=>({value:r.id,label:'Recibo '+r.numero+' · '+(r.cliente_nombre||'Sin cliente')+' · '+new Date(r.creado_en).toLocaleDateString('es-CO')}))];
  modal(form(id?'Actualizar solicitud':'Medicamento por conseguir',[
   {key:'producto_nombre',label:'Medicamento o producto',required:true},
   {key:'cantidad',label:'Cantidad',type:'number',min:1},
   {key:'proveedor_id',label:'Proveedor',type:'select',default:'',options:[{value:'',label:'Sin asignar'},...providers.map(p=>({value:p.id,label:p.nombre}))]},
   {key:'costo_estimado',label:'Costo estimado por unidad',type:'number',min:0},
   {key:'recibo_id',label:'Vincular con recibo (opcional)',type:'select',default:'',options:opts},
   {key:'recibo_item_id',label:'Línea del recibo para actualizar costo',type:'select',default:'',options:[{value:'',label:'Selecciona primero un recibo'}]},
   {key:'costo_real',label:'Costo real por unidad',type:'number',min:0},
   {key:'estado',label:'Estado',type:'select',default:'pendiente',options:['pendiente','cotizando','comprado','entregado','cancelado'].map(x=>({value:x,label:x[0].toUpperCase()+x.slice(1)}))},
   {key:'notas',label:'Notas'}
  ],{cantidad:1,estado:'pendiente',...b}));
  const receipt=$n('#nf-recibo_id'),item=$n('#nf-recibo_item_id');
  async function itemsForReceipt(receiptId,selected){
   item.innerHTML='<option value="">Cargando líneas…</option>';
   if(!receiptId){item.innerHTML='<option value="">Selecciona primero un recibo</option>';return}
   const {data,error}=await sb.from('recibo_items_app').select('id,nombre,cantidad,precio_venta').eq('recibo_id',receiptId).order('id');
   if(error)throw error;
   item.innerHTML='<option value="">No actualizar costo de una línea</option>'+(data||[]).map(x=>'<option value="'+x.id+'">'+escN(x.nombre)+' × '+x.cantidad+' · '+moneyN(x.precio_venta)+'</option>').join('');
   if(selected)item.value=selected;
  }
  receipt.addEventListener('change',()=>run(()=>itemsForReceipt(receipt.value,'')));
  if(b.recibo_id)await itemsForReceipt(b.recibo_id,b.recibo_item_id);
  $n('#neg-save').onclick=()=>run(()=>saveBuy(id));
 }
 async function quoteForm(id){
  const b=buys.find(x=>x.id===id);if(!b)return;
  if(!providers.length){alert('Primero registra un proveedor.');return}
  modal(form('Cotización para '+b.producto_nombre,[
   {key:'proveedor_id',label:'Proveedor',type:'select',options:providers.map(p=>({value:p.id,label:p.nombre}))},
   {key:'precio_unitario',label:'Precio por unidad',type:'number',min:0,required:true},
   {key:'disponible',label:'Disponibilidad',type:'select',default:'true',options:[{value:'true',label:'Disponible'},{value:'false',label:'No disponible'}]},
   {key:'notas',label:'Notas'}
  ],{proveedor_id:providers[0].id,disponible:'true'}));
  $n('#neg-save').onclick=()=>run(async()=>{const uid=await owner(),price=Number($n('#nf-precio_unitario').value);if(!(price>=0))throw new Error('Ingresa un precio válido.');const {error}=await sb.from('cotizaciones_proveedor').insert({owner_id:uid,compra_id:b.id,proveedor_id:$n('#nf-proveedor_id').value,precio_unitario:price,disponible:$n('#nf-disponible').value==='true',notas:$n('#nf-notas').value});if(error)throw error;$n('#modal').hidden=true;await load()});
 }
 async function run(fn){try{await fn()}catch(e){console.error(e);alert(e.message||'No se pudo guardar. Revisa la conexión y la migración SQL.')}} 
 function setTab(t){tab=t;$n('#neg-pend').hidden=t!=='pend';$n('#neg-prov').hidden=t!=='prov';document.querySelectorAll('[data-neg-tab]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.negTab===t)))}
 document.addEventListener('click',e=>{
  const b=e.target.closest('button');if(!b)return;
  if(b.dataset.v==='neg'){e.preventDefault();e.stopImmediatePropagation();show('neg');run(load);return}
  if(b.dataset.negTab){setTab(b.dataset.negTab);return}
  if(b.id==='neg-new-provider'){providerForm();return}
  if(b.id==='neg-new-buy'){buyForm();return}
  if(b.dataset.negEditProvider){providerForm(b.dataset.negEditProvider);return}
  if(b.dataset.negDeleteProvider){run(()=>deleteProvider(b.dataset.negDeleteProvider));return}
  if(b.dataset.negEditBuy){buyForm(b.dataset.negEditBuy);return}
  if(b.dataset.negQuote){quoteForm(b.dataset.negQuote);return}
 },true);
})();
