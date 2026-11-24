# Hallazgos de auditoría: caja y cotizaciones

Fecha: 24 de noviembre de 2026. Consultas de solo lectura sobre producción.

## Caja
- 17 registros de cierre: 16 con estado cerrada y 1 con estado reabierta.
- Los 16 cierres cerrados cumplen la fórmula efectivo esperado = base inicial + ventas en efectivo - gastos en efectivo.
- En los 16 cierres, diferencia = efectivo contado - efectivo esperado.
- Ningún cierre cerrado muestra cambios posteriores en ventas totales o ventas en efectivo frente al resumen actual.
- No hay fechas de cierre duplicadas.
- Hay 3 registros en cierres_caja_historial.
- El cierre del 6-nov-2026 está reabierto, con motivo “Prueba de cierre superada”, y no tiene fila en cierres_caja_historial. Se conserva como antecedente de prueba; no se modifica.
- La tabla gastos tiene 0 registros. Esto no es necesariamente un error técnico, pero significa que ningún gasto se ha descontado de los cierres ni de los informes que dependen de esa tabla.

Los cierres de días con ventas por transferencia u otros medios pueden mostrar ventas totales mayores que ventas en efectivo. Eso es correcto: solo las ventas en efectivo, junto con base inicial y gastos en efectivo, determinan el efectivo esperado.

## Cotizaciones
- 16 cotizaciones guardadas y 17 líneas.
- Todas tienen estado almacenado pendiente.
- Las 16 fechas de validez ya habían pasado al 24-nov-2026 (fechas entre 1 y 21 de noviembre).
- Ninguna cotización está vinculada a un recibo y no hay líneas huérfanas.

Esto no demuestra un error de conversión: no hay cotizaciones convertidas en recibos en los datos revisados. El sistema muestra el estado guardado y la fecha válida hasta; por eso Ayuda ahora aclara que una cotización no debe tratarse como vigente si la fecha ya pasó, aunque el estado siga diciendo pendiente.

## Conclusión

La fórmula de caja está conciliada en los 16 cierres cerrados. Los pendientes son de operación/registro: no se han registrado gastos, existe un cierre histórico reabierto de una prueba y las cotizaciones registradas están vencidas sin recibo asociado. No se cambiaron datos.