# Preparación técnica: conteo físico de inventario

**Estado:** implementación local inicial en revisión; la migración todavía no se ejecutó ni se validó en QA.
**Rama de trabajo:** `feature/conteo-fisico-inventario`.
**Base revisada:** commit `aea4240e61fe7982d6e8392c8705f1e647bc11ef`.

Este documento prepara el trabajo sin conectarse a Supabase. No ejecutar el SQL adjunto ni copiarlo a una base de datos. No se modificaron funciones existentes, roles ni permisos actuales.

La implementación autorizada está separada en `modules/conteo-fisico-api.js` (RPC), `modules/conteo-fisico.js` (interfaz), `modules/conteo-fisico.css` (estilos) y `supabase/migrations/20261119120000_conteo_fisico_inventario.sql` (migración nueva aún no aplicada). `index.html` solo registra la vista, navegación y carga de los módulos.

## 1. Búsqueda de la definición auténtica de `registrar_recepcion_compra`

La definición auténtica **no se recuperó**. Revisé SQL versionado, archivos SQL de QA/producción del repositorio, todas las ramas locales/remotas disponibles y el historial alcanzable con búsqueda por contenido. No aparece un `CREATE FUNCTION` / `CREATE OR REPLACE FUNCTION public.registrar_recepcion_compra(...)` en los archivos, ramas ni commits inspeccionados.

- `modules/ordenes-compra.js:99` invoca la RPC directamente (ruta legacy; no encontré que `index.html` la cargue como módulo activo).
- `modules/recepcion-mercancia.js:166` invoca `registrar_recepcion_compra_documentada`. La versión local más reciente, `supabase/migrations/20261118000700_motivo_costo_recepcion.sql:1-64`, valida usuario, documento/proveedor, orden, líneas, cantidades, presentación, costo e idempotencia; luego delega a `registrar_recepcion_compra` en la línea 63 y enlaza/actualiza el documento. El wrapper no inserta directamente en `inventario_movimientos`.
- `docs/compras-recepcion-erp.md` y `docs/baseline-produccion-transicion-controlada-2026-11-14.md` describen que la función base registra recepciones, movimientos, cantidades recibidas y costos con idempotencia. Son informes del comportamiento observado, **no el cuerpo SQL que podamos revisar ahora**, ni una verificación de QA en esta tarea.

No reconstruyo la función a partir de esos informes. Para cerrar la dependencia, habrá que obtener el artefacto auténtico que la creó o solicitar una exportación de esquema de QA en una etapa autorizada. No se consultó Supabase ni producción.

## 2. Rutas de recepción y relación con Kardex

1. **Recepción manual positiva:** `index.html:1033` y `modules/inventario.js:156` llaman a `registrar_recepcion_inventario`. Su cuerpo está en `supabase/migrations/20261109120000_inventario_movimientos.sql:121-178`: valida usuario Drosalud, producto existente, unidades positivas e identificador de operación; inserta `tipo='recepcion'` y delta positivo en `inventario_movimientos`. La misma clave con los mismos datos devuelve el movimiento existente; con otros datos falla. Un error de la RPC revierte su transacción.
2. **Recepción de compra legacy:** `modules/ordenes-compra.js:99` llama a `registrar_recepcion_compra` con orden, documento, items, clave de operación y notas. No se encontró el cuerpo SQL; no puedo certificar sus escrituras ni detallar sus validaciones internas.
3. **Recepción documentada activa:** `modules/recepcion-mercancia.js:166` llama al wrapper `registrar_recepcion_compra_documentada`. La última versión local delega en el RPC base ausente. Los documentos dicen que el RPC base registra el movimiento; falta demostrarlo en el cuerpo auténtico.

El trigger central `BEFORE INSERT` propuesto cubre con certeza la recepción manual local. Cubrirá las dos rutas de compra si la función base inserta en `inventario_movimientos`, como dice la documentación del proyecto. Esa compatibilidad sigue pendiente de verificar. No se cambian el wrapper ni la RPC base.

## 2. Contradicción de `tipo='ajuste'`

`supabase/migrations/20261109120000_inventario_movimientos.sql:18-21` crea la tabla y la restricción inline, que PostgreSQL nombra normalmente `inventario_movimientos_tipo_check`. La expresión solo permite `venta`, `anulacion` y `recepcion`.

`supabase/migrations/20261117160000_habilitar_fraccionamiento_con_kardex.sql:129-140` intenta insertar `tipo='ajuste'`. No encontré un `ALTER TABLE ... DROP/ADD CONSTRAINT` posterior para esa restricción. La migración `20261110111500_permitir_ajustes_costo_items_kardex.sql` permite cambiar campos de costo de líneas; no habilita un tipo `ajuste`.

La propuesta adjunta reemplaza el `CHECK` para permitir también `ajuste`. Antes de aplicar una versión final se debe comprobar, exclusivamente en QA, el nombre/definición real de la constraint y si hay datos previos incompatibles. No se consultó ningún entorno en esta tarea.

## 3. Arquitectura recomendada

### Sesión por grupo, protección por producto

Una sesión contiene el grupo parcial de productos. Cada línea se activa y se cuenta individualmente: una transacción corta captura el saldo teórico en unidades base, guarda una instantánea de código/presentación y crea la protección persistente. La persona que cuenta no recibe el saldo teórico en la respuesta de su RPC. El saldo vigente que demuestra la migración local es `SUM(inventario_movimientos.unidades_delta)` y la columna `unidades_delta` es `integer`; el snapshot puede ser `bigint`, pero antes de insertar un ajuste hay que rechazar una diferencia fuera del rango entero, sin truncarla ni partirla en varios movimientos.

La protección persiste en una tabla, no en una transacción abierta. Mientras está activa:

- Un nuevo movimiento debe bloquear brevemente la misma fila de `productos` y comprobar la protección.
- Si la línea sigue bloqueada, la operación se rechaza con un error de negocio identificable. No dejar una venta o recepción parcialmente guardada.
- Un trigger `BEFORE INSERT` en `inventario_movimientos` es el punto central propuesto. Cubre los movimientos generados por triggers de venta/anulación y los inserts ejecutados desde RPC, incluida una recepción delegada que escriba en el Kardex.
- Un trigger independiente bloquea cambios de presentación del producto mientras la línea esté protegida. Es necesario porque el fraccionamiento puede cambiar equivalencias aunque el cálculo del ajuste sea cero.

Inicio de línea y escritores toman `productos ... FOR UPDATE` en transacciones breves. Orden requerido para las RPC de conteo: productos por UUID ascendente, cabecera de sesión, línea(s). En una operación sobre una sola línea se sigue ese mismo orden. Si el escritor obtiene primero el bloqueo, el inicio espera a que termine y captura el saldo posterior. Si el inicio obtiene primero el bloqueo, registra la protección y confirma; el escritor continúa después, ve la protección y aborta toda su operación. El saldo de corte queda así definido. El trigger de movimiento toma el lock de producto; esto protege el saldo incluso si la operación ya escribió recibo/recepción en la misma transacción, porque el error revierte toda esa transacción.

El cierre/aprobación bloquea producto, sesión y línea en ese orden, valida estado y autorizador, elimina la protección e inserta el ajuste en la misma transacción. Los escritores que estaban esperando la fila de producto solo continúan después del commit y ven el producto liberado. Si falla el insert, el rollback restaura también la protección. El trigger debe validar movimientos `ajuste` con referencia a una línea de conteo: línea ya marcada aprobada por la RPC, actor autorizado y distinto del contador, mismo producto, delta y clave idempotente. `ajuste` con `referencia_id IS NULL` se conserva para el fraccionamiento existente; no se cambia esa función.

### Lotes y deadlocks

La sesión puede agrupar productos, pero activar una línea a la vez evita mantener bloqueos de fila durante el conteo humano. En operaciones de varios productos, los escritores pueden adquirir varias filas mediante triggers por línea. Si dos transacciones las toman en órdenes opuestos, PostgreSQL puede detectar un deadlock y abortar una de ellas sin confirmar escrituras parciales. Hay que probarlo y mostrar un error reintentable; el trigger por fila no elimina por sí solo todos los deadlocks. También hay que vigilar transacciones que esperan el lock de producto y devolver al cliente un error/reintento útil, sin dejar el conteo en estado parcial.

Si QA demuestra deadlocks operativamente inaceptables, la siguiente decisión es coordinación ordenada de productos por cada writer. Eso podría requerir cambios en RPC actuales y no está incluido ni autorizado aquí. La primera protección debe favorecer integridad transaccional; en el conteo, no abrir simultáneamente protecciones de grupos grandes.

### Inicio simultáneo y sesiones abandonadas

Una PK en `inventario_conteos_bloqueos.producto_id` impide que dos sesiones sean dueñas simultáneas del mismo producto. El comienzo serializa primero la fila del producto y luego inserta la protección; el conflicto devuelve un mensaje de producto ya contado.

Cancelar libera las protecciones de las líneas no aprobadas dentro de una transacción y deja auditoría. No liberar por un timeout silencioso: una sesión abandonada debe quedar visible y requerir cancelación administrativa con motivo. Un ajuste ya aprobado no se borra; una corrección posterior sería otro movimiento autorizado.

## 4. Modelo de datos propuesto

La migración nueva contiene el esquema, los triggers y RPC con cuerpos SQL. Sigue siendo código no probado: no se ejecutó, no se aplicó a Supabase y requiere revisar contra el baseline de QA antes de ejecutarse.

- `inventario_conteos`: sesión, alcance, estado y autoría.
- `inventario_conteos_items`: producto, unidad base, snapshot de código/presentación, saldo de corte, cantidad consensuada, diferencia final, aprobación y estado.
- `inventario_conteo_capturas`: evidencia inmutable de cada conteo/reconteo: cantidad base, secuencia, usuario, fecha, motivo y clave idempotente. Permite auditoría sin sobrescribir la primera captura.
- `inventario_conteos_bloqueos`: una fila por producto protegido, FK a la sesión/línea y fecha de activación. PK por producto impide doble sesión activa.
- `inventario_conteo_permisos`: capacidades explícitas de contar/aprobar para usuarios habilitados, sin ampliar el `CHECK` actual de `usuarios_drosalud.rol` (`admin`, `vendedor`). El admin conserva autoridad.
- `inventario_movimientos`: se agrega el tipo `ajuste`; `referencia_id` apunta a la línea de conteo y `operacion_id` identifica la aprobación.

Todas las cantidades del saldo, conteo y ajuste se guardan en unidades base. La instantánea de presentación permite explicar qué unidad se usó aunque el catálogo cambie después. Para contar fraccionables, la interfaz puede aceptar cajas y sueltas, pero convierte y valida un entero de unidades base.

Se propone una clave única de ajuste por línea y un identificador idempotente. La aprobación requiere un usuario distinto de **todos** los contadores. Las capturas son inmutables; cada reconteo agrega evidencia en vez de sobrescribirla.

### Regla de segundo conteo y desacuerdo

- Si el primer conteo coincide con el saldo del Kardex, no hay diferencia y no se exige reconteo; se puede enviar a aprobación/cierre sin movimiento.
- Toda diferencia positiva o negativa exige un segundo conteo antes de aprobar el ajuste. Lo realiza otra persona, sin ver saldo teórico, cantidad anterior ni delta.
- Si dos capturas independientes coinciden, esa cantidad consensuada se compara con el saldo de corte y pasa a aprobación. No se promedian unidades.
- Si difieren, el producto permanece protegido y otra persona que aún no lo haya contado hace un nuevo conteo ciego. Se conserva cada intento. Hay consenso cuando la misma cantidad aparece en dos capturas independientes; la revisión autorizada muestra cantidades y autores.
- Sin consenso operativo, el administrador cancela con motivo y el producto se libera sin ajuste. Se puede iniciar otra sesión; una discrepancia irresuelta nunca se convierte en movimiento.
- El aprobador debe ser distinto de todos los contadores. No hay límite automático ni vencimiento que libere en silencio; las sesiones atascadas requieren cancelación administrativa auditada.

La regla se aplica a cualquier diferencia, sin umbral de unidades o valor, para que sea sencilla de operar y auditar.

## 5. Permisos y RLS

Las tablas nuevas deben tener RLS habilitado y sin escritura directa desde `anon` o `authenticated`. La interfaz consume RPC específicas con `EXECUTE` revocado a `PUBLIC`/`anon` y concedido únicamente a `authenticated`; cada función valida `auth.uid()`, usuario activo y capacidad específica. Las funciones privilegiadas usarán `search_path` fijo y nombres de tabla calificados.

La autorización del encargado se modela como capacidad de conteo, no como un nuevo rol global ni como cambio a los permisos del vendedor. La lectura de conteo debe separarse: RPC de contador sin saldo teórico, y RPC de revisión/aprobación que sí devuelve el saldo, protegida por capacidad.

## 6. RPC necesarias antes de construir la interfaz

1. `crear_conteo_inventario(product_ids, motivo, solicitud_id)`: admin/usuario autorizado; valida productos y lista única. Reintento igual devuelve la misma sesión; misma clave con datos distintos falla.
2. `iniciar_linea_conteo(item_id, solicitud_id)`: serializa por producto, captura SUM del Kardex y snapshot, registra bloqueo y devuelve datos ciegos. Orden de locks: producto, sesión, línea.
3. `guardar_conteo_fisico(item_id, cantidad_base, solicitud_id)`: solo contador asignado; captura inicial idempotente y ciega.
4. `enviar_linea_conteo_a_revision(item_id, solicitud_id)`: compara internamente primera captura con corte; cero queda sin ajuste, diferencia pasa a reconteo obligatorio.
5. `registrar_reconteo_fisico(item_id, cantidad_base, solicitud_id, motivo)`: nuevo contador independiente, pantalla ciega, captura inmutable. Si dos conteos concuerdan, pasa a revisión; si no, solicita otro reconteo.
6. `consultar_conteo_contador` y `consultar_conteo_revision`: rutas separadas; contador no obtiene saldo/delta ni capturas anteriores, aprobador autorizado sí obtiene historial y consenso.
7. `aprobar_linea_conteo(item_id, solicitud_id, motivo)`: admin o aprobador autorizado distinto de todos los contadores; ajuste único por línea/operación, cero sin movimiento y libera atómicamente.
8. `cancelar_conteo_inventario(id, solicitud_id, motivo)`: solo admin en v1; libera no aprobadas con auditoría. Las aprobadas y movimientos permanecen.
9. `gestionar_permiso_conteo(user_id, puede_contar, puede_aprobar)`: solo admin; conserva historial y no cambia el rol general.

No había RPC de conteo existente que reutilizar. La implementación nueva usa el modelo de movimientos y las funciones de identidad actuales; conserva la RPC de recepción como dependencia sin reemplazarla ni asumir su código.

## 7. Plan por etapas

1. **Recuperar la fuente de recepción y cerrar cobertura.** Obtener el artefacto auténtico de `registrar_recepcion_compra` o, con autorización posterior, su definición desde QA. Confirmar inserts en `inventario_movimientos`, tablas tocadas e idempotencia. No tocar producción.
2. **Cerrar migración base.** Corregir constraint; crear tablas, RLS, índices, guard de movimientos y guard de cambios de presentación. Revisar permisos y deadlocks antes de integrar UI.
3. **Implementar RPC y políticas de autorización.** Inicio, primera captura, envío a revisión, reconteos ciegos con consenso, lecturas separadas, aprobación, cancelación e idempotencia; habilitar capacidades por asignación explícita.
4. **Interfaz iPhone/escritorio.** Búsqueda/escaneo, grupo parcial, captura numérica ciega, revisión, segundo conteo, aprobación y estado de bloqueos. Sin acceso directo de escritura a tablas.
5. **Aceptación operativa en QA.** Matriz de pruebas de la sección siguiente; revisión de saldos antes/después y comparación de historial. No promover sin aprobación independiente.

## 8. Matriz mínima de pruebas QA

| Escenario | Resultado esperado |
|---|---|
| Diferencia negativa, positiva y cero | Delta correcto; cero no inserta movimiento; movimientos previos intactos. |
| Reintento de crear/guardar/enviar/recontar/aprobar/cancelar | Una sola operación; clave igual con payload diferente se rechaza. |
| Contador intenta aprobar su línea | Rechazo; sesión y protección permanecen pendientes. |
| Dos sesiones activan el mismo producto | Una gana; la otra recibe conflicto sin duplicar línea activa. |
| Venta iniciada antes de activar | El conteo espera; snapshot incluye la venta confirmada. |
| Venta y anulación durante bloqueo | No se confirma ninguna escritura de recibo/Kardex parcial. |
| Recepción documentada y manual durante bloqueo | No quedan recepciones, costos ni movimientos parciales. |
| Fraccionamiento durante bloqueo | No cambia equivalencia ni genera ajuste. |
| Cancelación y abandono | Cancelar libera sin movimiento; abandonada requiere resolución auditada. |
| Error en aprobación | Rollback conjunto: sin movimiento huérfano ni liberación prematura. |
| Varias líneas concurrentes | Cualquier deadlock aborta una operación completa; reintento no duplica. |
| Presentaciones | Caja + sueltas dan el mismo total base; snapshot conserva factor/código. |
| Usuario sin capacidad / vendedor | RPC denegada; no se amplía acceso general del vendedor. |
| Escritura directa a tablas nuevas | Denegada por grants/RLS. |
| Diferencia fuera de rango de `integer` | Aprobación rechazada sin truncar, liberar el producto ni insertar movimiento. |
| Conteo inicial distinto del saldo teórico | Reconteo obligatorio; la línea todavía no puede aprobarse. |
| Dos conteos independientes iguales | Se confirma cantidad y pasa a revisión; delta se calcula frente al saldo de corte. |
| Primer y segundo conteo distintos | Se guardan ambos; otro contador distinto realiza conteo ciego. Ningún ajuste hasta consenso de dos. |
| Aprobador participó en cualquier conteo | RPC denegada aunque sea admin; debe ser independiente de todos los contadores. |
| Permiso revocado durante conteo | La acción siguiente revalida permiso; línea no se libera por revocación y requiere admin/cancelación auditada. |
| Llamada RPC con SECURITY DEFINER | `PUBLIC`/`anon` no pueden ejecutarla; usuario no autorizado no ve campos de revisión ni puede cambiar estados. |

Evidencia por caso: respuesta RPC, filas de sesión/línea/bloqueo, movimientos antes/después, saldo agregado recalculado y ausencia de escrituras parciales. Ejecutar todo con productos de prueba dentro de una transacción/dataset aislado en QA.

## 9. Pendientes y límites

- No se pudo generar una migración con `supabase migration new`: el CLI no está instalado. Por eso el SQL está en `docs/propuestas/`, fuera del directorio de migraciones ejecutables.
- Los cuerpos RPC ya están escritos en la migración local, pero aún no han sido validados por el motor. Falta ejecutar pruebas en QA, revisar grants/roles efectivos y demostrar la reacción del trigger en cada flujo.
- Falta recuperar el cuerpo de `registrar_recepcion_compra` y demostrar la cobertura Kardex de la compra. La recepción manual sí está demostrada por la migración local; el wrapper de compra delega a la RPC ausente.
- La regla de reconteo ya está definida: toda diferencia requiere dos capturas iguales de personas distintas; desacuerdo sigue con otro contador; sin consenso se cancela sin ajuste. Falta definir en la interfaz quién asigna contadores y las alertas operativas para bloqueos prolongados.
- El guard central solo intercepta `INSERT` a `inventario_movimientos`, que es la ruta de escritura encontrada en las migraciones revisadas. No impide por sí solo `UPDATE`/`DELETE` ejecutados por roles privilegiados fuera de esas rutas; QA debe confirmar permisos y buscar escrituras adicionales antes de cerrar ese riesgo.
- La primera pantalla y el módulo RPC están construidos en la rama, pero no se deben considerar terminados ni listos para operación. La migración no está lista para aplicarse sin revisión SQL y QA. La prueba integrada de compra además depende de recuperar `registrar_recepcion_compra` y confirmar su ruta de Kardex. Antes de QA funcional deben revisarse constraints, grants/RLS, concurrencia y los casos de reconteo.
- No se ejecutaron SQL ni pruebas. Tampoco se consultó Supabase.

## Referencias técnicas

- [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security) — habilitar RLS en tablas expuestas y conceder solo los accesos requeridos.
- [Supabase: Database Functions](https://supabase.com/docs/guides/database/functions) — funciones SQL, `SECURITY DEFINER` y permisos.
- [Supabase Changelog](https://supabase.com/changelog) — consultado para revisar cambios recientes de CLI; no se encontró uno relevante a este diseño SQL.
