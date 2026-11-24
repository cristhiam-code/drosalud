# Plan de estabilización y publicación de DROSalud

Actualizado: 24 de noviembre de 2026.

## Completado en QA
- Separación explícita de entorno y bloqueo de hosts no reconocidos.
- Pruebas del conteo ya realizadas anteriormente; no crear ni repetir sesiones.
- Controles de integridad en compras/recepción: producto de documento, idempotencia y autorización de diferencia de costo.
- Documentación inicial de procesos y arquitectura.
- Ayuda ampliada con diagnóstico del sistema, roles, precios, exportación y alcance real del archivo Excel.
- Extracción de funciones puras a domain/formatters.js, domain/presentaciones.js, domain/precios.js y domain/dinero.js.
- Servicios services/ventas.js, services/caja.js, services/informes.js, services/compras.js y services/pedidos.js y services/gestion-negocio.js y services/catalogo.js y services/clientes.js y services/configuracion.js con cliente Supabase inyectado.
- Pruebas Node para dominio y servicio, contratos Python y chequeo de sintaxis ampliado.
- Auditoría de ventas e inventario de producción en solo lectura: 62/62 líneas conciliadas con movimientos; anulaciones compensadas; saldo de vista igual a suma del Kardex.
- Auditoría de catálogo: dos precios manuales inferiores al costo requieren validación comercial; diez saldos negativos requieren conciliación física/documental.
- Auditoría de caja/cotizaciones: 16 cierres conciliados, uno reabierto por prueba, cero gastos registrados y 16 cotizaciones vencidas sin conversión a recibo.
- Auditoría de Informes: módulo de solo lectura con tres consultas de inventario; la valoración total está desactivada y no hay informes de ventas, margen, compras o rotación.
- Auditoría de seguridad: RLS activo en todas las tablas públicas revisadas, ninguna función SECURITY DEFINER ejecutable por anon y roles admin/vendedor activos.

## Última validación automatizada

- GitHub Actions: Pruebas y sintaxis SUCCESS en commit 032cc73 (run 45432608432), con 43 pruebas Python, 35 pruebas Node y chequeo de sintaxis JavaScript.
- El último despliegue de código de QA READY sigue siendo 30416b1. El código de la rama avanzó después (incluye el servicio de Pedidos), pero Vercel bloqueó los nuevos despliegues por límite de compilaciones; por eso el alias de preview está desactualizado y no sirve para validar el último commit.
- El PR #91 sigue en borrador y no se ha integrado ni desplegado a producción.

## Pendiente antes de considerar listo
1. Confirmar GitHub Actions para el último commit que contiene la separación de lecturas y escrituras de Pedidos, Recepción y Gestión de proveedores.
2. Revisión visual autenticada en QA de Ayuda/Sistema, exportación, login y navegación móvil.
3. Prueba funcional autenticada en QA de venta normal y fraccionada (caja + unidades), cotización, impresión y anulación, sin generar operaciones persistentes innecesarias.
4. Definir y validar informes de ventas, margen, compras, gastos y rotación. Caja, cotizaciones e informes actuales ya fueron auditados; confirmar si los gastos realmente no se usan o si falta registrarlos.
5. Conciliar los diez saldos negativos y los dos precios manuales bajo costo con existencias físicas y documentos originales. No corregir automáticamente.
6. Decidir si se necesita un respaldo realmente restaurable. La exportación actual solo incluye recibos, líneas de venta, productos, clientes e historial de precios; no incluye todo el ERP.
7. Continuar la extracción gradual de servicios del shell principal (ventas, catálogo, clientes, historial y configuración), sin mover el bootstrap de Supabase ni el selector de entorno.
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

## Actualización de arquitectura QA

- Pedidos ahora delega lecturas de pantalla y de Pedido sugerido, además de las RPC, a `services/pedidos.js`. La fórmula y la regla de reposición permanecen en el módulo.
- Recepción delega lecturas y escrituras a `services/compras.js`; ya no tiene consultas directas a Supabase.
- Gestión de proveedores delega lecturas, altas, cambios, bajas y cotizaciones a `services/gestion-negocio.js`; las validaciones de duplicados y los formularios permanecen en el módulo.
- Las pruebas de contrato se ampliaron para impedir que estos tres módulos vuelvan a consultar o escribir directamente en Supabase.
- La revisión automatizada de estos últimos cambios sigue pendiente de un nuevo resultado de GitHub Actions. No se considera aprobada hasta que el check termine correctamente.


- Se incorporó `services/catalogo.js` para persistencia de productos, precios, fraccionamiento, auditoría e importación. La interfaz mantiene sus validaciones y las reglas de negocio.


- Se incorporó `services/clientes.js` para acceso a clientes, consentimientos y su historial. Las reglas de privacidad y los controles de duplicados siguen en la interfaz y el backend.


- Se separó el acceso a Ajustes en `services/configuracion.js`, manteniendo la confirmación de guardado y la protección contra sobrescritura si falta el registro principal.
