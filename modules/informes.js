/* Drosalud · Informes y reportes · Solo lectura */
(() => {
  'use strict';
  const root = document.getElementById('informes-app');
  if (!root) return;
  const state = {products:[],balances:{},costs:{},rows:[],tab:'menu',filter:'todos',query:'',limit:50,loadedAt:null,warning:''};
  const esc = v => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const number = v => (Number(v)||0).toLocaleString('es-CO');
  const money = v => '$'+Math.round(Number(v)||0).toLocaleString('es-CO');
  const dateTime = v => v ? new Date(v).toLocaleString('es-CO',{dateStyle:'medium',timeStyle:'short'}) : '—';
  const factor = p => Math.max(1,Number(p.unidades_por_caja)||1);
  async function readAll(build){
    const rows=[];let start=0;
    while(true){const r=await build().range(start,start+999);if(r.error)throw r.error;const page=r.data||[];rows.push(...page);if(page.length<1000)return rows;start+=1000}
  }
  function message(msg,error){
    const el=root.querySelector('[data-ir-message]');if(!el)return;
    el.textContent=msg||'';el.hidden=!msg;el.classList.toggle('ir-error',!!error);
  }
  function resolveCost(p,record){
    if(record&&Number(record.cost)>0)return {unit:Number(record.cost),source:record.source,date:record.date};
    const catalog=Number(p.precio_compra);
    if(catalog>0)return {unit:catalog/factor(p),source:'Catálogo · costo de presentación convertido a unidad base',date:p.actualizado_en||null};
    return {unit:null,source:null,date:null};
  }
  async function loadData(){
    message('Consultando catálogo y existencias actuales…',false);
    const results=await Promise.all([
      readAll(()=>sb.from('productos_app').select('id,codigo,nombre,laboratorio,linea,precio_compra,precio_venta,fraccionable,unidades_por_caja,unidades_por_venta,actualizado_en').order('nombre').order('id')),
      readAll(()=>sb.from('inventario_saldos').select('producto_id,saldo_unidades').order('producto_id'))
    ]);
    state.products=results[0]||[];state.balances={};
    (results[1]||[]).forEach(x=>state.balances[x.producto_id]=Number(x.saldo_unidades)||0);
    const costMap={};let warning='';
    try{
      const movements=await readAll(()=>sb.from('inventario_movimientos').select('producto_id,costo_unitario_base,creado_en').not('costo_unitario_base','is',null).order('creado_en',{ascending:false}));
      movements.forEach(x=>{const cost=Number(x.costo_unitario_base);if(x.producto_id&&cost>0&&!costMap[x.producto_id])costMap[x.producto_id]={cost:cost,source:'Último movimiento con costo',date:x.creado_en}});
    }catch(e){console.warn('No se pudo leer el costo de movimientos:',e);warning='No se pudo consultar el costo de los movimientos; se utilizará el costo del catálogo cuando exista.'}
    try{
      const history=await readAll(()=>sb.from('historial_costos').select('producto_id,costo_unitario_base,registrado_en').order('registrado_en',{ascending:false}));
      history.forEach(x=>{const cost=Number(x.costo_unitario_base);if(!x.producto_id||!(cost>0))return;const old=costMap[x.producto_id];if(!old||new Date(x.registrado_en)>new Date(old.date||0))costMap[x.producto_id]={cost:cost,source:'Historial de costos',date:x.registrado_en}});
    }catch(e){console.warn('No se pudo leer historial de costos:',e)}
    state.costs=costMap;
    state.rows=state.products.map(p=>{
      const registered=Object.prototype.hasOwnProperty.call(state.balances,p.id);const stock=registered?(Number(state.balances[p.id])||0):null;const cost=resolveCost(p,costMap[p.id]);
      const sale=Number(p.precio_venta)>0?Number(p.precio_venta)/factor(p):null;
      return {product:p,stock:stock,unitCost:cost.unit,costSource:cost.source,costDate:cost.date,value:stock!==null&&stock>0&&cost.unit!==null?stock*cost.unit:null,saleUnit:sale,saleValue:stock!==null&&stock>0&&sale!==null?stock*sale:null};
    });
    state.loadedAt=new Date();state.warning=warning;state.limit=50;render();message('',false);
  }
  function filteredRows(){
    const q=state.query.trim().toLocaleLowerCase('es');
    return state.rows.filter(r=>{
      const p=r.product;
      if(state.tab==='faltantes'&&r.stock!==null&&r.stock>0)return false;
      if(state.filter==='positivas'&&!(r.stock!==null&&r.stock>0))return false;
      if(state.filter==='agotados'&&r.stock!==0)return false;
      if(state.filter==='negativos'&&!(r.stock!==null&&r.stock<0))return false;
      if(state.filter==='sin-movimientos'&&r.stock!==null)return false;
      if(state.filter==='sin-costo'&&!(r.stock!==null&&r.stock>0&&r.unitCost===null))return false;
      if(q&&![p.nombre,p.codigo,p.laboratorio,p.linea].some(v=>String(v||'').toLocaleLowerCase('es').includes(q)))return false;
      return true;
    }).sort((a,b)=>state.tab==='valor'?(b.value||0)-(a.value||0):a.product.nombre.localeCompare(b.product.nombre,'es'));
  }
  function renderKpis(){
    const positive=state.rows.filter(r=>r.stock!==null&&r.stock>0),negative=state.rows.filter(r=>r.stock!==null&&r.stock<0),zero=state.rows.filter(r=>r.stock===0),unregistered=state.rows.filter(r=>r.stock===null);
    const missing=positive.filter(r=>r.unitCost===null),saleMissing=positive.filter(r=>r.saleUnit===null).length;
    const total=positive.reduce((s,r)=>s+(r.value||0),0),sale=positive.reduce((s,r)=>s+(r.saleValue||0),0);
    let html='<div class="ir-kpis">';
    html+='<article class="ir-kpi ir-kpi-main"><span>Valor conocido al costo</span><strong>'+money(total)+'</strong><small>'+(missing.length?'Valor parcial: hay productos sin costo registrado':'Todos los productos con saldo positivo tienen costo')+'</small></article>';
    html+='<article class="ir-kpi"><span>Valor potencial de venta</span><strong>'+money(sale)+'</strong><small>'+number(saleMissing)+' productos sin precio de venta</small></article>';
    html+='<article class="ir-kpi"><span>Con existencias</span><strong>'+number(positive.length)+'</strong><small>'+number(positive.reduce((s,r)=>s+r.stock,0))+' unidades base</small></article>';
    html+='<article class="ir-kpi"><span>Agotados</span><strong>'+number(zero.length)+'</strong><small>Saldo registrado igual a cero</small></article>';
    html+='<article class="ir-kpi"><span>Sin movimientos</span><strong>'+number(unregistered.length)+'</strong><small>Sin saldo inicial ni movimientos registrados</small></article>';
    html+='<article class="ir-kpi"><span>Negativos</span><strong class="'+(negative.length?'ir-danger':'')+'">'+number(negative.length)+'</strong><small>'+number(negative.reduce((s,r)=>s+Math.abs(r.stock),0))+' unidades por cubrir</small></article>';
    html+='<article class="ir-kpi"><span>Sin costo confiable</span><strong class="'+(missing.length?'ir-warning':'')+'">'+number(missing.length)+'</strong><small>Con saldo positivo</small></article></div>';
    if(missing.length)html+='<p class="ir-alert ir-alert-warning">El valor mostrado es parcial. Los productos con existencias pero sin costo confiable se excluyen de la suma; no se les asigna un costo inventado.</p>';
    if(negative.length)html+='<p class="ir-alert">Los saldos negativos se muestran como faltantes y no se restan del valor de la mercancía disponible.</p>';
    if(unregistered.length)html+='<p class="ir-alert">Los productos sin movimientos no se consideran agotados: todavía no tienen saldo registrado en el Kardex.</p>';
    if(saleMissing)html+='<p class="ir-alert">El valor potencial de venta es parcial porque hay productos sin precio de venta.</p>';
    if(state.warning)html+='<p class="ir-alert">'+esc(state.warning)+'</p>';
    return html;
  }
  function renderRows(rows){
    if(!rows.length)return '<div class="ir-empty">No hay productos que coincidan con esta consulta.</div>';
    const cards=rows.slice(0,state.limit).map(r=>{
      const p=r.product;const status=r.stock===null?'<span class="ir-pill">Sin movimientos</span>':r.stock<0?'<span class="ir-pill ir-pill-danger">Negativo</span>':r.stock===0?'<span class="ir-pill">Agotado</span>':'<span class="ir-pill ir-pill-good">Disponible</span>';
      let html='<article class="ir-product"><div class="ir-product-title"><div><strong>'+esc(p.nombre)+'</strong><small>'+esc(p.codigo||'Sin código')+' · '+esc(p.laboratorio||'Sin laboratorio')+'</small></div>'+status+'</div>';
      html+='<div class="ir-product-data"><div><span>Existencia</span><b class="'+(r.stock!==null&&r.stock<0?'ir-danger':'')+'">'+(r.stock===null?'Sin movimientos':number(r.stock)+' unidades')+'</b></div>';
      html+='<div><span>Costo por unidad</span><b>'+(r.unitCost===null?'<em>Sin costo</em>':money(r.unitCost))+'</b></div>';
      html+='<div><span>Valor al costo</span><b>'+(r.value===null?'—':money(r.value))+'</b></div>';
      html+='<div><span>Valor de venta</span><b>'+(r.saleValue===null?'—':money(r.saleValue))+'</b></div></div>';
      if(r.stock>0&&r.unitCost!==null)html+='<small class="ir-source">Costo: '+esc(r.costSource||'Catálogo')+(r.costDate?' · '+esc(dateTime(r.costDate)):'')+'</small>';
      return html+'</article>';
    }).join('');
    return cards+(rows.length>state.limit?'<button type="button" class="btn alt full ir-more" data-ir-more>Mostrar '+Math.min(50,rows.length-state.limit)+' más ('+number(rows.length-state.limit)+' restantes)</button>':'');
  }
  function renderMenu(){
    return '<section class="ir-module"><header class="ir-heading"><div><span class="ir-kicker">ANÁLISIS DEL NEGOCIO</span><h2>Informes y reportes</h2><p>Selecciona qué información necesitas consultar.</p></div><button type="button" class="btn alt" data-ir-refresh>Actualizar datos</button></header>'+
      '<div class="ir-menu-grid">'+
      '<button type="button" class="ir-menu-card" data-ir-tab="valor"><span class="ir-menu-icon">▤</span><strong>Valor del inventario</strong><small>Consulta cuánto dinero representa la mercancía disponible, al costo y a precio de venta.</small><span class="ir-menu-link">Consultar informe →</span></button>'+
      '<button type="button" class="ir-menu-card" data-ir-tab="existencias"><span class="ir-menu-icon">▦</span><strong>Existencias</strong><small>Revisa cuánto hay de cada producto y consulta su costo y valor.</small><span class="ir-menu-link">Consultar informe →</span></button>'+
      '<button type="button" class="ir-menu-card" data-ir-tab="faltantes"><span class="ir-menu-icon">⚑</span><strong>Faltantes</strong><small>Identifica productos agotados, con saldo negativo o sin movimientos registrados.</small><span class="ir-menu-link">Consultar informe →</span></button>'+
      '</div><p class="ir-footnote">Informes conectados a los datos actuales de Drosalud. Son consultas de solo lectura.</p></section>';
  }
  function render(){
    if(state.tab==='menu'){root.innerHTML=renderMenu();return}
    const rows=filteredRows(),value=state.tab==='valor';
    const title=value?'Valor del inventario':state.tab==='existencias'?'Existencias':'Faltantes';
    const description=value?'Consulta el valor de las unidades disponibles usando el costo por unidad base.':state.tab==='existencias'?'Consulta las cantidades actuales de cada producto, calculadas desde los saldos registrados.':'Productos agotados, con saldo negativo o sin movimientos registrados. Los productos sin movimientos no se consideran agotados.';
    let html='<section class="ir-module"><header class="ir-heading ir-detail-heading"><div><button type="button" class="ir-back" data-ir-back>← Volver a informes</button><span class="ir-kicker">INFORMES Y REPORTES</span><h2>'+title+'</h2><p>'+description+'</p></div><button type="button" class="btn alt" data-ir-refresh>Actualizar</button></header>';
    if(value)html+=renderKpis();
    html+='<section class="ir-panel"><div class="ir-filters"><input type="search" data-ir-search placeholder="Buscar producto, código o laboratorio" value="'+esc(state.query)+'"><select data-ir-filter aria-label="Filtrar productos"><option value="todos" '+(state.filter==='todos'?'selected':'')+'>Todos</option><option value="positivas" '+(state.filter==='positivas'?'selected':'')+'>Con existencias</option><option value="agotados" '+(state.filter==='agotados'?'selected':'')+'>Agotados</option><option value="negativos" '+(state.filter==='negativos'?'selected':'')+'>Negativos</option><option value="sin-movimientos" '+(state.filter==='sin-movimientos'?'selected':'')+'>Sin movimientos</option><option value="sin-costo" '+(state.filter==='sin-costo'?'selected':'')+'>Con costo pendiente</option></select></div>';
    html+='<div class="ir-results-meta"><span>'+number(rows.length)+' productos</span><span>Actualizado: '+dateTime(state.loadedAt)+'</span></div><div class="ir-list">'+renderRows(rows)+'</div>';
    html+='<div class="ir-export"><button type="button" class="btn alt" data-ir-excel>Exportar Excel</button><button type="button" class="btn alt" data-ir-pdf>Guardar PDF</button></div></section><p class="ir-footnote">Consulta de solo lectura. No modifica existencias, costos, pedidos ni movimientos del Kardex.</p></section>';
    root.innerHTML=html;
  }
  function exportExcel(){
    if(typeof XLSX==='undefined'){message('No está disponible el componente de Excel en esta versión.',true);return}
    const data=filteredRows().map(r=>({Codigo:r.product.codigo||'',Producto:r.product.nombre,Laboratorio:r.product.laboratorio||'',Existencias_unidades:r.stock,Estado_inventario:r.stock===null?'Sin movimientos':r.stock<0?'Negativo':r.stock===0?'Agotado':'Disponible',Costo_unitario_base:r.unitCost,Valor_inventario:r.value,Precio_venta_unitario:r.saleUnit,Valor_potencial_venta:r.saleValue,Fuente_costo:r.costSource||'Sin costo confiable'}));
    const book=XLSX.utils.book_new();XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(data),'Inventario');
    XLSX.writeFile(book,'drosalud-inventario-'+new Date().toISOString().slice(0,10)+'.xlsx');
  }
  function exportPdf(){
    const rows=filteredRows(),popup=window.open('','_blank');
    if(!popup){message('El navegador bloqueó la ventana de impresión. Permite las ventanas emergentes para guardar el PDF.',true);return}
    const title=state.tab==='valor'?'Valor del inventario':state.tab==='existencias'?'Existencias':'Faltantes';
    const body=rows.map(r=>'<tr><td>'+esc(r.product.codigo||'—')+'</td><td>'+esc(r.product.nombre)+'</td><td>'+(r.stock===null?'Sin movimientos':number(r.stock))+'</td><td>'+(r.unitCost===null?'Sin costo':money(r.unitCost))+'</td><td>'+(r.value===null?'—':money(r.value))+'</td></tr>').join('');
    popup.document.write('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>'+title+' · Drosalud</title><style>body{font:12px Arial,sans-serif;color:#17365c;padding:24px}h1{font-size:20px}p{color:#52657b}table{width:100%;border-collapse:collapse;margin-top:18px}th,td{padding:7px;border-bottom:1px solid #dce7f1;text-align:left}th{background:#edf4fb}td:nth-child(n+3){text-align:right}</style></head><body><h1>Drosalud · '+title+'</h1><p>Generado: '+esc(dateTime(new Date()))+' · Productos: '+number(rows.length)+'</p><table><thead><tr><th>Código</th><th>Producto</th><th>Existencia</th><th>Costo unitario</th><th>Valor al costo</th></tr></thead><tbody>'+body+'</tbody></table><script>window.onload=function(){window.print()}<\/script></body></html>');
    popup.document.close();
  }
  root.addEventListener('click',e=>{
    const b=e.target.closest('button');if(!b)return;
    if(b.hasAttribute('data-ir-refresh'))loadData().catch(showError);
    else if(b.hasAttribute('data-ir-back')){state.tab='menu';state.query='';state.filter='todos';state.limit=50;render()}\n    else if(b.dataset.irTab){state.tab=b.dataset.irTab;state.query='';state.filter='todos';state.limit=50;render()}
    else if(b.hasAttribute('data-ir-more')){state.limit+=50;render()}
    else if(b.hasAttribute('data-ir-excel'))exportExcel();
    else if(b.hasAttribute('data-ir-pdf'))exportPdf();
  });
  root.addEventListener('input',e=>{
    if(!e.target.matches('[data-ir-search]'))return;
    state.query=e.target.value;state.limit=50;const pos=e.target.selectionStart;render();
    const input=root.querySelector('[data-ir-search]');input.focus();input.setSelectionRange(pos,pos);
  });
  root.addEventListener('change',e=>{if(e.target.matches('[data-ir-filter]')){state.filter=e.target.value;state.limit=50;render()}});
  function showError(error){
    console.error('Informes y reportes:',error);
    root.innerHTML='<section class="ir-module"><h2>No se pudieron cargar los informes</h2><p class="ir-alert">'+esc(error?.message||'Revisa tu conexión y vuelve a intentarlo.')+'</p><button type="button" class="btn" data-ir-refresh>Intentar de nuevo</button></section>';
  }
  window.DrosaludInformes={load:async function(){try{await loadData()}catch(e){showError(e)}}};
})();