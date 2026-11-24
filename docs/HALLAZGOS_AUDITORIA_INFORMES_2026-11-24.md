# Hallazgos de auditoría: Informes y reportes

Fecha: 24 de noviembre de 2026. Revisión estática del módulo y consultas de solo lectura.

## Alcance real del módulo

El módulo actual ofrece tres consultas: Valor del inventario, Existencias y Faltantes. No incluye informes de ventas por período, margen por producto, compras, gastos, rotación ni desempeño de vendedores. Para ventas se debe consultar Historial y Caja; para compras, los módulos de Pedidos y Recepción.

Los datos se consultan desde productos_app, inventario_saldos, inventario_movimientos e historial_costos. La vista no escribe datos ni modifica existencias.

## Valoración

El módulo asigna intencionalmente null a valor de inventario y valor potencial de venta; por eso muestra “No disponible” o “—”. No debe interpretarse como valor cero. Muestra saldo del Kardex y costo unitario de referencia, pero no calcula una valoración física total.

## Costos

El costo unitario se resuelve en este orden: último movimiento con costo, historial de costos más reciente y, como alternativa, costo de presentación del catálogo dividido por unidades por empaque. En los registros actuales, los costos de catálogo existen; los productos con saldo positivo no quedan sin costo por ausencia de un historial de recepción.

## Conclusión y trabajo pendiente

El módulo es de consulta y no presenta errores de escritura. Su alcance es limitado frente a un ERP completo. Para la siguiente etapa se recomienda definir y probar informes de ventas, margen, compras, gastos y rotación, pero sin añadir indicadores hasta que sus fórmulas y fuentes estén conciliadas. No calcular utilidad neta con la ganancia de recibos solamente.