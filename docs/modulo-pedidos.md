# Módulo PEDIDOS — Drosalud

## Propósito
PEDIDOS es el flujo interno de abastecimiento. No es una orden de compra: una solicitud interna puede contener productos de distintos proveedores y, al autorizarse, producir varias órdenes de compra.

## Modalidades
- **Sugerido:** propuesta calculada a partir de rotación, existencias y compras pendientes. El administrador revisa y ajusta cantidades.
- **Urgente:** necesidad inmediata por solicitud de un cliente o agotado.
- **Extraordinario:** ampliación planificada, incorporación de productos o aprovechamiento de oportunidades comerciales.

## Flujo
1. Admin o vendedor crea un borrador.
2. El vendedor puede editar sus propios borradores y enviarlos; también el administrador puede hacerlo.
3. El envío deja el pedido pendiente de autorización.
4. Solo el administrador autoriza o rechaza.
5. El administrador asigna cada línea autorizada a uno o varios proveedores y genera una o varias órdenes de compra.
6. La recepción física continúa por el flujo existente. Solo la recepción confirmada genera movimientos de inventario y actualiza Kardex.

## Reglas de integridad
- Cantidades de pedido y orden se expresan en unidades base.
- No se puede autorizar más de lo solicitado.
- El administrador puede vincular un producto escrito como texto a un registro del catálogo durante la autorización.
- La generación de órdenes utiliza una clave de operación y huella de la solicitud: un reintento idéntico devuelve las órdenes ya creadas y no las duplica; reutilizar la clave con asignaciones distintas se rechaza.
- Las asignaciones a proveedores no pueden superar el total autorizado, incluyendo órdenes ya generadas.
- Un producto no catalogado puede registrarse como texto en un pedido; debe vincularse a un producto del catálogo antes de generar una orden formal.
- Generar órdenes es una operación atómica. Si una validación falla, no queda ninguna orden parcial.
- Autorizar o generar órdenes no modifica existencias ni crea movimientos de inventario.
- Las órdenes antiguas conservan `pedido_id = NULL`; sus líneas conservan `pedido_item_id = NULL`.
- `compras_pendientes` y sus cotizaciones históricas se conservan. `cotizaciones_proveedor` puede vincularse a una compra pendiente antigua o a una línea de pedido nueva, nunca a ambas.
- Las órdenes de compra creadas desde un pedido autorizado quedan aprobadas para que continúen por el proceso actual de recepción.

## Cálculo del pedido sugerido
La interfaz utiliza una ventana móvil de 7 días, excluye recibos anulados, convierte presentaciones a unidades base, consulta el saldo de `inventario_saldos` y descuenta unidades pendientes de recibir en órdenes no canceladas.

La fórmula inicial es:

`cantidad sugerida = max(0, ventas de 7 días − existencia − pendientes de recibir)`

La cobertura inicial es de 7 días. No se inventa un stock de seguridad ni un mínimo que el negocio todavía no tenga configurado. El administrador puede modificar cada cantidad antes de guardar o enviar.

## Frontend
- `modules/pedidos.js`: interfaz y lógica de PEDIDOS.
- `modules/pedidos.css`: estilos del módulo.
- `index.html`: integra el módulo en la navegación principal y proporciona el cliente de Supabase.

## Base de datos
La migración `supabase/migrations/20261112210000_create_pedidos_module.sql` crea:
- `pedidos` y `pedidos_items`.
- Relaciones desde órdenes de compra a pedido y línea de pedido.
- Vínculo opcional de cotizaciones con una línea de pedido.
- Vista `pedidos_resumen` para estados operativos derivados.
- RPC para guardar, enviar, autorizar, rechazar y generar órdenes.

## Seguridad
- Lectura de pedidos para usuarios activos del equipo.
- Guardado y envío mediante RPC con validación de sesión y rol.
- Autorización, rechazo y generación de órdenes exclusivamente para administrador.
- Sin escrituras directas a `pedidos` ni `pedidos_items` desde el cliente.
- Las RPC privilegiadas revocan ejecución de PUBLIC/anon y conceden ejecución a authenticated.
- La creación/aprobación de órdenes independientes queda restringida al administrador para impedir el bypass del flujo.

## Estados
La tabla conserva estados administrativos: `borrador`, `pendiente_autorizacion`, `autorizado`, `rechazado`, `cancelado`.
La vista `pedidos_resumen` calcula el avance operativo: `parcialmente_comprado`, `en_compra`, `parcialmente_recibido`, `completado`.

## Alcance pendiente de completar
- Captura y comparación de cotizaciones por línea de pedido desde la interfaz.
- Pruebas manuales de extremo a extremo en el preview con una cuenta de vendedor y otra de administrador.
- Revisión visual en móvil y escritorio.
- Integración de los pedidos urgentes con el módulo antiguo de medicamentos por conseguir, sin borrar el historial legacy.
