/* Centro de ayuda: utiliza métricas reales del navegador; no simula velocidad de internet. */
(() => {
 'use strict';
 const button=document.getElementById('ayuda-performance'),output=document.getElementById('ayuda-performance-results');
 if(!button||!output)return;
 const ms=value=>Number.isFinite(value)&&value>=0?Math.round(value)+' ms':'No disponible';
 button.addEventListener('click',()=>{
  const nav=performance.getEntriesByType('navigation')?.[0];
  if(!nav){output.textContent='Este navegador no expone las métricas de carga.';return}
  const metrics=[['Resolución DNS',nav.domainLookupEnd-nav.domainLookupStart],['Conexión',nav.connectEnd-nav.connectStart],['Respuesta del servidor',nav.responseStart-nav.requestStart],['Documento interactivo',nav.domInteractive],['DOM listo',nav.domContentLoadedEventEnd],['Carga completa',nav.loadEventEnd||nav.duration]];
  output.innerHTML='<dl>'+metrics.map(([label,value])=>'<div><dt>'+label+'</dt><dd>'+ms(value)+'</dd></div>').join('')+'</dl><p class="mut sm">Medición de la carga actual, registrada por el navegador. Varía según dispositivo, conexión y caché.</p>';
 });
})();
