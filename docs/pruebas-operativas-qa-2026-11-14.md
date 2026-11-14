# Pruebas operativas QA — 14/11/2026

## Alcance y entorno

- Aplicación: preview Vercel de `release/qa-candidate-2026-11-14`.
- URL probada: `https://drosalud-ox3bfgxfb-drosalud.vercel.app/`.
- Despliegue: `READY`, commit `61eb3612783a6b6addabdd7e901cf675095051eb`.
- HTTP: página principal 200; `modules/pedidos.js` 200; `modules/pedidos.css` 200; `manifest.webmanifest` 200.
- El host preview usa el selector de entorno para Supabase QA (`uorhpljsofnfgzblxcga`), no producción.
- Producción no fue modificada.

## 1. Validación estática del despliegue

- Los tres bloques JavaScript inline de `index.html` se pudieron compilar con el parser de JavaScript.
- `modules/pedidos.js` se pudo compilar con el parser de JavaScript.
- HTML incluye el contenedor `#pedidos-app`, carga `modules/pedidos.js` y `modules/pedidos.css`.
- El módulo obtiene el usuario autenticado y el rol desde `usuarios_drosalud`.
- La interfaz solo presenta autorización/rechazo y generación desde Pedidos cuando el rol es administrador.
- Los RPC del servidor vuelven a validar el rol; no dependen de ocultar botones.
- Compras independiente conserva el botón de creación y el flujo de aprobar orden para el equipo activo.

Esto es validación HTTP/estática, no una prueba de interacción real con navegador.

## 2. Prueba transaccional de flujo completo en QA

Se ejecutó un bloque SQL que creó datos temporales y revirtió todo al terminar:

1. Usuario vendedor creó una orden independiente y la aprobó, conservando el comportamiento productivo.
2. Vendedor creó un Pedido urgente y lo envió a autorización.
3. El intento de autorización por vendedor fue denegado.
4. Administrador autorizó las tres unidades solicitadas.
5. La misma línea se dividió entre dos proveedores: 1 unidad y 2 unidades.
6. Se generaron dos órdenes de compra.
7. Repetir la generación con la misma clave de operación devolvió las mismas dos órdenes, sin duplicarlas.
8. Vendedor registró recepción parcial de 1 de 2 unidades en una de las órdenes.
9. Repetir la recepción con la misma clave devolvió el mismo recibo y dejó un único movimiento de inventario.
10. Vendedor no pudo generar órdenes desde Pedidos.

Resultado: el bloque terminó sin excepción y las verificaciones posteriores confirmaron que pedidos, órdenes, recepciones, movimientos, proveedor temporal y cambio de rol fueron revertidos.

## 3. Validaciones negativas

Otra prueba transaccional confirmó que el servidor rechaza:
- Autorizar más unidades de las solicitadas.
- Asignar a proveedores más unidades que las autorizadas.
- Recibir más unidades que las ordenadas.

Todos los registros creados para estas pruebas se revirtieron.

## 4. Permisos RPC

En QA, los cinco RPC de Pedidos (`guardar_pedido`, `enviar_pedido`, `autorizar_pedido`, `rechazar_pedido`, `generar_ordenes_compra_pedido`) tienen:
- `authenticated`: EXECUTE permitido.
- `anon`: EXECUTE denegado.
- `PUBLIC`: EXECUTE denegado.

Las definiciones SQL de `crear_orden_compra`, `aprobar_orden_compra` y `registrar_recepcion_compra` siguen coincidiendo por huella MD5 entre QA y producción.

## 5. Resultado de integridad después de las pruebas

QA quedó con los mismos conteos que antes de las pruebas:
- Pedidos: 0.
- Líneas de pedido: 0.
- Órdenes de compra: 2.
- Líneas de órdenes: 2.
- Recepciones: 1.
- Movimientos de inventario: 11.
- Proveedores: 1.
- Administradores activos: 1.
- Vendedores activos: 0.

Producción quedó con:
- Productos: 1.189.
- Proveedores: 2.
- Movimientos de inventario: 54.
- Órdenes de compra: 0.
- Tablas de Pedidos: no existen todavía.

## 6. Pendientes para cerrar pruebas de usuario

- QA no tiene una cuenta activa con rol vendedor; la prueba de permisos vendedor se hizo simulando el rol dentro de una transacción y revirtiéndolo.
- La herramienta disponible para esta sesión permite consultar la vista previa y ejecutar consultas, pero no controlar un navegador autenticado ni introducir credenciales. Por tanto, no se declara aprobado el recorrido visual E2E.
- QA no tiene recibos de venta en los últimos siete días; el módulo Pedido sugerido debe mostrar el estado vacío. No se pudo validar con ventas reales recientes el cálculo no vacío. El cálculo se revisó estáticamente: toma unidades vendidas en siete días, descuenta saldo de inventario y cantidades pendientes de órdenes aprobadas/parciales, sin inventar stock de seguridad.
- Para cerrar la aceptación visual/funcional se requiere iniciar sesión en la vista previa con un usuario QA autorizado y, para el recorrido vendedor, disponer de un usuario QA con rol vendedor.

## Conclusión

Los flujos críticos de base de datos, permisos, división por proveedor, idempotencia, recepción parcial y validaciones de cantidades pasaron pruebas transaccionales en QA. Los archivos del preview responden y pasan validación sintáctica. No se ha certificado todavía el recorrido E2E autenticado del navegador ni el cálculo sugerido con ventas recientes. Producción permanece sin cambios.
