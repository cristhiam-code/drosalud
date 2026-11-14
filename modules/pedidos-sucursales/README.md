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
- Una solicitud tiene un único registro y cambia de estado. Las pantallas consultan el mismo pedido; no duplican registros.
- El despacho descuenta del inventario de la bodega central. La recepción acredita únicamente las unidades confirmadas por la sucursal.
- Los movimientos deben ser idempotentes y auditables.
- No se altera el módulo de compras a proveedores, Ventas ni Caja.
- El primer desarrollo y sus pruebas se realizan exclusivamente en QA.
