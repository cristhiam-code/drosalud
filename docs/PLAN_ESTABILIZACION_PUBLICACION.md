# Plan de estabilización y publicación de DROSalud

Actualizado: 24 de noviembre de 2026.

## Completado en QA
- Separación explícita de entorno y bloqueo de hosts no reconocidos.
- Pruebas del conteo ya realizadas anteriormente; no crear ni repetir sesiones.
- Controles de integridad en compras/recepción: producto de documento, idempotencia y autorización de diferencia de costo.
- Documentación inicial de procesos y arquitectura.
- Ayuda ampliada con diagnóstico del sistema, roles, precios, exportación y alcance real del archivo Excel.
- Extracción de funciones puras a domain/formatters.js, domain/presentaciones.js, domain/precios.js y domain/dinero.js.
- Servicios services/ventas.js, services/caja.js, services/informes.js y services/compras.js con cliente Supabase inyectado.
- Pruebas Node para dominio y servicio, contratos Python y chequeo de sintaxis ampliado.
- Auditoría de ventas e inventario de producción en solo lectura: 62/62 líneas conciliadas con movimientos; anulaciones compensadas; saldo de vista igual a suma del Kardex.
- Auditoría de catálogo: dos precios manuales inferiores al costo requieren validación comercial; diez saldos negativos requieren conciliación física/documental.
- Auditoría de caja/cotizaciones: 16 cierres conciliados, uno reabierto por prueba, cero gastos registrados y 16 cotizaciones vencidas sin conversión a recibo.
- Auditoría de Informes: módulo de solo lectura con tres consultas de inventario; la valoración total está desactivada y no hay informes de ventas, margen, compras o rotación.
- Auditoría de seguridad: RLS activo en todas las tablas públicas revisadas, ninguna función SECURITY DEFINER ejecutable por anon y roles admin/vendedor activos.

## Última validación automatizada

- GitHub Actions: Pruebas y sintaxis SUCCESS en commit 70aa573 (run 45432028559), con 42 pruebas Python, 33 pruebas Node y chequeo de sintaxis JavaScript.
- El último despliegue de código de QA READY es 30416b1 y conserva el alias de preview. Un commit posterior solo de pruebas recibió el límite temporal de compilaciones de Vercel; no cambió la aplicación.
- El PR #91 sigue en borrador y no se ha integrado ni desplegado a producción.

## Pendiente antes de considerar listo
1. Confirmar el resultado de GitHub Actions para el último commit que contiene el servicio de ventas y las aclaraciones de exportación.
2. Revisión visual autenticada en QA de Ayuda/Sistema, exportación, login y navegación móvil.
3. Prueba funcional autenticada en QA de venta normal y fraccionada (caja + unidades), cotización, impresión y anulación, sin generar operaciones persistentes innecesarias.
4. Definir y validar informes de ventas, margen, compras, gastos y rotación. Caja, cotizaciones e informes actuales ya fueron auditados; confirmar si los gastos realmente no se usan o si falta registrarlos.
5. Conciliar los diez saldos negativos y los dos precios manuales bajo costo con existencias físicas y documentos originales. No corregir automáticamente.
6. Decidir si se necesita un respaldo realmente restaurable. La exportación actual solo incluye recibos, líneas de venta, productos, clientes e historial de precios; no incluye todo el ERP.
7. Continuar la extracción gradual de servicios y lógica del shell, sin mover aún el bootstrap de Supabase, el selector de entorno, Pedidos ni Recepción.
8. Revisar impresión térmica y móvil en QA, especialmente el formato de recibos y Kardex.
9. Hacer una revisión final de permisos, RLS, RPC y diferencias de esquema entre QA y producción.

## Condiciones para publicar
- PR #91 permanece en borrador y no se fusiona sin aprobación.
- No modificar main ni producción durante la estabilización.
- Todas las pruebas y revisiones funcionales deben estar completas en QA.
- Comparar el diff y las migraciones una por una; verificar respaldo antes de cualquier cambio productivo.
- La publicación y las migraciones de producción requieren autorización expresa.

## Criterio de finalización
DROSalud se considera preparado cuando los procesos del negocio estén documentados, las dependencias sean explícitas, los tests pasen, las cifras estén conciliadas o sus excepciones estén documentadas, los usuarios puedan completar los flujos en QA y no queden cambios de producción sin aprobar.