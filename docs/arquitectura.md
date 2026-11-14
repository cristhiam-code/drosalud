# Arquitectura actual de Drosalud

**Rama documentada:** `feature/modulo-pedidos`  
**Alcance:** documentación del frontend existente. Este archivo no define cambios de base de datos ni autoriza despliegues.

## 1. Punto de entrada

`index.html` sigue siendo el documento principal de la aplicación. En esta rama tiene aproximadamente 1.146 líneas y conserva la estructura HTML de las pantallas, parte de los estilos y una cantidad importante de JavaScript legado.

No es todavía una aplicación completamente modular. La extracción del frontend se está haciendo gradualmente para reducir el riesgo de romper operaciones existentes.

## 2. Archivos JavaScript cargados desde index.html

En el orden actual, el documento carga:

1. `supabase.js`, `base.js` y bibliotecas auxiliares (`xlsx.mini.min.js`, `html5-qrcode.min.js`, `qrcode.js`).
2. `modules/inventario.js`.
3. `modules/caja.js`.
4. `modules/compras.js`.
5. `modules/ordenes-compra.js`.
6. `modules/core.js`.
7. `modules/cotizaciones.js`.
8. `modules/pedidos.js`.
9. `modules/historial-ventas.js`.
10. `modules/historial-precios.js`.

También se carga `modules/pedidos.css`.

La carga de `modules/caja.js` aparece una sola vez en el HTML revisado.

## 3. Responsabilidad de los módulos extraídos

| Archivo | Responsabilidad observada |
| --- | --- |
| `modules/inventario.js` | Funciones del módulo de inventario. |
| `modules/caja.js` | Funciones del módulo de caja. |
| `modules/compras.js` | Gestión de proveedores, compras pendientes y cotizaciones a proveedores. |
| `modules/ordenes-compra.js` | Creación, aprobación y recepción de órdenes de compra. |
| `modules/core.js` | Puente explícito de funciones compartidas entre módulos y código legado. |
| `modules/cotizaciones.js` | Integración del módulo de cotizaciones de venta. |
| `modules/pedidos.js` | Flujo de pedidos internos: sugeridos, urgentes, extraordinarios y su gestión. |
| `modules/historial-ventas.js` | Funciones del historial de ventas. |
| `modules/historial-precios.js` | Funciones del historial de precios. |
| `modules/pedidos.css` | Estilos del módulo Pedidos. |

La presencia de un archivo separado no significa que todas sus dependencias estén aisladas. Algunos módulos todavía usan variables o funciones compartidas que se originan en el código de `index.html`.

## 4. Código que todavía permanece dentro de index.html

La revisión identificó tres bloques grandes de JavaScript inline, además de la estructura HTML y CSS:

- **Bloque inicial:** crea el cliente de Supabase, define utilidades y estado global, gestiona el rol de usuario, ajustes, paleta y funciones relacionadas con cotizaciones.
- **Bloque de sincronización y arranque:** gestiona Realtime, carga de datos, sesión, MFA, inicio de la aplicación y utilidades compartidas.
- **Bloque principal legado:** conserva navegación, pantallas y lógica del POS, incluida parte del flujo de ventas y carrito.

Por tanto, `index.html` continúa siendo un archivo con responsabilidades mezcladas. No debe intentarse extraer un bloque completo sin mapear antes sus funciones, variables globales, eventos y dependencias.

## 5. Comunicación entre módulos

El HTML carga los módulos como scripts clásicos, no como módulos ES con `import/export`.

El archivo `modules/core.js` publica `window.DrosaludCore` y expone un conjunto limitado de funciones compartidas. En el código revisado, el contrato contiene utilidades y operaciones que necesita Cotizaciones.

También hay funciones y datos globales heredados, por ejemplo el cliente de Supabase y datos de catálogo. Esta dependencia debe reducirse gradualmente, no cambiarse de golpe.

## 6. Flujo funcional de abastecimiento

El flujo de negocio previsto es:

Ventas y existencias → análisis de necesidades → pedido sugerido, urgente o extraordinario → autorización administrativa → órdenes separadas por proveedor → recepción física → actualización de inventario y Kardex.

Crear o autorizar un pedido y crear una orden no debe aumentar existencias. El inventario se actualiza cuando se registra una recepción física válida mediante el proceso correspondiente.

## 7. Reglas para continuar la refactorización

1. Trabajar únicamente en ramas de desarrollo, por ahora `feature/modulo-pedidos`.
2. No modificar `main` ni desplegar a producción como parte de esta etapa.
3. No ejecutar migraciones SQL ni modificar datos reales como consecuencia de una tarea de organización del frontend.
4. Antes de extraer código, identificar las funciones, variables globales, selectores HTML, listeners y módulos que dependen de él.
5. Extraer una responsabilidad por cambio pequeño; no mover simultáneamente varios módulos.
6. Después de cada extracción, comprobar carga de la aplicación y probar los procesos afectados en Preview.
7. No cambiar la interfaz ni el comportamiento funcional durante una extracción cuyo objetivo sea únicamente reorganizar código.
8. Mantener este documento sincronizado con la estructura real del repositorio.

## 8. Próximo paso técnico

Hacer un mapa de dependencias del bloque principal que permanece en `index.html`. La primera extracción futura debe elegirse por bajo acoplamiento y pruebas disponibles; no se debe decidir solo por el tamaño del bloque.

Hasta completar ese mapa, mantener el código legado donde está es más seguro que moverlo a ciegas.

## 9. Dependencias compartidas observadas

La lectura estática de los módulos muestra que la separación de archivos todavía convive con dependencias globales. Esta tabla registra referencias encontradas en el código; no significa que todas sean errores, pero sí que deben considerarse antes de modificar contratos.

| Módulo | Dependencias compartidas encontradas |
| --- | --- |
| Inventario | `sb`, `CO`, `toast`, `DrosaludPedidos`. |
| Caja | `sb`, `CO`, `toast`, `go`. |
| Compras | `sb`, `CO`, `show`. |
| Órdenes de compra | `sb`, `P`, `invCargarDatos`, `window.__drosaludRole`, `window.__ocProviders`. |
| Core | Recibe referencias del código legado: `sb`, `CO`, `go`. |
| Cotizaciones | `DrosaludCore`. |
| Pedidos | `sb`, `P`, `C`, `CO`. |
| Historial de ventas | `H`, `sb`, `toast`, `go`. |
| Historial de precios | `sb`, `P`. |

### Implicaciones para la siguiente extracción

- `sb` es el cliente compartido de Supabase.
- `P`, `C`, `H` y `CO` son datos que el código legado mantiene en variables globales.
- `show`, `go` y `toast` son funciones globales usadas por más de un área.
- Órdenes de compra necesita conocer el rol y actualizar inventario después de una recepción.
- Pedidos consulta datos compartidos del catálogo, clientes y cotizaciones.

Por este acoplamiento, no se debe cambiar todavía el modo de carga a `type="module"`, renombrar variables globales ni convertir los scripts a ES Modules como una sola operación. Primero se deben definir contratos explícitos y migrar una dependencia a la vez.

