# Inventario y pedidos — diseño vigente

Este documento describe el comportamiento aprobado para los módulos independientes de inventario de Drosalud. Las migraciones están en la rama `feature/inventario-pedidos`; no se han aplicado a producción.

## Módulos

### 1. Generar Kardex
- Formulario inicial independiente para seleccionar bodega, laboratorios, línea y contenido.
- Laboratorios con buscador, seleccionar todos y limpiar.
- Filtro de contenido: existencia distinta de cero, solo negativos o solo cero.
- Resultado agrupado por laboratorio A-Z y producto A-Z.
- Columnas: Producto, Cantidad (cajas/presentaciones completas) y Unidades sueltas.
- Salida en pantalla, impresión POS, PDF mediante diálogo de impresión y CSV compatible con Excel.
- La línea comercial es editable en la ficha del producto y se guarda en mayúsculas.

### 2. Pedidos
- Módulo independiente.
- Sugerido por unidades vendidas en la semana calendario actual, de lunes a domingo, zona horaria America/Bogota.
- No resta el saldo actual del sugerido.
- Cantidades editables antes de imprimir.

### 3. Recepción
- Módulo independiente.
- Registra unidades individuales únicamente cuando la mercancía llega físicamente.
- Marcar un pedido como comprado no aumenta el saldo.
- La clave de operación hace idempotente la recepción.

## Reglas de inventario
- Inventario inicial cero; no se importan existencias desde catálogo ni ventas anteriores.
- Las ventas descuentan inmediatamente `recibo_items.cantidad`, que ya está expresada en unidades individuales por el POS.
- Se permiten saldos negativos.
- La anulación compensa exactamente el movimiento de venta original y no borra el historial.
- La recepción suma unidades individuales físicamente recibidas.
- El saldo se obtiene sumando `inventario_movimientos.unidades_delta`.

## Identidad de producto y presentaciones
- Cada código identifica una presentación concreta.
- Si cambia la presentación o equivalencia, se registra un producto nuevo con un código nuevo.
- Un producto que ya tiene movimientos no permite cambiar código, `fraccionable`, `unidades_por_caja` ni `unidades_por_venta`.
- El producto anterior conserva sus movimientos e historial; no se convierten ni reinterpretan sus saldos.

## Integridad de ventas y Kardex
- Una línea de venta que ya generó movimiento no se puede editar ni eliminar.
- Para corregir una venta registrada, se anula el recibo y se crea uno nuevo con los datos correctos.
- Un recibo con movimientos no se puede borrar.
- Un recibo anulado y ya revertido no se puede reactivar.
- Estas reglas se aplican en Supabase, no solo en la interfaz.

## Información económica y acceso
- Ambos socios pueden consultar costo de compra, precio de venta e información de ganancia.
- La vista `productos_app` conserva los campos económicos y agrega `linea`; no se ocultan costos por tratarse de un usuario vendedor.
- La vista usa `security_invoker=true` para respetar las políticas RLS de `productos` del usuario que consulta. La política de lectura de producción autoriza usuarios activos de Drosalud.

## Migraciones vigentes
1. `supabase/migrations/20261109120000_inventario_movimientos.sql`: línea comercial, movimientos, saldos, triggers de venta/anulación y RPC de recepción.
2. `supabase/migrations/20261109150000_integridad_kardex.sql`: protege presentación, líneas de venta y recibos con movimientos.
3. `supabase/migrations/20261109160000_productos_app_security_invoker.sql`: hace que `productos_app` respete RLS del usuario que consulta.

## Archivos obsoletos
- `sql/inventario-pedidos-propuesta.sql` es obsoleto y NO debe ejecutarse. Usa nombres de columnas y funciones de un diseño anterior.

## Estado de validación
- Las tres migraciones se aplicaron en el proyecto aislado `drosalud-pruebas`.
- Se verificó con pruebas SQL que una venta descuenta unidades, el cambio de equivalencia queda bloqueado, la línea vendida no se puede editar ni borrar, la anulación devuelve el saldo a cero, y el recibo anulado no se puede reactivar ni borrar.
- También se verificó que `productos_app` conserva las opciones `security_barrier=true` y `security_invoker=true`.
- El proyecto de pruebas es un esquema aislado y no una copia completa de producción; los advisors muestran avisos por tablas de recibos/productos sin RLS en ese entorno mínimo. No se debe interpretar esa configuración de pruebas como el estado de producción.
- No se ha ejecutado ninguna migración en producción.
- Falta validar los flujos reales de frontend en Preview y los casos de permisos con ambos usuarios antes de aprobar el PR.

## Producción
No fusionar el PR ni ejecutar migraciones en producción hasta completar pruebas funcionales y revisar las migraciones contra el esquema real.
