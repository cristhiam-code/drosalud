# Hallazgos de auditoría: ventas e inventario

Fecha de revisión: 24 de noviembre de 2026.

## Alcance y seguridad
- Consultas exclusivamente de lectura sobre producción y QA.
- No se modificaron recibos, productos, costos, movimientos ni saldos.
- No se crearon ventas ni sesiones de conteo.
- Las diferencias históricas se documentan; no se corrigen sin evidencia y aprobación.

## Ventas en producción
| Control | Resultado |
|---|---:|
| Recibos | 38 |
| Recibos activos | 31 |
| Recibos anulados | 7 |
| Líneas de venta | 62 |
| Movimientos tipo venta | 62 |
| Líneas sin movimiento de venta | 0 |
| Movimientos sin línea de recibo | 0 |
| Líneas con cantidad/unidades diferentes al movimiento | 0 |
| Líneas anuladas sin reversión | 0 |
| Reversiones incorrectas o duplicadas | 0 |

La referencia de los movimientos tipo venta apunta a la línea de recibo (recibo_items.id), no a la cabecera del recibo. La conciliación se hizo usando esa relación.

## Inventario y Kardex
- Productos registrados: 1.195.
- Movimientos de inventario: 114.
- Productos con saldo distinto de cero: 18.
- Productos con saldo negativo: 10.
- Productos con saldo cero: 1.177.
- Productos con saldo positivo: 8.
- Diferencias entre inventario_saldos y la suma de inventario_movimientos: 0.
- Códigos de producto duplicados: 0.
- Productos sin código: 13.

Los saldos negativos no se clasifican automáticamente como errores. Pueden indicar ventas anteriores a la carga de entradas, saldo inicial aún no registrado o movimientos que necesitan investigación. Entre los registros sin código hay servicios y referencias comerciales; no se debe asignar un código en bloque sin revisar cada ficha.

## Costos guardados en ventas
En las 55 líneas de ventas activas:
- 37 no tienen costo_real_unitario.
- Las 55 sí tienen precio_compra guardado como costo de referencia de la venta.
- No hay líneas activas sin precio de venta, con cantidad no positiva o con factor de presentación inválido.

La función actual de venta toma el costo del producto al momento de registrar la operación y lo guarda en recibo_items.precio_compra. La ausencia de costo_real_unitario en estas líneas antiguas no significa por sí sola que no exista costo histórico; el campo de referencia disponible es precio_compra.

## Diferencia histórica en el cálculo de ganancia
La función de venta actualmente calcula la ganancia del recibo como:

margen de las líneas - descuento + domicilio - costo del mensajero

Al recalcular 31 recibos activos con esa fórmula, 24 coinciden y 7 recibos antiguos de octubre muestran una diferencia exactamente igual al valor del domicilio:
- Recibo 13: diferencia $3.000.
- Recibo 17: diferencia $3.000.
- Recibo 31: diferencia $3.000.
- Recibo 35: diferencia $3.000.
- Recibo 36: diferencia $4.000.
- Recibo 37: diferencia $3.000.
- Recibo 38: diferencia $4.000.

La evidencia apunta a que el cálculo histórico de esos recibos no incluía el domicilio como ingreso de ganancia, mientras que la función actual sí lo incluye. Esto es una diferencia de criterio entre versiones del cálculo, no evidencia de movimientos de inventario incorrectos. No se modifican los recibos históricos.

El resumen de ganancia por producto en la interfaz calcula el margen de las líneas y no distribuye el domicilio entre productos. Por ello, el total de ganancia del recibo y la suma de márgenes por producto pueden no ser comparables sin explicar ese componente.

## Conclusión
La trazabilidad de ventas y el saldo contable del Kardex están conciliados en los registros revisados. Los pendientes son de interpretación y calidad de datos: investigar los 10 saldos negativos, validar el origen de los 13 productos sin código y definir/documentar el tratamiento del domicilio en indicadores históricos. No se justifica una corrección masiva ni una modificación de datos productivos.