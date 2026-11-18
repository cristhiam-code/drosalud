# Diseño funcional — Compras y recepción profesional

Estado: propuesta técnica para revisión. Esta especificación NO modifica datos existentes ni habilita cambios en producción.

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

## Cambios necesarios identificados en el esquema actual

El esquema actual tiene `ordenes_compra`, `ordenes_compra_items`, `recepciones_compra` y `recepciones_compra_items`. La recepción actual guarda un único `documento_proveedor`, fecha de recepción y líneas con unidades/costo por unidad base; no separa tipo/fecha/valores del documento ni cantidades documentadas y físicamente aceptadas.

La evolución debe ser aditiva y compatible:
- Crear cabecera de documentos de proveedor.
- Crear líneas de documentos de proveedor.
- Relacionar documentos con órdenes sin asumir relación 1:1.
- Relacionar una o varias recepciones con el documento correspondiente.
- Ampliar las líneas de recepción para conservar cantidad recibida, aceptada y rechazada, presentación y equivalencia histórica.
- Añadir estados/diferencias auditables y usuario/fecha de autorización.
- Mantener las tablas actuales y sus datos históricos; no renombrar ni eliminar columnas en la primera etapa.

No ejecutar DDL hasta revisar las funciones RPC, triggers, RLS, grants, vistas y dependencias del esquema completo. La nueva superficie pública debe tener RLS y permisos mínimos, siguiendo las políticas/roles existentes de DROSalud; no crear políticas genéricas para todos los usuarios.

## Interfaz propuesta

Sección «Compras y recepción» con cuatro vistas:
1. Órdenes de compra: estado, proveedor, fecha, solicitado y pendiente.
2. Documentos: facturas/remisiones, fecha, proveedor, valor y estado de conciliación.
3. Recepciones: entregas físicas por fecha, cantidades y novedades.
4. Conciliación: comparativo por línea con acciones explícitas para aceptar, dejar pendiente o rechazar diferencias.

En cada línea mostrar la presentación comercial primero y la equivalencia base como detalle. Ejemplo: «2 cajas (60 unidades)». El costo se captura como aparece en el documento, y el sistema calcula la unidad base.

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

## Plan de implementación

Fase 1 — Esquema aditivo y seguro:
- Revisar RPC, triggers, RLS, grants, dependencias y restricciones actuales.
- Preparar migración versionada y reversible cuando sea posible.
- Probar en proyecto/entorno QA; no aplicar a producción.

Fase 2 — Servicios y validaciones:
- Crear RPC transaccionales para documento, recepción y conciliación.
- Evitar que el cliente escriba directamente movimientos de inventario.
- Mantener idempotencia, validaciones de proveedor/orden/producto y permisos.

Fase 3 — Interfaz:
- Implementar la experiencia de cuatro vistas dentro del módulo actual, preservando estilos y responsive existentes.
- Mostrar errores claros y evitar doble envío.

Fase 4 — Pruebas:
- Ejecutar los 10 escenarios anteriores en QA y comprobar órdenes, documentos, recepciones, inventario, Kardex e historial de costos.
- Verificar explícitamente que el código de pedido sugerido no cambió.

Fase 5 — Revisión:
- Abrir PR para revisión.
- No fusionar ni desplegar en producción hasta aprobación explícita del usuario.

## Fuera de alcance de esta primera entrega

- Cambios al algoritmo de pedido sugerido.
- Cambios al POS, caja, roles/permisos o panel global.
- Contabilidad/cuentas por pagar completa.
- Integración automática con DIAN o lectura OCR de facturas.
- Costeo fiscal/contable avanzado sin definir antes el tratamiento de impuestos y fletes.
