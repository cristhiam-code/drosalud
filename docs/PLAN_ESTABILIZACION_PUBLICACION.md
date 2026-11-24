# Plan de estabilización y publicación de DROSalud

Actualizado: 24 de noviembre de 2026.

## Objetivo

Dejar el ERP organizado, verificable y documentado para que las operaciones de ventas, inventario, compras, recepción, caja e informes sean coherentes y puedan probarse en QA antes de cualquier publicación. Esta estabilización no autoriza cambios en producción.

## Completado y verificado

### Entornos y seguridad
- Selector explícito de QA/producción mediante lista cerrada de hosts y bloqueo de hosts no reconocidos.
- Entorno QA separado de la base productiva.
- Tres controles de integridad de compras/recepción aplicados y verificados únicamente en Supabase QA: correspondencia producto-documento, idempotencia concurrente y autorización/motivo para diferencias de costo.
- RLS activo en las tablas públicas revisadas; ninguna función SECURITY DEFINER revisada ejecutable por anon.
- No se modificaron datos, esquema, permisos, variables ni configuración de producción.

### Código y dependencias
- Reglas puras separadas en `domain/`: formato, presentaciones, precios y cálculos monetarios.
- Servicios con cliente Supabase inyectado en `services/`: ventas, caja, informes, compras, pedidos, gestión del negocio, catálogo, clientes, configuración, historial e inventario.
- Módulos delegan progresivamente acceso a datos a los servicios; las reglas de negocio y validaciones de interfaz permanecen en los módulos cuando corresponde.
- Pruebas Node nativas, pruebas Python de contratos de arquitectura y chequeo de sintaxis JavaScript. No se agregaron dependencias externas.
- Ayuda y Sistema explican los procesos principales, perfiles, exportación y sus límites, estado de conexión, sesión, base de datos, entorno y mediciones de carga.

### Auditorías de datos (producción, solo lectura)
- Ventas e inventario: 62/62 líneas de venta con movimiento correcto; anulaciones compensadas y saldos Kardex conciliados.
- Excepciones de catálogo: diez saldos negativos y dos precios manuales bajo costo; requieren conciliación física/documental y validación comercial. No se corrigieron automáticamente.
- Caja y cotizaciones: 16 cierres conciliados, uno reabierto por una prueba anterior, cero gastos registrados y 16 cotizaciones vencidas sin conversión a recibo.
- Compras/recepción: 41/41 líneas de recepción conciliadas con exactamente un movimiento Kardex correcto. Se identificaron excedentes documentales, diferencias de costo y dos movimientos históricos sin referencia; requieren cotejo con documentos originales. No se modificaron.
- Informes: actualmente es un módulo de consulta de inventario; la valoración total está desactivada y no están implementados informes completos de ventas, margen, compras o rotación.

### Conteo
- La prueba funcional de QA ya se realizó y quedó cerrada. No crear ni repetir sesiones.

## Validación automatizada vigente

- Rama: `qa/entorno-seguro-ci`.
- Commit: `b75458f7883162d3bdac7769b788df296f46e543`.
- GitHub Actions push #330 y pull_request #331: **SUCCESS**.
- Última ejecución: 49 pruebas Python y 68 pruebas Node aprobadas; 0 fallidas; chequeo de sintaxis incluido.
- Run: https://github.com/cristhiam-code/drosalud/actions/runs/45435936182
- Los fallos anteriores #273/#274 correspondían al commit `e3551e7`: tres pruebas verificaban de forma incorrecta el texto del error de cliente Supabase inválido. El commit actual supera esas pruebas.
- Las ejecuciones canceladas no son fallos de pruebas: el workflow define `concurrency.cancel-in-progress: true` y cancela ejecuciones anteriores de la misma referencia cuando llega una nueva.
- Queda una advertencia no bloqueante por acciones de GitHub que aún usan Node.js 20. Actualizar versiones de acciones en un cambio separado y volver a validar.

## Validación funcional pendiente

El preview READY más reciente de Vercel para QA apunta al commit `4651da2`, anterior al commit actual. Por tanto, los cambios actuales todavía no tienen validación visual autenticada. No se fuerza un despliegue mientras siga el antecedente de límite de compilaciones.

Cuando exista un preview del commit vigente, realizar una revisión breve y controlada de:
1. Inicio de sesión y confirmación visible del entorno QA.
2. Ayuda y Sistema: guía, estado, exportación, versión y mediciones.
3. Venta normal y venta fraccionada (caja más unidades), sin generar registros innecesarios.
4. Cotización, historial y anulación, verificando sus efectos.
5. Pedido sugerido y urgente, sin cambiar sus reglas.
6. Documento de proveedor y recepción, comprobando cantidades, costos, autorización y prevención de duplicados.
7. Caja, informes y exportaciones.
8. Impresión térmica de recibo y Kardex, y navegación móvil.

## Pendientes de negocio y datos

- Cotejar con documentos originales las diferencias de cantidades/costos de compras, los dos movimientos históricos sin referencia y los documentos cuyo total no coincide con sus líneas. No corregir sin evidencia.
- Conciliar los diez saldos negativos con inventario físico y soportes de movimientos.
- Revisar los dos precios manuales inferiores al costo con criterio comercial.
- Definir si se requiere un respaldo completo restaurable. La exportación actual contiene recibos, ventas por producto, productos, clientes e historial de precios; no incluye todo el ERP.
- Definir necesidades y reglas para informes de ventas, margen, compras, gastos y rotación.
- Revisar permisos, RLS, RPC y diferencias de esquema QA/producción antes de cualquier publicación.

## Publicación controlada

- PR #91 permanece en borrador y no se fusiona ni despliega a producción sin aprobación expresa.
- El PR #91 actualmente apunta a la rama base `feature/conteo-fisico-inventario`, no a `main`. Confirmar el destino correcto antes de una futura integración; no se ha cambiado automáticamente.
- No modificar `main`, permisos productivos ni datos de producción durante esta estabilización.
- Antes de publicar, comparar el diff y las migraciones una por una, confirmar respaldo restaurable y repetir las pruebas en el entorno de destino.
- Cualquier migración o despliegue productivo requiere autorización expresa.

## Criterio de finalización

DROSalud estará preparado para una decisión de publicación cuando: el CI del commit vigente pase; el preview correspondiente supere la revisión funcional; los procesos y permisos estén documentados; las cifras estén conciliadas o sus excepciones estén respaldadas; y no queden cambios productivos sin revisar. Tener CI verde por sí solo no significa que el ERP esté listo para operar en producción.
