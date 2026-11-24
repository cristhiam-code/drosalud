# Hallazgos de auditoría: catálogo y precios

Fecha: 24 de noviembre de 2026. Consultas de solo lectura en producción.

## Resumen
- Productos: 1.195.
- Costo de compra nulo o negativo: 0.
- Precio de venta negativo: 0.
- Precio de venta manual nulo: 1.164.
- Precio manual inferior al costo de compra: 2.
- Productos fraccionables con factor inválido: 0.
- Productos fraccionables configurados: 11.
- Códigos duplicados: 0.
- Productos sin código: 13.

## Cómo interpretar los precios nulos

Que precio_venta esté vacío no significa que el producto no tenga precio. El POS calcula una sugerencia usando los ajustes del negocio: 25% de recargo sobre el costo y redondeo hacia arriba a $100. Si existe un precio manual, el sistema lo respeta. Esta regla se explica ahora en Ayuda y está separada en domain/precios.js con pruebas.

## Dos referencias con precio manual inferior al costo

| Producto | Costo de presentación | Precio manual | Factor | Saldo actual | Último cambio de costo |
|---|---:|---:|---:|---:|---|
| BONSONO 2MG * 20 TAB | $500.000 | $50.000 | 20 | 0 | 19-nov-2026 |
| CETIRIZINA 10 MG X 30 PASTILLAS | $180.000 | $15.000 | 30 | 0 | 14-nov-2026 |

Ambos costos se registraron desde recepción. El historial de ventas es anterior al último cambio de costo/presentación:
- BONSONO: ventas del 24 y 28 de octubre, con costo guardado $25.000 por línea y precios de $40.000/$50.000. El costo de presentación actual de $500.000 corresponde a 20 unidades de $25.000.
- CETIRIZINA: venta del 8 de noviembre, con factor histórico 10, costo guardado $200 y precio $1.500 por unidad de presentación. La ficha actual usa factor 30 y costo de presentación $180.000.

No hubo ventas posteriores a esos cambios de costo. Los registros sugieren que cambió la presentación/factor o el costo de empaque y el precio manual no se actualizó. No se puede afirmar cuál precio debe quedar sin cotejar el documento del proveedor, la presentación física y el precio comercial decidido.

## Recomendación

No modificar precios ni factores automáticamente. Antes de vender estas referencias, administración debe comprobar la factura/remisión, unidades por empaque y precio comercial. Una vez confirmado, actualizar el precio con motivo mediante el flujo autorizado. Los 13 productos sin código también deben revisarse individualmente; no todos necesariamente requieren código de barras (por ejemplo, servicios).