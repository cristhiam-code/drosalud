# Baseline real de producción y transición controlada — 14/11/2026

## Alcance y seguridad

Inspección de solo lectura contra:
- Producción: proyecto Supabase `fwkaqxzdhqpvvjhixeod`.
- QA: proyecto Supabase `uorhpljsofnfgzblxcga`.

No se ejecutaron escrituras, migraciones, cambios de permisos ni modificaciones de datos en producción. Este documento registra el estado observado el 14/11/2026; los conteos pueden cambiar con la operación.

**Regla de salida:** producción continúa siendo el entorno operativo. QA sirve para validar cambios. No copiar la base QA sobre producción ni ejecutar `supabase db push` hasta reconciliar el historial.

## 1. Estado comprobado de producción

### Historial de migraciones

- Producción tiene **32 versiones** registradas.
- Última versión: `20261112223131_compras_rls_rpc`.
- El repositorio no contiene el SQL original de varias migraciones históricas. Entre las ausentes comprobadas están:

```text
20261104022228_secure_seller_prices_and_logout_support
20261104024606_show_purchase_cost_to_sellers
20261104111355_vendedor_precios_ventas_ajustes
20261105040107_endurecer_permisos_vistas_app
20261105100135_fase3_exigir_aal2_admin
20261105100828_limpieza_permisos_productos
20261105102957_ley1581_consentimientos_y_anonimizar
20261105220905_anonimizar_exigir_aal2
20261106034002_cierre_caja_jornada
20261106215856_historial_cierres_caja
20261108201313_enable_realtime_for_drosalud_sync
20261112214210_guardar_compra_pendiente_v2
20261112223125_guardar_compra_pendiente_v4
20261112223131_compras_rls_rpc
```

No reconstruir el historial con archivos vacíos ni marcar migraciones como aplicadas solo para silenciar diferencias. El esquema real debe ser la fuente de verdad para reconstruir el baseline.

### Datos observados

| Objeto | Registros en producción |
|---|---:|
| productos | 1.189 |
| proveedores | 2 |
| inventario_movimientos | 54 |
| compras_pendientes | 0 |
| ordenes_compra | 0 |
| ordenes_compra_items | 0 |
| recepciones_compra | 0 |
| recepciones_compra_items | 0 |

Estos conteos son una fotografía del momento, no valores que deban copiarse a QA ni modificarse.

### Estructura de Compras e Inventario

Producción ya contiene:
- `compras_pendientes` (15 columnas).
- `cotizaciones_proveedor` (8 columnas; `compra_id` es NOT NULL).
- `ordenes_compra` (9 columnas).
- `ordenes_compra_items` (7 columnas).
- `recepciones_compra` (10 columnas).
- `recepciones_compra_items` (7 columnas).
- `inventario_movimientos` (12 columnas).
- `inventario_saldos` (vista/objeto de consulta, no se debe tratar como tabla transaccional).
- `productos` (11 columnas) y `proveedores` (11 columnas).

Las tablas operativas de compras, proveedores, productos y movimientos consultadas tienen RLS habilitado. Se verificaron políticas para lectura del equipo y restricciones administrativas. No se modificó ninguna política.

### Funciones activas de producción

Firmas observadas:
- `registrar_recepcion_compra(uuid,text,jsonb,uuid,text)`
- `crear_orden_compra(uuid,jsonb,text,text)`
- `aprobar_orden_compra(uuid)`
- `guardar_compra_pendiente(...)`
- `guardar_compra_con_costo_real(...)`
- `registrar_recepcion_inventario(uuid,integer,text,uuid)`

Las funciones de recepción y las de creación/aprobación de órdenes son `SECURITY DEFINER` y tienen `search_path` vacío. No se tocaron.

## 2. Diferencias reales entre producción y QA

QA tiene **45 versiones** de migración, frente a las 32 de producción. Incluye migraciones de reconstrucción/semilla del entorno de pruebas, correcciones QA y Pedidos. Por eso los historiales no son comparables como si fueran dos copias idénticas.

### Diferencias de esquema vinculadas a Pedidos

| Objeto | Producción | QA |
|---|---|---|
| `pedidos` | No existe | Existe |
| `pedidos_items` | No existe | Existe |
| `pedidos_resumen` | No existe | Existe |
| `ordenes_compra` | 9 columnas | 12 columnas |
| `ordenes_compra_items` | 7 columnas | 8 columnas |
| `cotizaciones_proveedor` | 8 columnas | 9 columnas |

Columnas adicionales de QA:
- `ordenes_compra.pedido_id`
- `ordenes_compra.operacion_id`
- `ordenes_compra.request_hash`
- `ordenes_compra_items.pedido_item_id`
- `cotizaciones_proveedor.pedido_item_id`

Además, en QA `cotizaciones_proveedor.compra_id` acepta NULL para permitir que una cotización se vincule a una línea de Pedido; en producción es NOT NULL. La migración de avance debe cambiar esto con una restricción de origen exclusivo: una cotización debe pertenecer a una compra pendiente o a una línea de pedido, nunca a ambas.

### Diferencias de comportamiento que no deben pasar inadvertidas

Las firmas de `crear_orden_compra` y `aprobar_orden_compra` son iguales, pero sus reglas no:

- Producción permite esas acciones a un usuario activo del equipo mediante `es_usuario_drosalud()`.
- QA exige administrador mediante `es_admin_drosalud()`.

La migración consolidada actual de Pedidos instala la regla más restrictiva. **No se debe llevar ese cambio automáticamente a producción**: primero hay que decidir y probar el impacto sobre el flujo de Compras que ya está en operación. Para preservar la operatividad actual, la migración de Pedidos debe separar sus permisos nuevos (autorizar/rechazar Pedidos y generar órdenes desde Pedidos, solo administrador) de los permisos existentes de órdenes independientes.

`registrar_recepcion_compra` existe en ambos entornos con la misma firma y el mismo flujo funcional general: valida la orden y las cantidades, evita repetir la operación, registra recepción y movimiento de inventario, actualiza cantidades recibidas y costo del producto, y conserva historial de costos. Sin embargo, el texto/huella de la función difiere entre entornos. No declarar equivalencia byte a byte; conservar la definición productiva hasta una revisión comparativa y una prueba de regresión.

### Seguridad de Pedidos en QA

QA tiene RLS habilitado en `pedidos` y `pedidos_items`, políticas de lectura para usuarios autenticados del equipo y RPC para escrituras. Las funciones de Pedidos observadas son:
- `guardar_pedido(uuid,text,text,jsonb)`
- `enviar_pedido(uuid)`
- `autorizar_pedido(uuid,jsonb)`
- `rechazar_pedido(uuid,text)`
- `generar_ordenes_compra_pedido(uuid,jsonb,uuid)`

Producción no tiene estas tablas, vista ni funciones.

## 3. Estrategia de transición sin interrumpir producción

### Fase A — Congelar y documentar baseline (actual)

1. Conservar este inventario de producción y la lista de migraciones.
2. Recuperar del esquema real las definiciones completas de tablas, vistas, funciones, triggers, índices, constraints, grants y policies de las migraciones históricas ausentes.
3. No ejecutar escrituras ni migraciones en producción durante esta fase.

### Fase B — Preparar migración aditiva

Preparar una migración específica de avance, posterior a `20261112223131`, que:
1. Cree `pedidos` y `pedidos_items`, índices, constraints, vista resumen, RLS, políticas y RPC.
2. Añada las columnas de enlace/idempotencia a órdenes y cotizaciones.
3. Haga `cotizaciones_proveedor.compra_id` nullable y aplique la regla de origen exclusivo, después de comprobar los datos existentes.
4. Mantenga intactas las definiciones y permisos productivos de `registrar_recepcion_compra`, `crear_orden_compra` y `aprobar_orden_compra`, salvo cambio aprobado y probado por separado.
5. No modifique productos, existencias, Kardex, ventas, caja ni datos históricos.
6. Use funciones nuevas de Pedidos para exigir administrador en autorización, rechazo y generación de órdenes desde un Pedido.

La migración consolidada actual es una base de trabajo, no una autorización para producción: debe revisarse para separar los cambios de permisos de órdenes independientes descritos arriba.

### Fase C — Validación en QA

1. Ajustar QA para que el flujo existente de Compras siga siendo compatible con la política de producción, salvo que se apruebe explícitamente cambiarla.
2. Ejecutar pruebas de regresión de Compras: crear orden independiente, aprobarla, recepción parcial y completa, reintento idempotente, actualización de costo y Kardex.
3. Ejecutar pruebas de Pedidos: borrador, envío por vendedor, autorización/rechazo por administrador, asignación de una línea a varios proveedores, generación idempotente y recepción.
4. Verificar roles con cuentas reales de prueba (administrador y vendedor) desde navegador; las pruebas SQL transaccionales no sustituyen E2E.
5. Comparar otra vez esquema, funciones, policies, grants e índices entre QA y el baseline productivo esperado.

### Fase D — Publicación controlada (no ejecutada)

Solo con aprobación explícita:
1. Crear punto de restauración/backup y verificar recuperación.
2. Aplicar únicamente la migración aditiva revisada, nunca un `db push` global mientras falten migraciones históricas.
3. Verificar los objetos y permisos inmediatamente después.
4. Publicar el frontend después de que el esquema esté listo, para evitar que la interfaz invoque RPC aún inexistentes.
5. Ejecutar smoke tests de inicio de sesión, venta, caja, consulta de inventario, compras y recepción.
6. Confirmar que los datos previos siguen intactos y que los flujos actuales siguen funcionando.

## 4. Decisiones técnicas

- No igualar los historiales de migración mediante renombres artificiales ni migraciones vacías.
- No restaurar QA sobre producción ni copiar datos de prueba.
- No desplegar la migración consolidada actual sin revisar la restricción de permisos de órdenes independientes.
- No desplegar el frontend de Pedidos antes de tener las funciones y tablas disponibles en el entorno correspondiente.
- Mantener producción como fuente de verdad para los flujos actualmente operativos; QA debe probar la transición sin introducir cambios funcionales no solicitados.

## Estado al cierre

- Reconstrucción inicial del baseline productivo: **hecha mediante consultas de solo lectura**.
- Diferencias críticas entre producción y QA: **identificadas**.
- Cambios en producción: **ninguno**.
- Migración lista para producción: **pendiente de ajuste y regresión**.
- Publicación: **no autorizada ni ejecutada**.


## 5. Alineación aplicada en QA después del baseline

Para evitar que el entorno de pruebas cambie el comportamiento de Compras que hoy existe en producción, se aplicó únicamente en QA la migración:

`20261114183822_qa_restore_production_purchase_rpc_behavior`

Archivo versionado:
`supabase/migrations/20261114183822_qa_restore_production_purchase_rpc_behavior.sql`

La migración restaura en QA las definiciones productivas exactas de:
- `crear_orden_compra`
- `aprobar_orden_compra`
- `registrar_recepcion_compra`

Verificación posterior: las tres funciones tienen la misma huella MD5 de `pg_get_functiondef` en ambos proyectos y conservan los mismos permisos (`authenticated` sí; `anon` y `PUBLIC` no).

Prueba transaccional QA (revertida al finalizar):
- Un usuario simulado como vendedor pudo crear y aprobar una orden independiente, igual que permite producción.
- Ese vendedor pudo crear y enviar un Pedido.
- El mismo vendedor recibió denegación al intentar autorizar el Pedido; esa acción continúa reservada al administrador.
- La prueba se ejecutó dentro de un bloque transaccional que revirtió la orden, el pedido y el cambio temporal de rol.

Después de la prueba, QA mantuvo sus conteos previos: 0 pedidos, 2 órdenes, 1 recepción y 11 movimientos de inventario. Producción no recibió cambios.

## 6. Ajustes en el código candidato para conservar Compras

En la rama `release/qa-candidate-2026-11-14`:
- Se retiró la restricción visual `data-admin-only` del botón de creación de órdenes independientes.
- Se retiraron los bloqueos de rol de la creación y aprobación de órdenes independientes en el código activo de `index.html` y en la copia de `modules/ordenes-compra.js`.
- La migración consolidada de Pedidos ya no reemplaza las funciones productivas `crear_orden_compra` ni `aprobar_orden_compra`; conserva sus permisos actuales.
- La autorización/rechazo de Pedidos y la generación de órdenes desde Pedidos siguen siendo operaciones exclusivas del administrador.

Estos cambios preservan el flujo de Compras existente y separan sus permisos de las nuevas reglas del módulo Pedidos. No se desplegó a producción.
