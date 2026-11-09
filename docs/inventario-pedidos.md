# Drosalud · Inventario, Kardex y Pedidos

## Base funcional
- El saldo se expresa siempre en unidades individuales.
- El inventario inicial es cero; no se infiere desde el catálogo.
- La línea de venta ya guarda `recibo_items.cantidad` en unidades individuales (incluye ventas fraccionadas). El trigger descuenta esa cantidad al insertarse la línea.
- Una anulación cambia el recibo de no anulado a anulado y genera una reversión positiva por cada línea, una sola vez.
- Una recepción física se registra por RPC y suma unidades individuales. El estado "comprado" de compras pendientes no afecta existencias.
- No se bloquean ventas por saldo negativo.
- Las líneas sin `producto_id` no afectan inventario.

## Kardex
- Consulta de saldo actual, no historial de movimientos.
- Todos los productos, incluidos los que tienen saldo cero.
- Orden: laboratorio A-Z y producto A-Z.
- Presentación: factor `productos.unidades_por_caja`; cajas completas y unidades sueltas.
- Si el saldo es negativo, mostrar cajas 0 y el saldo negativo en unidades (ej. -10 → 0 cajas, -10 unidades).

## Pedidos sugeridos
- Ventana móvil de los últimos 7 días.
- Sugerido = unidades vendidas en ese período, sin restar inventario actual.
- Convertir unidades a cajas y unidades sueltas con `unidades_por_caja`.
- El usuario ajusta la cantidad a pedir. No registrar compra ni recepción desde el cálculo sugerido.

## Pruebas obligatorias antes de fusionar
1. Venta de producto no fraccionable: -1 unidad.
2. Venta fraccionada de 10 unidades: -10 unidades.
3. Venta de 3 empaques de 30: -90 unidades.
4. Anulación: reversión exacta; repetir actualización no duplica.
5. Recepción de 2 unidades: +2; recepción no cambia el recibo ni el costo.
6. Secuencia saldo 0 → venta 1 → -1; venta 1 → -2; recepción 2 → 0; recepción 4 → +4.
7. Venta sin producto_id no crea movimiento.
8. Usuario no autenticado/no autorizado no puede registrar recepción.
9. Vendedor y administrador consultan Kardex y registran recepción según permisos RLS vigentes.
10. El pedido sugerido no resta existencias y excluye recibos anulados.
