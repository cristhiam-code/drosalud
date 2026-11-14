# Reconciliación de migraciones de Pedidos — 14/11/2026

## Estado comprobado

No ejecutar todavía las tres migraciones de Pedidos tal como están en esta rama.

| Entorno | Últimas versiones relevantes | Estado de Pedidos |
|---|---|---|
| Producción | `20261112223131 compras_rls_rpc` | No existen `pedidos`, `pedidos_items` ni RPC de Pedidos |
| QA | `20261112223020 guardar_compra_pendiente_v4`, luego `20261113020211`, `20261113020736`, `20261113020840` | Pedidos y sus RPC existen |

Las tres migraciones de Pedidos versionadas en Git usan otros identificadores:
- `20261112210000_create_pedidos_module.sql`
- `20261112220000_link_products_on_pedido_authorization.sql`
- `20261112223000_add_order_generation_idempotency.sql`

Por tanto, los identificadores registrados en QA no corresponden con los nombres/fechas de los archivos versionados. Además, producción ya tiene una migración posterior a la fecha de la primera migración Pedidos. No se debe confiar en un `db push` directo ni en reparar el historial para marcar como aplicadas migraciones cuyo esquema todavía no existe en producción.

## Ruta segura de publicación

1. Preparar una nueva migración de avance, con versión posterior a `20261112223131`, que deje el esquema Pedidos completo en producción.
2. Hacer que esa migración sea idempotente respecto a QA: tablas, columnas, índices, constraints y políticas deben comprobar existencia; funciones y vistas deben quedar en la definición final de esta rama.
3. Antes de ejecutar, comparar en QA y producción las columnas, constraints, índices, policies, grants y firmas de funciones de compras/recepción.
4. Aplicar únicamente en QA; verificar que los objetos y las firmas finales coincidan con el código.
5. Probar el flujo completo en QA con una cuenta administradora y otra de vendedor. Solo después de aprobación explícita se planifica producción.

No usar `migration repair` para ocultar diferencias de esquema. No renombrar archivos históricos para que parezcan aplicados.

## Compatibilidad de compras y recepción

- `registrar_recepcion_compra` ya existe tanto en QA como en producción.
- La función acepta órdenes en estado `aprobada` o `parcial`, valida cantidades/costos, registra recepción, genera movimiento de inventario, actualiza costo del producto y conserva historial de costos.
- La función comprueba `es_usuario_drosalud()`, no `es_admin_drosalud()`. La ejecución está concedida a `authenticated` y no a `anon`; la autorización real se valida dentro de la función. Esto permite recepción a usuarios activos del equipo, no solo al administrador.
- En cambio, autorizar/rechazar Pedidos y generar órdenes desde Pedidos exige administrador.
- La migración de Pedidos también cambia `crear_orden_compra` y `aprobar_orden_compra` para exigir administrador. Es un cambio de permisos respecto a producción y debe incluirse en la prueba de regresión de Compras.

## Idempotencia y reintentos

- La migración final define `generar_ordenes_compra_pedido(uuid,jsonb,uuid)`.
- La interfaz envía `p_operacion_id`; la firma y el nombre del parámetro coinciden.
- La función bloquea la fila del pedido, verifica autorización, controla las unidades ya asignadas y devuelve las órdenes existentes cuando se repite la misma operación con el mismo contenido.
- La interfaz conserva el identificador de operación durante un reintento en la misma sesión. Se reforzó el envío de pedidos para consultar el estado en servidor cuando la respuesta del envío es ambigua, evitando duplicar borradores o mostrar como fallido un envío que sí quedó registrado.

## Validaciones realizadas

- Se creó una migración consolidada e idempotente: `20261114182004_pedidos_release_consolidated_20261114.sql`.
- Se aplicó únicamente en QA. Supabase registró la versión `20261114182004`, con el mismo nombre que el archivo versionado; así no queda una segunda migración pendiente con otra fecha.
- El despliegue de vista previa de la rama terminó en estado `READY`. La página principal responde HTTP 200 y entrega el HTML candidato; `modules/pedidos.js` y `modules/pedidos.css` se sirven correctamente.
- Prueba transaccional en QA, revertida al terminar: crear pedido urgente, enviarlo, autorizarlo, dividir una misma línea entre dos proveedores, generar dos órdenes, repetir la misma operación y recibir parcialmente una orden. La repetición devolvió la operación existente; no creó órdenes duplicadas.
- Prueba transaccional de roles, también revertida: un vendedor puede crear/enviar pedidos y registrar recepción; no puede autorizar/rechazar pedidos, crear/aprobar órdenes independientes ni generar órdenes desde Pedidos.
- Después de ambas pruebas, QA conservó los mismos datos operativos: 0 pedidos de prueba, 2 órdenes, 1 recepción y 11 movimientos; el proveedor temporal no existe y el usuario QA volvió a rol administrador.
- Los RPC de Pedidos y Compras tienen ejecución para `authenticated`, no para `anon`. El asesor de seguridad conserva 28 avisos de funciones SECURITY DEFINER autenticadas y 1 aviso de protección de contraseñas filtradas; son avisos del proyecto QA, no se intentó ocultarlos ni revocar funciones usadas por la app.
- Estas son pruebas transaccionales directas contra funciones SQL y validación de vista previa, no una prueba E2E visual desde navegador autenticado.
- No se aplicó ninguna migración ni se modificó ningún dato en producción.

## Bloqueo de salida

La rama no está lista para fusionarse a `main` hasta que exista la migración de avance reconciliada, se aplique y valide en QA y se completen las pruebas de roles y operación real.
