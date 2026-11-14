/* INVENTARIO · extraído sin reescritura del bloque original */
let invProductos=[],invSaldos={},invPedidos=[],invLaboratorios=[],invLabsSeleccionados=new Set(),invResultados=[],invRecepcionIntento=null,invSaldoDisponible=false;
function invSaldo(p){return Number(invSaldos[p.id]||0)}
function invPartes(s,f){f=Math.max(1,Number(f)||1);s=Math.trunc(s);if(s<0)return{cajas:0,sueltas:s};return{cajas:Math.floor(s/f),sueltas:s%f}}
function invRenderLabs(){
 const q=norm($('#inv-q').value||'');
 const visibles=invLaboratorios.filter(l=>!q||norm(l).includes(q)||invProductos.some(p=>(p.laboratorio||'Sin laboratorio').trim()===l&&norm([p.nombre,p.codigo].join(' ')).includes(q)));
 $('#inv-labs').innerHTML=visibles.map(l=>'<label class="inv-lab"><input type="checkbox" data-inv-lab="'+esc(l)+'" '+(invLabsSeleccionados.has(l)?'checked':'')+'> '+esc(l)+'</label>').join('')||'<p class="mut sm">No hay laboratorios coincidentes.</p>';
 $('#inv-lab-count').textContent='Laboratorios · '+invLabsSeleccionados.size+' seleccionados';
}
function invFiltrar(){
 const q=norm($('#inv-q').value||'');
 const contenido=document.querySelector('input[name="inv-contenido"]:checked')?.value||'todos';
 invResultados=invProductos.filter(p=>{
  const lab=(p.laboratorio||'Sin laboratorio').trim(),saldo=invSaldo(p);
  if(!invLabsSeleccionados.has(lab))return false;
  const lineaSeleccionada=$('#inv-linea').value;
  if(lineaSeleccionada&&(p.linea||'')!==lineaSeleccionada)return false;
  if(q&&!norm([p.nombre,p.laboratorio,p.codigo].join(' ')).includes(q))return false;
  if(contenido==='negativos'&&saldo>=0)return false;
  if(contenido==='cero'&&saldo!==0)return false;
  if(contenido==='con_existencia'&&saldo===0)return false;
  return true;
 }).sort((a,b)=>(a.laboratorio||'').localeCompare(b.laboratorio||'','es',{sensitivity:'base'})||a.nombre.localeCompare(b.nombre,'es',{sensitivity:'base'}));
 return invResultados;
}
function invRenderInforme(){
 if(!invSaldoDisponible){$('#inv-kardex-list').innerHTML='<p class="mut">El catálogo está disponible, pero el Kardex requiere instalar las migraciones de inventario en este entorno.</p>';$('#inv-print-kardex').hidden=true;$('#inv-status').textContent='Falta instalar el esquema de inventario en este entorno.';return []}
 const rows=invFiltrar(),labs=[...new Set(rows.map(p=>(p.laboratorio||'Sin laboratorio').trim()))];
 const html=labs.map(l=>'<div class="item"><h3>'+esc(l)+'</h3><div class="cj-line inv-cols"><b>Producto</b><b>Cantidad</b><b>Unidades</b></div>'+rows.filter(p=>(p.laboratorio||'Sin laboratorio').trim()===l).map(p=>{const v=invPartes(invSaldo(p),p.unidades_por_caja);return '<div class="cj-line inv-cols"><span>'+esc(p.nombre)+'</span><b>'+v.cajas+'</b><b>'+v.sueltas+'</b></div>'}).join('')+'</div>').join('');
 $('#inv-kardex-list').innerHTML=html||'<p class="mut">No hay productos para los filtros seleccionados.</p>';
 $('#inv-print-kardex').hidden=!rows.length;
 $('#inv-status').textContent=rows.length+' productos incluidos en el informe.';
 return rows;
}
function invLabsClick(e){
 const box=e.target.closest('[data-inv-lab]');if(!box)return;
 const lab=box.dataset.invLab;if(e.target.checked)invLabsSeleccionados.add(lab);else invLabsSeleccionados.delete(lab);
 invRenderLabs();
}
function invGenerarKardex(){
 const rows=invRenderInforme();if(!rows.length){toast('No hay productos que coincidan con los filtros. Revisa la línea o la búsqueda.');return}
 const formato=document.querySelector('input[name="inv-formato"]:checked')?.value||'pantalla';
 if(formato==='pantalla')return;
 if(formato==='excel'){
  const data=[['Laboratorio','Producto','Cantidad','Unidades'],...rows.map(p=>{const v=invPartes(invSaldo(p),p.unidades_por_caja);return[p.laboratorio||'Sin laboratorio',p.nombre,v.cajas,v.sueltas]})];
  const csv='\uFEFF'+data.map(r=>r.map(x=>{let v=x??'';if(typeof v==='string'&&(['=','+','@','-'].includes(v[0])||v.charCodeAt(0)===9||v.charCodeAt(0)===13))v="'"+v;return '"'+String(v).replace(/"/g,'""')+'"'}).join(';')).join('\r\n');
  const blob=new Blob([csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='kardex-drosalud.csv';a.click();URL.revokeObjectURL(url);return;
 }
 invImprimirKardex(formato==='pos');
}
async function invLeerTodo(construir){
 const salida=[];let desde=0,lote=[];
 do{
  const{data,error}=await construir().range(desde,desde+999);
  if(error)throw error;
  lote=data||[];salida.push(...lote);desde+=lote.length;
 }while(lote.length===1000);
 return salida;
}
async function invCargarDatos(){
 // El catálogo se carga aparte: el Preview puede apuntar a una BD sin migraciones de inventario.
 // Si la columna linea aún no existe, cargar el catálogo sin ese filtro y continuar.
 let productos;
 try{
  productos=await invLeerTodo(()=>sb.from('productos_app').select('id,codigo,nombre,laboratorio,linea,unidades_por_caja').order('nombre').order('id'));
 }catch(e){
  if(!/linea|column/i.test(String(e.message||e)))throw e;
  productos=await invLeerTodo(()=>sb.from('productos_app').select('id,codigo,nombre,laboratorio,unidades_por_caja').order('nombre').order('id'));
  productos=productos.map(p=>({...p,linea:null}));
 }
 invProductos=productos;invSaldos={};invSaldoDisponible=false;
 try{
  const movimientos=await invLeerTodo(()=>sb.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id'));
  movimientos.forEach(m=>{invSaldos[m.producto_id]=Number(m.saldo_unidades||0)});
  invSaldoDisponible=true;
 }catch(e){console.warn('Kardex aún no instalado en este entorno:',e)}
 invLaboratorios=[...new Set(invProductos.map(p=>(p.laboratorio||'Sin laboratorio').trim()))].sort((a,b)=>a.localeCompare(b,'es',{sensitivity:'base'}));
 const opts=invProductos.slice().sort((a,b)=>a.nombre.localeCompare(b.nombre,'es',{sensitivity:'base'}));
 $('#inv-prod').innerHTML='<option value="">Seleccionar producto</option>'+opts.map(p=>'<option value="'+p.id+'">'+esc(p.nombre)+' · '+esc(p.laboratorio||'Sin laboratorio')+'</option>').join('');
 const buscador=$('#inv-prod-search'),resultados=$('#inv-prod-results'),seleccion=$('#inv-prod-selected');
 if(buscador&&resultados){
  buscador.value='';$('#inv-prod').value='';seleccion.textContent='Selecciona un producto del catálogo.';
  const pintar=()=>{const q=norm(buscador.value).trim(),dig=q.replace(/\\D/g,'');const hallados=opts.filter(p=>norm([p.nombre,p.laboratorio,p.codigo].join(' ')).includes(q)||(dig.length>=4&&String(p.codigo||'').replace(/\\D/g,'').includes(dig))).slice(0,12);
   resultados.innerHTML=hallados.map(p=>'<button type="button" class="btn alt full" data-inv-pick="'+p.id+'" style="text-align:left;margin:3px 0">'+esc(p.nombre)+' · '+esc(p.codigo||'Sin código')+' · '+esc(p.laboratorio||'')+'</button>').join('')||(q?'<p class="mut sm">No se encontraron coincidencias.</p>':'<p class="mut sm">Escribe para buscar en el catálogo.</p>');
  };
  buscador.oninput=()=>{ $('#inv-prod').value='';seleccion.textContent='Selecciona un producto del catálogo.';pintar() };
  resultados.onclick=e=>{const btn=e.target.closest('[data-inv-pick]');if(!btn)return;const p=opts.find(x=>String(x.id)===btn.dataset.invPick);if(!p)return;$('#inv-prod').value=p.id;buscador.value=p.nombre;seleccion.textContent='Seleccionado: '+p.nombre+' · '+(p.codigo||'Sin código');resultados.innerHTML=''};
  pintar();
 }
 const lineas=[...new Set(invProductos.map(p=>(p.linea||'').trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es',{sensitivity:'base'}));
 $('#inv-linea').innerHTML='<option value="">'+(lineas.length?'Todas las líneas':'Líneas disponibles al instalar migración')+'</option>'+lineas.map(l=>'<option value="'+esc(l)+'">'+esc(l)+'</option>').join('');
 $('#inv-linea').disabled=!lineas.length;
 invRenderLabs();
}
function invImprimirKardex(pos=false){
 const rows=invFiltrar();
 if(!rows.length){toast('No hay productos para imprimir');return}
 const title='Kardex de inventario',stamp=new Date().toLocaleString('es-CO');
 let h='<h2>'+title+'</h2><p>Consulta: '+stamp+'</p>';
 const labs=[...new Set(rows.map(p=>(p.laboratorio||'Sin laboratorio').trim()))];
 labs.forEach(l=>{h+='<h3>'+esc(l)+'</h3><div class="cj-line inv-cols"><b>Producto</b><b>Cantidad</b><b>Unidades</b></div>';rows.filter(p=>(p.laboratorio||'Sin laboratorio').trim()===l).forEach(p=>{const v=invPartes(invSaldo(p),p.unidades_por_caja);h+='<div class="cj-line inv-cols"><span>'+esc(p.nombre)+'</span><b>'+v.cajas+'</b><b>'+v.sueltas+'</b></div>'})});
 openM(h+'<div class="acts"><button class="btn alt full" onclick="closeM()">Cerrar</button></div>');
 document.body.classList.add('print-inventario');if(pos)document.body.classList.add('print-pos');
 window.addEventListener('afterprint',()=>document.body.classList.remove('print-inventario','print-pos'),{once:true});window.print();
}
function invImprimirPedido(){
 let h='<h2>Pedido sugerido</h2><p>Ventas de la semana actual (desde el lunes) · '+new Date().toLocaleDateString('es-CO')+'</p>';
 invPedidos.forEach((x,i)=>{const cajas=Math.max(0,Math.trunc(Number($('#inv-c-'+i).value)||0)),sueltas=Math.max(0,Math.trunc(Number($('#inv-s-'+i).value)||0));h+='<div class="cj-line"><span>'+esc(x.p.nombre)+'<small> · '+esc(x.p.laboratorio||'Sin laboratorio')+'</small></span><b>'+cajas+' cajas</b><b>'+sueltas+' unidades</b></div>'});
 openM(h+'<div class="acts"><button class="btn alt full" onclick="closeM()">Cerrar</button></div>');document.body.classList.add('print-inventario','print-pos');window.addEventListener('afterprint',()=>document.body.classList.remove('print-inventario','print-pos'),{once:true});window.print();
}
function invFechaInicio(){
 // Semana calendario desde el lunes 00:00, zona horaria fija de Colombia.
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Bogota',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
 const v={};parts.forEach(p=>{v[p.type]=p.value});
 const inicio=new Date(Date.UTC(Number(v.year),Number(v.month)-1,Number(v.day),5));
 inicio.setUTCDate(inicio.getUTCDate()-((inicio.getUTCDay()+6)%7));
 return inicio.toISOString();
}
function invFechaFin(){const fin=new Date(invFechaInicio());fin.setUTCDate(fin.getUTCDate()+7);return fin.toISOString();}
async function invCargarPedidos(){
 const recibos=await invLeerTodo(()=>sb.from('recibos_app').select('id').eq('anulado',false).gte('creado_en',invFechaInicio()).lt('creado_en',invFechaFin()).order('creado_en').order('id'));
 const ventas={};
 for(let i=0;i<recibos.length;i+=100){
  const ids=recibos.slice(i,i+100).map(r=>r.id);
  const items=await invLeerTodo(()=>sb.from('recibo_items_app').select('producto_id,cantidad,unidades_por_presentacion').in('recibo_id',ids).order('id'));
  items.forEach(x=>{if(x.producto_id)ventas[x.producto_id]=(ventas[x.producto_id]||0)+(Number(x.cantidad||0)*Math.max(1,Number(x.unidades_por_presentacion)||1))});
 }
 invPedidos=invProductos.filter(p=>(ventas[p.id]||0)>0).map(p=>{
  const u=ventas[p.id],f=Math.max(1,Number(p.unidades_por_caja)||1);
  return{p,unidades:u,cajas:Math.floor(u/f),sueltas:u%f};
 }).sort((a,b)=>(a.p.laboratorio||'').localeCompare(b.p.laboratorio||'','es',{sensitivity:'base'})||a.p.nombre.localeCompare(b.p.nombre,'es',{sensitivity:'base'}));
 $('#inv-pedidos-list').innerHTML=invPedidos.length?invPedidos.map((x,i)=>'<div class="item"><div class="top"><b>'+esc(x.p.nombre)+'</b><span class="mut">'+esc(x.p.laboratorio||'Sin laboratorio')+'</span></div><p class="sm">Vendido: '+x.cajas+' cajas · '+x.sueltas+' unidades ('+x.unidades+' unidades en total)</p><div class="two"><div><label for="inv-c-'+i+'">Cajas a pedir</label><input id="inv-c-'+i+'" type="number" min="0" step="1" value="'+x.cajas+'"></div><div><label for="inv-s-'+i+'">Unidades sueltas</label><input id="inv-s-'+i+'" type="number" min="0" max="'+(Math.max(1,Number(x.p.unidades_por_caja)||1)-1)+'" step="1" value="'+x.sueltas+'"></div></div></div>').join(''):'<p class="mut">No hay ventas de productos en la semana actual.</p>';
}
async function loadInventario(){
 $('#inv-status').textContent='Cargando productos y existencias…';
 try{await invCargarDatos();$('#inv-status').textContent=invSaldoDisponible?'Datos cargados. Selecciona laboratorios y genera el informe.':'Catálogo cargado. Para generar el Kardex falta instalar las migraciones en este entorno.'}
 catch(e){console.error(e);$('#inv-status').textContent='No se pudo cargar Kardex. La migración de inventario debe estar instalada en el entorno de pruebas. '+(e.message||'')}
}
async function loadPedidos(){
 if(window.DrosaludPedidos){await window.DrosaludPedidos.load();return}
 const box=$('#pedidos-app');if(box)box.textContent='El módulo de pedidos no pudo cargarse. Actualiza la página e inténtalo de nuevo.';
}
async function loadRecepcion(){
 $('#recep-status').textContent='Cargando catálogo…';
 try{await invCargarDatos();$('#recep-status').textContent='Selecciona el producto y registra solo las unidades que llegaron físicamente.'}
 catch(e){console.error(e);$('#recep-status').textContent='No se pudo cargar el catálogo: '+(e.message||'')}
}
async function invRegistrarRecepcion(){
 const id=$('#inv-prod').value,u=Number($('#inv-unidades').value),nota=$('#inv-notas').value.trim();
 if(!id){toast('Selecciona el producto recibido');return}
 if(!Number.isInteger(u)||u<=0){toast('Escribe una cantidad válida de unidades individuales');return}
 const b=$('#inv-recibir');b.disabled=true;
 try{
  const datos=JSON.stringify([id,u,nota]);if(!invRecepcionIntento||invRecepcionIntento.datos!==datos)invRecepcionIntento={datos,id:crypto.randomUUID()};
  const{error}=await sb.rpc('registrar_recepcion_inventario',{p_producto_id:id,p_unidades:u,p_notas:nota||null,p_operacion_id:invRecepcionIntento.id});
  if(error)throw error;
  $('#inv-unidades').value='';$('#inv-notas').value='';invRecepcionIntento=null;
  toast('Recepción registrada');$('#recep-status').textContent='Recepción guardada. El saldo fue actualizado.';await invCargarDatos();
 }catch(e){console.error(e);$('#recep-status').textContent='No se pudo registrar la recepción: '+(e.message||'Error desconocido');toast(e.message||'No se pudo registrar la recepción')}
 finally{b.disabled=false}
}
const vistaInventario=document.querySelector('#v-inventario');
vistaInventario.addEventListener('click',e=>{
 if(e.target.closest('#inv-generar'))invGenerarKardex();
 if(e.target.closest('#inv-print-kardex'))invImprimirKardex(document.querySelector('input[name="inv-formato"]:checked')?.value==='pos');
 if(e.target.closest('#inv-labs-all')){invLabsSeleccionados=new Set(invLaboratorios);invRenderLabs();invRenderInforme()}
 if(e.target.closest('#inv-labs-none')){invLabsSeleccionados.clear();invRenderLabs();invRenderInforme()}
});
vistaInventario.addEventListener('change',e=>{
 if(e.target.matches('[data-inv-lab]')){invLabsClick(e);invRenderInforme()}
 if(e.target.matches('#inv-linea')||e.target.matches('input[name="inv-contenido"]'))invRenderInforme();
});
$('#inv-q').addEventListener('input',()=>{invRenderLabs();invRenderInforme()});
document.querySelector('#v-pedidos').addEventListener('click',e=>{if(e.target.closest('#inv-print'))invImprimirPedido()});
document.querySelector('#v-recepcion').addEventListener('click',e=>{if(e.target.closest('#inv-recibir'))invRegistrarRecepcion()});
