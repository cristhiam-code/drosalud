# Diseño funcional — Compras y recepción profesional

Estado: implementación de base de datos iniciada en QA. Sin cambios en producción.

## Objetivo

Conciliar de forma trazable tres hechos distintos:
1. Lo que DROSalud solicitó (orden de compra).
2. Lo que el proveedor documentó (factura y/o remisión).
3. Lo que físicamente se recibió y aceptó.

El inventario y el Kardex solo reciben cantidades físicamente aceptadas y confirmadas.

## Reglas que no se negocian

- No cambiar la lógica ni los resultados de `loadSuggested()` en `modules/pedidos.js`.
- No alterar ventas, caja, autenticación, roles/permisos ni el diseño global del panel.
- Mantener las cantidades internas en unidades base para inventario y Kardex.
- Mostrar al usuario la presentación comercial y su equivalencia (por ejemplo, 2 cajas × 30 unidades = 60 unidades base).
- No asumir que una factura debe coincidir exactamente con una orden: las diferencias se documentan y concilian.
- No sumar a inventario productos adicionales, sobrantes, dañados o rechazados sin decisión explícita.
- No actualizar el costo vigente del producto hasta que la recepción y el costo aceptado estén confirmados.
- Conservar idempotencia y validaciones transaccionales existentes de `registrar_recepcion_compra`.

## Modelo operativo

### A. Orden de compra
La orden conserva producto, proveedor, presentación/unidades por presentación, unidades solicitadas (base), costo estimado y estado. La sugerencia de compra actual se mantiene intacta.

### B. Documento del proveedor
Un documento es independiente de la recepción física. Debe registrar:
- Tipo: factura, remisión, nota crédito u otro documento admitido.
- Número, fecha de emisión y proveedor.
- Moneda (COP inicialmente).
- Subtotal, descuentos, impuestos, flete y total cuando estén disponibles.
- Referencia a una o varias órdenes, según la operación real.
- Líneas: producto, presentación descrita, cantidad documentada, unidades por presentación, precio por presentación y equivalencia a unidades base.

No se debe duplicar el mismo documento por cada entrega. Debe poder existir una factura con varias entregas/remisiones.

### C. Recepción física
Cada entrega se registra separadamente:
- Fecha/hora de recepción y persona que recibe.
- Documento relacionado, si existe.
- Cantidad físicamente recibida por línea y presentación.
- Cantidad aceptada, rechazada y motivo.
- Lote y vencimiento cuando aplique y cuando el catálogo/operación pueda capturarlos.
- Evidencia/observaciones.

Una recepción parcial no cierra automáticamente la orden. Una segunda entrega se registra como otra recepción vinculada a la misma orden/documento.

### D. Conciliación
Por producto y presentación se comparan:
- Ordenado.
- Documentado/facturado.
- Recibido físicamente.
- Aceptado para inventario.
- Pendiente y diferencia.

Estados sugeridos: pendiente, parcial, conciliado, diferencia por revisar, rechazado/cancelado. Los estados deben derivarse de las cantidades y decisiones, no de un texto libre.

### E. Inventario y costos
- Solo unidades aceptadas generan movimiento de inventario tipo recepción.
- La conversión a unidades base se calcula con la equivalencia guardada en la línea, no con una equivalencia que pueda cambiar después.
- Costo presentado por proveedor se convierte automáticamente a costo por unidad base.
- Descuentos, impuestos recuperables/no recuperables y flete requieren una regla contable definida antes de incorporarlos al costo de adquisición; no se deben sumar arbitrariamente.
- Diferencias de precio requieren confirmación antes de actualizar el costo del producto y el historial de costos.

## Hallazgos de auditoría del esquema y RPC actuales (18-11-2026)

Verificado directamente en el proyecto Supabase conectado:
- Las tablas de órdenes, recepciones, movimientos y costos tienen RLS habilitado.
- Las políticas visibles para el equipo permiten lectura; no hay políticas directas de INSERT/UPDATE para las tablas operativas consultadas. La escritura se canaliza por RPC.
- `registrar_recepcion_compra` es `SECURITY DEFINER`, permite recibir a un usuario reconocido por `es_usuario_drosalud()`, valida orden aprobada/parcial, líneas pertenecientes a la orden, no exceder cantidad pendiente y evita reintentos duplicados con identificador de operación.
- Esa RPC inserta recepción, movimientos de inventario, actualiza unidades recibidas, actualiza `productos.precio_compra` y agrega historial de costos en una misma transacción.
- El costo de presentación se calcula multiplicando costo por unidad base por `productos.unidades_por_caja`.
- La RPC actual no registra fecha/tipo/valores del documento ni distingue cantidades facturadas de cantidades recibidas.
- `generar_ordenes_compra_pedido` y `autorizar_pedido` tienen validaciones de administrador que deben conservarse.

## Base de datos añadida en QA

Migración aplicada únicamente al proyecto `drosalud-pruebas`:
`supabase/migrations/20261118000100_compras_documentos_proveedor_base.sql`

Añade:
- `documentos_proveedor`: cabecera de factura/remisión/nota crédito, proveedor, fecha, valores y estado.
- `documentos_proveedor_items`: cantidades y precios tal como aparecen en el documento, guardando la equivalencia de presentación usada en ese momento.
- `documentos_proveedor_ordenes`: permite relacionar un documento con varias órdenes.
- `recepciones_compra.documento_id`: vínculo opcional entre una entrega física y su documento.

Seguridad inicial:
- RLS habilitado en las tres tablas nuevas.
- Lectura limitada a usuarios reconocidos de DROSalud.
- Sin permisos de escritura directa para `anon` ni `authenticated`; las altas y cambios deberán pasar por RPC con validaciones.
- Verificación SQL confirmó que RLS está activo en las tres tablas.

Esta etapa es solo la estructura. Todavía no hay pantalla nueva ni RPC de alta/conciliación conectadas a estas tablas. El flujo anterior sigue intacto. No registrar compras reales en estas tablas desde la interfaz hasta completar los servicios y pruebas.

## Interfaz propuesta

Sección «Compras y recepción» con cuatro vistas:
1. Órdenes de compra: estado, proveedor, fecha, solicitado y pendiente.
2. Documentos: facturas/remisiones, fecha, proveedor, valor y estado de conciliación.
3. Recepciones: entregas físicas por fecha, cantidades y novedades.
4. Conciliación: comparativo por línea con acciones explícitas para aceptar, dejar pendiente o rechazar diferencias.

En cada línea mostrar la presentación comercial primero y la equivalencia base como detalle. Ejemplo: «2 cajas (60 unidades)». El costo se captura como aparece en el documento, y el sistema calcula la unidad base.

## Precios y costos: reglas funcionales

Mantener tres valores separados:
1. Costo de compra vigente: valor real pagado al proveedor por la presentación comercial, convertido a unidad base. Se actualiza desde una recepción confirmada, no por una oferta o cotización.
2. Precio habitual del catálogo: precio normal de venta que se propone por defecto en el POS.
3. Precio aplicado a la venta: precio particular cobrado en esa transacción. Un descuento manual en el carrito no debe reescribir el precio habitual del catálogo.

La advertencia existente cuando el precio de venta queda por debajo del costo se conserva sin cambios. El costo debe mostrarse con su unidad clara (por caja/presentación o por unidad base).

La auditoría identificó tres historiales distintos:
- `historial_costos`: costo, proveedor, presentación, origen, referencia y fecha.
- `historial_precios`: la pantalla actual lo usa para cambios del costo de compra.
- `auditoria_precios`: guarda campo, valor anterior/nuevo, usuario, correo, rol y fecha, pero no se encontró una pantalla que lo consulte ni un motivo de cambio.

Pendiente de implementar: una vista única de trazabilidad que permita consultar por producto los cambios del costo de compra y del precio habitual de venta, mostrando fecha, valor anterior, valor nuevo, usuario, origen y motivo cuando exista. No confundir el precio particular de una venta con una modificación del catálogo.

## Escenarios de aceptación obligatorios

1. Orden 5 cajas, factura 5, recepción 5: conciliación completa; ingresan 5 cajas equivalentes al inventario.
2. Orden 5, factura 5, recepción 4: solo 4 ingresan; 1 queda como diferencia/pendiente.
3. Orden 5, factura 5, recepción 3 hoy y 2 después: dos recepciones vinculadas; no duplicar factura ni unidades.
4. Orden 5, factura 6, recepción 6: exceso documentado; requiere autorización antes de ingresar la unidad adicional.
5. Orden 5, factura 5, recepción 5 con precio distinto: advertencia y confirmación de costo antes de actualizar historial.
6. Producto no pedido: registrar novedad y exigir vinculación/autorización antes del ingreso.
7. Producto dañado: registrar recibido/rechazado y no sumar rechazado al inventario.
8. Reintento de confirmación: no duplicar recepción ni movimientos (idempotencia).
9. Presentación de 30 unidades: 2 cajas deben convertirse exactamente a 60 unidades base.
10. Documento sin orden (compra urgente): permitir flujo excepcional con autorización y trazabilidad, sin alterar el cálculo del pedido sugerido.

## Siguientes fases

1. RPC seguras para registrar documentos y relacionarlos con órdenes; sin escritura directa del navegador.
2. RPC de recepción/conciliación versionadas, conservando compatibilidad e idempotencia de la recepción actual.
3. Interfaz de documentos y recepción dentro del módulo actual, sin alterar panel global ni sugerencia de pedidos.
4. Vista de historial de costos/precios y etiquetas inequívocas para caja/unidad.
5. Pruebas de los diez escenarios en QA, inventario/Kardex, historial y regresión del pedido sugerido.

No fusionar ni desplegar en producción hasta aprobación explícita del usuario.


## Avance de implementación (18-11-2026, QA)

- Se creó `preview-compras.html` para revisar la estructura visual en una ruta separada, con datos ilustrativos. No escribe en Supabase ni altera la aplicación operativa.
- En QA se añadieron las RPC `registrar_documento_proveedor` y `registrar_recepcion_compra_documentada`.
- La primera registra cabecera, líneas y relación con la orden; valida proveedor, pertenencia de las líneas, equivalencia de presentación y cantidades/precios no negativos.
- La segunda valida que la recepción corresponda al proveedor y a las líneas documentadas, evita recibir más unidades que las facturadas y delega el movimiento real a `registrar_recepcion_compra`, conservando sus controles de inventario e idempotencia. Después enlaza la recepción al documento.
- Verificación de QA: ambas funciones existen; `authenticated` puede ejecutarlas y `anon` no. Ambas mantienen validación interna de usuario DROSalud. Los avisos generales del asesor de Supabase sobre funciones SECURITY DEFINER incluyen muchas funciones preexistentes; no se han relajado permisos de tablas.
- Pendiente antes de habilitar operación: conectar formularios del módulo real a las RPC, añadir pruebas autenticadas de punta a punta y completar vista de historial de costos/precios. No hay cambios en producción ni en el cálculo del pedido sugerido.


## Implementación conectada en QA (18-11-2026)

La rama ahora contiene una primera versión funcional del módulo, no solo el diseño:

- modules/recepcion-mercancia.js: cuatro vistas dentro del módulo existente: órdenes, documentos, recepciones e historial de costos/precios.
- modules/recepcion-mercancia.css: estilos adaptables a escritorio y móvil, aislados del resto del panel.
- Registro de factura/remisión asociado a una orden, con fecha, número, subtotal, descuentos, impuestos, flete, total y detalle de líneas.
- Recepción por unidades aceptadas. La pantalla calcula el máximo entre lo pendiente de la orden y lo aún no recibido del documento.
- La RPC de recepción enlaza el registro físico al documento y deriva el estado del documento a parcial o conciliado.
- El movimiento de inventario y el historial de costo continúan ejecutándose mediante la RPC original registrar_recepcion_compra; no se creó un inventario paralelo.
- Se añadió auditoria_precios.motivo y la RPC actualizar_precios_drosalud_con_motivo. Los formularios de actualización de costo/precio solicitan el motivo y el historial muestra usuario, fecha, valor anterior y nuevo.
- Los registros de auditoría anteriores no tenían motivo; se muestran como «No indicado», sin inventar una explicación.
- Las funciones nuevas están disponibles para authenticated, no para anon, y validan usuario DROSalud dentro de la función.

### Límites que siguen pendientes antes de habilitar producción

1. La primera versión relaciona cada documento con una orden y con sus líneas. Falta soportar en pantalla una factura que agrupe varias órdenes.
2. Si la factura declara más unidades que la orden, la diferencia se conserva como documento parcial; el exceso no se puede ingresar al inventario hasta autorizar un ajuste de orden.
3. Todavía no se registra por separado mercancía físicamente recibida pero rechazada/dañada, lote o vencimiento. Esas cantidades no deben marcarse como aceptadas.
4. Falta probar con sesión autenticada los escenarios de entrega parcial, reintento, costo diferente, cantidades por presentación y regresión de inventario/Kardex.
5. El historial muestra costo por unidad y por presentación; se debe completar una prueba visual con registros reales para confirmar nombres de producto/proveedor en todas las relaciones.

La vista desplegada en Vercel es un preview de rama. No es producción. No se han creado facturas, recepciones ni movimientos de inventario de prueba. Las tablas nuevas continúan sin documentos de ejemplo.


### Ajustes de seguridad y trazabilidad añadidos después de la primera integración

- Migración 20261118000300: agrega el campo motivo a auditoria_precios y una RPC de actualización que registra el motivo en la misma transacción que el cambio de costo/precio.
- Migración 20261118000500: conserva la posibilidad anterior de dejar vacío el precio de venta habitual desde la ficha del producto.
- Migraciones 20261118000600 y 20261118000700: preservan el reintento idempotente de recepciones documentadas y registran el número de factura/remisión como motivo del cambio de costo generado por la recepción.
- El despliegue de preview utiliza el hostname distinto al dominio de producción; la selección de conexión en index.html dirige esos hostnames al proyecto Supabase QA uorhpljsofnfgzblxcga. Producción sigue conectada al proyecto fwkaqxzdhqpvvjhixeod.
- En QA se verificó que las tablas nuevas de documentos no tienen registros de prueba. La recepción existente que se encontró (REC-5, 12-11-2026) es anterior a estos cambios y no está enlazada a un documento nuevo.
- El último deployment de la rama quedó en estado READY. Esto confirma la publicación estática, no sustituye pruebas de navegador con sesión autenticada.
