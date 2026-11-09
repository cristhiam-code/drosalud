# Inventario y pedidos — propuesta técnica

Esta carpeta contiene SQL de propuesta, todavía no aplicado a Supabase.

## Reglas funcionales
- Inventario inicial cero; no se importan existencias desde catálogo ni ventas antiguas.
- La cantidad de `recibo_items` ya representa unidades individuales según el POS actual. Por eso cada venta descuenta `cantidad`, no `cantidad * unidades_por_presentacion`.
- El saldo admite negativos.
- Anular un recibo compensa una sola vez cada línea, sin borrar movimientos.
- Marcar una compra como comprada/entregada no suma stock. Solo la RPC de recepción física registra entradas.
- Pedidos semanales se calculan con unidades vendidas en los últimos siete días y se convierten a cajas/unidades usando `productos.unidades_por_caja`. No se resta el saldo actual del sugerido.

## Archivos
- `inventario-pedidos-propuesta.sql`: tablas, triggers y RPC de recepción.
- `inventario-pedidos-pruebas.sql`: consultas de verificación.

## Pendiente antes de aplicar
1. Ejecutar pruebas en una base aislada.
2. Validar con casos reales de POS fraccionable y no fraccionable.
3. Integrar interfaz Kardex/Pedidos/Recepción en `index.html`.
4. Revisar políticas y advisors.
5. Solo entonces solicitar autorización separada para producción.
