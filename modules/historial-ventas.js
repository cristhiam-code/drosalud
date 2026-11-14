/* Historial de ventas e informes. Extraído sin reescribir la lógica original. */
function rango(){const v=$('#hp').value,n=new Date(),d0=new Date(n.getFullYear(),n.getMonth(),n.getDate()),day=864e5;let a,b;
if(v==='hoy'){a=d0;b=new Date(d0.getTime()+day)}
else if(v==='sem'){a=new Date(d0.getTime()-((d0.getDay()+6)%7)*day);b=new Date(a.getTime()+7*day)}
else if(v==='mes'){a=new Date(n.getFullYear(),n.getMonth(),1);b=new Date(n.getFullYear(),n.getMonth()+1,1)}
else if(v==='mant'){a=new Date(n.getFullYear(),n.getMonth()-1,1);b=new Date(n.getFullYear(),n.getMonth(),1)}
else if(v==='30'){a=new Date(d0.getTime()-29*day);b=new Date(d0.getTime()+day)}
else if(v==='rango'){const x=$('#hd1').value,y=$('#hd2').value;a=x?new Date(x+'T00:00:00'):new Date(2000,0,1);b=y?new Date(new Date(y+'T00:00:00').getTime()+day):new Date(d0.getTime()+day)}
else{a=new Date(2000,0,1);b=new Date(d0.getTime()+day)}
return[a,b]}
function hisFiltered(){const q=norm($('#hq').value);return q?H.filter(r=>norm((r.cliente_nombre||'')+' '+r.numero+' '+pad(r.numero)).includes(q)):H}
async function loadHis(){const[a,b]=rango();let o=[],f=0;for(;;){const{data,error}=await sb.from('recibos_app').select('*').gte('creado_en',a.toISOString()).lt('creado_en',b.toISOString()).order('creado_en',{ascending:false}).order('id').range(f,f+999);if(error)throw error;o=o.concat(data);if(data.length<1000)break;f+=1000}H=o;hisShown=100;rHis();if(hv==='res')await rResumen()}
function rHis(){const all=hisFiltered(),valid=all.filter(r=>!r.anulado),anul=all.filter(r=>!!r.anulado),V=hv==='anul'?anul:valid,s=valid.reduce((a,r)=>a+Number(r.total),0),g=valid.reduce((a,r)=>a+Number(r.ganancia),0);$('#hs').textContent=money(s);$('#hg').textContent=money(g);$('#hn').textContent=hv==='anul'?anul.length+(anul.length===1?' operación anulada':' operaciones anuladas')+' en este período':valid.length+(valid.length===1?' venta':' ventas')+' en este período'+(anul.length?' · '+anul.length+' anulada'+(anul.length===1?'':'s')+' aparte':'');
$('#hl').innerHTML=V.length?V.slice(0,hisShown).map(r=>`<button class="row${r.anulado?' anul':''}" data-rc="${r.id}"><span class="nm">Recibo ${pad(r.numero)}${r.cliente_nombre?' · '+esc(tcase(r.cliente_nombre)):''}<small>${esc(fmt(r.creado_en))}${r.anulado?' · ANULADO · '+esc(r.motivo_anulacion||'Sin motivo registrado'):''}</small></span><span class="pr">${money(r.total)}${`<small>ganancia ${money(r.ganancia)}</small>`}</span></button>`).join(''):'<p class="mut">'+(hv==='anul'?'No hay operaciones anuladas en este período.':'No hay ventas en este período.')+'</p>';$('#hmore').hidden=V.length<=hisShown}
async function itemsDe(rs){let it=[];for(let i=0;i<rs.length;i+=40){const ids=rs.slice(i,i+40).map(r=>r.id);const{data,error}=await sb.from('recibo_items_app').select('*').in('recibo_id',ids);if(error)throw error;it=it.concat(data)}return it}
function setHV(v){if(v==='res'&&!usuarioDrosalud){toast('Inicia sesión.');return}hv=v;document.querySelectorAll('[data-hv]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.hv===v)));$('#hrec').hidden=v==='res';$('#hres').hidden=v!=='res';if(v!=='res'){hisShown=100;rHis()}else go(rResumen)}
const hisValid=()=>hisFiltered().filter(r=>!r.anulado);
async function rResumen(){const L=hisValid(),box=$('#hres');if(!L.length){box.innerHTML='<p class="mut">No hay ventas en este período.</p>';return}
box.innerHTML='<p class="mut">Calculando…</p>';const it=await itemsDe(L),T=L.reduce((a,r)=>a+Number(r.total),0),G=L.reduce((a,r)=>a+Number(r.ganancia),0),D=L.reduce((a,r)=>a+Number(r.domicilio||0),0),M=L.reduce((a,r)=>a+Number(r.costo_mensajero||0),0),base=T-D;
const mp=new Map();it.forEach(i=>{const o=mp.get(i.nombre)||{n:i.nombre,u:0,v:0,g:0};o.u+=i.cantidad;o.v+=i.precio_venta*i.cantidad;o.g+=(i.precio_venta-(i.costo_real_unitario==null?i.precio_compra:i.costo_real_unitario))*i.cantidad;mp.set(i.nombre,o)});
const top=[...mp.values()].sort((a,b)=>b.g-a.g).slice(0,8),topUnidades=[...mp.values()].sort((a,b)=>b.u-a.u).slice(0,10),mx=Math.max(1,...top.map(x=>x.g));
const fp={};L.forEach(r=>{const k=r.forma_pago||'Sin dato';fp[k]=(fp[k]||0)+Number(r.total)});
const low=it.filter(i=>i.precio_venta<i.precio_compra||mg(i.precio_venta,i.precio_compra)<cfg.mMin).length;
const ds=L.map(r=>new Date(r.creado_en).getTime()),mn=new Date(Math.min(...ds)),mxd=new Date(Math.max(...ds)),byM=(mxd-mn)/864e5>62,key=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+(byM?'':'-'+String(d.getDate()).padStart(2,'0'));
const sv={};L.forEach(r=>{const k=key(new Date(r.creado_en));sv[k]=(sv[k]||0)+Number(r.total)});
const keys=[],c=byM?new Date(mn.getFullYear(),mn.getMonth(),1):new Date(mn.getFullYear(),mn.getMonth(),mn.getDate());while(c<=mxd){keys.push(key(c));if(byM)c.setMonth(c.getMonth()+1);else c.setDate(c.getDate()+1)}
const vd={};L.forEach(r=>{const k=(r.vendedor||'').trim()||'Sin vendedor';vd[k]=(vd[k]||0)+Number(r.total)});const vdH=Object.keys(vd).length>=2?'<h2>Por vendedor</h2>'+Object.entries(vd).sort((a,b)=>b[1]-a[1]).map(e=>`<div class="rk"><span>${esc(e[0])}</span><b>${money(e[1])}</b></div>`).join(''):'';
const vmax=Math.max(1,...keys.map(k=>sv[k]||0)),lab=k=>byM?k.slice(5)+'/'+k.slice(2,4):k.slice(8);
box.innerHTML=`<div class="kpi"><div>Ventas<b>${money(T)}</b></div><div>Ganancia<b>${money(G)}</b></div><div>Recibos<b>${L.length}</b></div><div>Ticket promedio<b>${money(T/L.length)}</b></div><div>Ganancia sobre ventas<b>${base>0?(G/base*100).toFixed(1).replace('.',','):0}%</b></div><div>Domicilios cobrados<b>${money(D)}</b></div><div>Pagos a mensajeros<b>${money(M)}</b></div></div>
<h2>Ventas por ${byM?'mes':'día'}</h2><div class="bars">${keys.map(k=>`<div title="${k}: ${money(sv[k]||0)}"><i style="height:${Math.round((sv[k]||0)/vmax*100)}%"></i>${lab(k)}</div>`).join('')}</div>
<h2>Productos más vendidos</h2>${topUnidades.map((x,n)=>`<div class="rk"><span>${n+1}. ${esc(x.n)}<small>${x.u} unidades · ${money(x.v)} vendido</small></span><b>${x.u} und</b></div>`).join('')}<h2>Productos que más ganancia dejan</h2>${top.map((x,n)=>{const w=Math.round(x.g/mx*100);return `<div class="rk" style="background:linear-gradient(90deg,var(--soft) ${w}%,var(--card) ${w}%)"><span>${n+1}. ${esc(x.n)}<small>${x.u} und · ${money(x.v)} vendido</small></span><b>${money(x.g)}</b></div>`}).join('')}
<h2>Por forma de pago</h2>${Object.entries(fp).sort((a,b)=>b[1]-a[1]).map(e=>`<div class="rk"><span>${esc(e[0])}</span><b>${money(e[1])}</b></div>`).join('')}${vdH}
${low?`<p class="warn">⚠ ${low} línea${low>1?'s':''} vendida${low>1?'s':''} con ganancia menor a ${cfg.mMin}%.</p>`:''}
<p class="mut sm">La ganancia por producto es antes de descuentos. La ganancia del recibo ya resta el descuento y no cuenta el domicilio.</p>`}
