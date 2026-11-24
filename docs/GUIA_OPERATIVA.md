# Guía operativa de DROSalud

## Cómo leer esta guía

DROSalud registra operaciones del negocio. Cada acción tiene un resultado distinto: consultar no modifica datos; guardar una solicitud no compra mercancía; registrar una factura no significa que llegó; confirmar una recepción sí registra una entrada; una venta confirmada registra una salida.

## Recorrido diario

1. Abrir el sistema y comprobar que el entorno diga **Producción** o **ENTORNO DE PRUEBAS**, según corresponda. No registrar operaciones reales en QA.
2. Consultar el catálogo y revisar que el producto y su presentación sean los correctos.
3. Registrar cada venta una sola vez y entregar el recibo al cliente.
4. Revisar los saldos y movimientos para identificar productos agotados o negativos.
5. Preparar pedidos según la necesidad real y las sugerencias del sistema.
6. Esperar la autorización administrativa cuando el flujo la requiera.
7. Comparar órdenes, factura/remisión y mercancía física.
8. Confirmar únicamente las unidades recibidas y aceptadas.
9. Consultar Kardex e informes para verificar el resultado.

## Ventas y cotizaciones

- **Venta/recibo:** registra una operación realizada. Revisa productos, cantidades, presentación, descuentos, domicilio y medio de pago antes de confirmar.
- **Cotización:** es una oferta para el cliente; no es una venta y no debe descontar inventario.
- La cotización muestra una fecha “válida hasta”. El estado guardado puede seguir como pendiente aunque esa fecha haya pasado; no se debe tratar como vigente después de su vencimiento.
- **Anulación:** debe utilizar el procedimiento habilitado por el sistema. No se corrige una venta creando otra venta negativa ni editando directamente la base de datos.
- **Fraccionamiento:** confirma si la cantidad ingresada está expresada en empaques o unidades. La equivalencia debe corresponder a la ficha del producto.

## Catálogo y presentaciones

- Busca por código y nombre antes de crear una referencia.
- El costo de compra y el precio de venta son datos distintos.
- El porcentaje de “Ganancia sobre la compra” es un recargo sobre el costo: costo × (1 + porcentaje/100). No es el margen sobre el precio de venta. El redondeo configurado se aplica hacia arriba y un precio manual existente tiene prioridad sobre la sugerencia.
- La cantidad por empaque determina la conversión a unidades base.
- Si una presentación requiere código y trazabilidad propios, se registra como producto separado.
- No cambies el código ni la equivalencia de una referencia que ya tiene movimientos sin evaluar el impacto histórico.

## Pedidos y órdenes de compra

- **Pedido sugerido:** propone reposición a partir de la rotación, saldo y compromisos pendientes que consulta el sistema. Es una propuesta, no una orden enviada al proveedor.
- **Pedido urgente:** permite priorizar necesidades, por ejemplo productos con saldo negativo. El negativo es una señal para investigar, no una orden automática para ajustar inventario.
- **Autorización:** confirma qué cantidades se permite comprar. No genera una entrada de inventario.
- **Orden de compra:** organiza los productos y cantidades aprobados por proveedor. Sigue pendiente hasta que se reciba mercancía.

## Documentos del proveedor y recepción

Hay tres cantidades que no deben confundirse:

1. **Solicitada:** unidades que aparecen en la orden.
2. **Documentada:** unidades que el proveedor declara en la factura o remisión.
3. **Recibida y aceptada:** unidades que llegaron físicamente y se verificaron.

Una factura puede documentar más unidades que las solicitadas, o más unidades que las que llegaron. Eso no significa que se deban ingresar automáticamente. Primero se debe aclarar o autorizar la diferencia mediante el proceso previsto.

- Registrar factura/remisión crea el documento comercial y sus líneas; por sí solo no aumenta inventario.
- La recepción confirma lo que llegó y fue aceptado.
- Una diferencia de costo frente al costo de la orden requiere la autorización y el motivo que valida el sistema.
- Una recepción confirmada genera la entrada correspondiente en inventario/Kardex y actualiza las cantidades recibidas de la orden.
- No repitas una confirmación cuando la pantalla tarde o muestre un error: primero consulta si la recepción ya quedó registrada.

## Inventario y Kardex

- El saldo representa el resultado de entradas y salidas que el sistema tiene registradas.
- Un saldo negativo significa que las salidas registradas superan las entradas registradas. No demuestra por sí solo que físicamente no exista mercancía.
- El saldo cero significa que el registro de movimientos queda en cero.
- Para explicar una diferencia, revisa el historial del producto, ventas, anulaciones, recepciones y ajustes.
- No se debe crear un ajuste para ocultar una diferencia sin identificar la causa y contar con la autorización aplicable.

## Caja e informes

- Caja resume ventas, medios de pago, gastos y cierre de la jornada. El efectivo esperado se calcula como base inicial + ventas en efectivo − gastos en efectivo; las transferencias y otros medios no forman parte del efectivo contado. La diferencia es efectivo contado − efectivo esperado. Verifica efectivo contado y valores electrónicos antes de cerrar. Los gastos no registrados no aparecerán en el resumen.
- Los informes dependen de los filtros y del período seleccionado. Revisa fechas y alcance antes de exportar.
- Margen bruto estimado no equivale a utilidad neta: no descuenta necesariamente gastos, comisiones, domicilios ni otros costos.
- El valor del inventario solo es confiable si los saldos y costos de referencia son completos y consistentes.

## Usuarios, permisos y seguridad

- El rol define las acciones visibles, pero la autorización real se valida también en Supabase.
- Las operaciones administrativas deben realizarse con el usuario autorizado.
- No compartas contraseñas ni códigos de verificación.
- Si el sistema muestra una operación pendiente o un error de red, consulta primero el historial antes de repetirla.

## Ayuda y Sistema

- **Ayuda** debe explicar qué resuelve cada módulo, cuándo usarlo, pasos, datos que guarda, efectos sobre inventario y errores comunes.
- **Sistema** debe mostrar versión, entorno, estado de sesión/conexión, estado de sincronización, diagnóstico y dependencias activas. Nunca debe mostrar claves secretas.
- La exportación operativa de Excel incluye Recibos, Ventas por producto, Productos, Clientes e Historial de precios. No es un respaldo completo restaurable: no incluye órdenes/documentos de compra, recepciones, movimientos Kardex, usuarios ni toda la configuración. Conserva el archivo fuera del equipo y no lo uses como única copia ante pérdida de la base de datos.
- La frecuencia configurada en Ajustes → Administración solo controla el recordatorio manual; no ejecuta exportaciones automáticas. La opción “Luego” aplaza el aviso tres días.
- Las mediciones de carga del navegador no son una prueba de velocidad de internet.
- Un respaldo descargado debe comprobarse y guardarse en un lugar seguro. La notificación de descarga no reemplaza la verificación del archivo.

## Regla ante diferencias

Antes de corregir una cifra, clasifica la diferencia:

- **Error de uso:** la operación se realizó de forma distinta al flujo previsto. Documentar el procedimiento y capacitar.
- **Diferencia documental:** lo facturado no coincide con la orden o la mercancía. Conciliar con el proveedor.
- **Diferencia física:** el saldo del sistema no coincide con lo que hay en el estante. Investigar movimientos y validar un ajuste autorizado.
- **Error técnico:** el sistema duplicó, omitió o calculó mal un registro. Reproducir en QA y corregir con pruebas.

No modificar datos históricos solo para hacer coincidir totales sin evidencia documental.
