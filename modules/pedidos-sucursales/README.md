# Pedidos de Sucursales

Módulo independiente para el abastecimiento y traslado de inventario entre la bodega central y las sucursales.

## Menú funcional

1. **Pedido sugerido**: propuesta calculada con ventas de los últimos siete días, saldo real de la sucursal y cantidades pendientes de recibir. Se recalcula al abrir y al pulsar Recalcular. El usuario revisa y envía; nunca se autoriza automáticamente.
2. **Pedido urgente de productos en negativo**: disponible cualquier día. El servidor valida que cada producto tenga saldo menor que cero en la bodega de la sucursal.
3. **Pedidos autorizados**: solicitudes aprobadas por administración, cantidades autorizadas y estado de preparación/despacho.
4. **Lista de pedidos realizados y enviados**: historial de la sucursal y trazabilidad hasta la recepción.

## Separación de responsabilidades

Este módulo NO reutiliza ni modifica `modules/pedidos.js`. Ese archivo sigue gestionando solicitudes de compra a proveedores. Este módulo gestiona transferencias internas entre bodegas.

## Estructura prevista

- `api.js`: único punto de acceso a RPC y consultas del módulo.
- `index.js`: inicialización, estado y navegación interna.
- `pedido-sugerido.js`: cálculo mostrado, edición de cantidades y envío.
- `pedido-urgente.js`: selección exclusiva de productos en negativo.
- `pedidos-autorizados.js`: bandeja de autorizaciones y preparación.
- `historial.js`: lista y seguimiento de pedidos.
- `despachos.js`: despacho central y confirmación de recepción.
- `styles.css`: estilos aislados con prefijo `ps-`.

## Reglas no negociables

- Las reglas de día habilitado, inventario negativo, permisos, autorización, despacho y recepción se validan en PostgreSQL; la interfaz solo guía al usuario.
- Una solicitud tiene un único registro y cambia de estado: Pendiente → En revisión → Aprobado o Rechazado → En preparación → Despachado → Recibido (o Parcial). Las pantallas consultan el mismo pedido; no duplican registros.
- El despacho descuenta del inventario de la bodega central. La recepción acredita únicamente las unidades confirmadas por la sucursal.
- Los movimientos deben ser idempotentes y auditables.
- No se altera el módulo de compras a proveedores, Ventas ni Caja.
- El primer desarrollo y sus pruebas se realizan exclusivamente en QA.

## Persistencia y sincronización

- El inventario de la bodega central se inicializa desde el Kardex existente, conservando cada movimiento histórico y su fecha. El saldo de apertura se reconcilia contra el inventario general.
- Las ventas y anulaciones nuevas se reflejan en el libro de movimientos de la bodega correspondiente mediante un trigger.
- El pedido sugerido toma la venta neta de anulaciones de los últimos siete días, resta el saldo actual y las unidades pendientes de recibir.
- Los despachos descuentan de la bodega central; la recepción acredita únicamente las unidades confirmadas en la sucursal.
- Los envíos, despachos y recepciones usan identificadores de operación para evitar duplicados por doble clic o reintentos de red.
- Las tablas tienen RLS. El cliente solo tiene permiso de lectura directa; las escrituras pasan por funciones que comprueban usuario, sucursal, rol y estado.

## Preparación administrativa

La administración puede crear una sucursal y su bodega, asignar un usuario activo y habilitar los días del Pedido Sugerido desde el botón **Configurar sucursales** del encabezado. La bodega central se crea como origen de despachos. No se inventan sucursales de negocio: deben registrarse con sus nombres reales.

## Validaciones probadas en QA

- Pedido urgente permitido con saldo negativo, incluso con días normales deshabilitados.
- Pedido urgente rechazado cuando el saldo es cero o positivo.
- Pedido sugerido bloqueado fuera del día configurado con el mensaje solicitado.
- Cálculo sugerido con ventas netas, inventario y pedidos pendientes.
- Autorización administrativa y rechazo de permisos a vendedor.
- Despacho desde central, recepción en sucursal y cambio de estado a recibido.
- Reintento del mismo pedido, despacho y recepción sin duplicar registros ni movimientos.
- RLS limita a un usuario de sucursal a su propia sucursal; no hay permisos directos de escritura para authenticated ni acceso anon.
- Todas las pruebas operativas se ejecutaron dentro de transacciones revertidas.
