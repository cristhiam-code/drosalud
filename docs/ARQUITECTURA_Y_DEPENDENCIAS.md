# Arquitectura y dependencias de DROSalud

## Objetivo

Mantener la aplicación estática actual estable mientras se separan responsabilidades de forma incremental. No se hará una reescritura completa ni se cambiará el comportamiento del POS, impresión, pedidos, recepción o permisos por razones estéticas.

## Estado observado en la rama QA

- `index.html` contiene el shell, navegación, vistas principales, estilos globales, selección cerrada de entorno, creación del cliente Supabase y parte de la lógica de la aplicación.
- `base.js` contiene funciones y estado compartidos por la aplicación.
- `modules/` contiene módulos JavaScript y CSS separados, entre ellos Pedidos, Recepción, Informes, Ayuda/Sistema, Gestión del negocio, Exportaciones y Conteo.
- `supabase.js`, `xlsx.mini.min.js`, `html5-qrcode.min.js` y `qrcode.js` son dependencias estáticas cargadas por la página.
- Los módulos actuales no son paquetes independientes: algunos consumen el cliente `sb` y utilidades/estado globales del shell. Por eso no se deben mover archivos ni cambiar el orden de carga sin identificar primero sus dependencias reales.

## Capas objetivo

1. **Presentación**: HTML de vistas, componentes DOM y CSS. No debe ejecutar SQL ni decidir permisos.
2. **Módulos de negocio**: Pedidos, Recepción, Ventas, Inventario/Kardex, Caja, Informes y Ayuda. Cada módulo controla su propia vista y eventos.
3. **Servicios**: funciones reutilizables para ventas, compras, inventario, clientes, caja y reportes. Encapsulan llamadas a Supabase.
4. **Acceso a datos**: cliente Supabase único, consultas y RPC. No se crea un cliente nuevo dentro de cada módulo.
5. **Dominio/utilidades**: validaciones puras, conversión de presentaciones, cantidades, dinero, fechas y estados.
6. **Configuración**: selección de entorno por lista cerrada de hosts. Ningún módulo puede elegir o cambiar el proyecto Supabase.

## Reglas de dependencias

- `index.html` inicializa el entorno y el cliente una sola vez.
- Los módulos reciben o consumen una interfaz compartida documentada; no deben crear otro cliente Supabase.
- Un módulo no debe importar ni manipular el estado interno de otro módulo.
- La comunicación entre módulos se realiza mediante servicios compartidos o eventos explícitos, no mediante referencias cruzadas.
- Las reglas de autorización se validan en backend/RLS/RPC. Ocultar botones es solo una ayuda visual.
- Las funciones de dominio deben poder probarse sin DOM ni conexión a Supabase.
- No añadir una librería para resolver algo que pueda resolverse con las dependencias ya instaladas.
- Mantener versiones y archivos de dependencias existentes; no actualizar bibliotecas de impresión, Excel, QR o Supabase en el mismo cambio que una refactorización funcional.
- No introducir TypeScript, bundlers ni frameworks en una tarea de estabilización sin una decisión de arquitectura y un plan de migración separado.

## Estructura objetivo incremental

```text
/
  index.html                 # shell, navegación y puntos de montaje
  base.js                    # bootstrap y compatibilidad temporal
  supabase.js                # cliente/librería existente
  modules/
    <modulo>.js              # interfaz y eventos del módulo
    <modulo>.css             # estilos exclusivos del módulo
  services/
    ventas.js                # operaciones de ventas
    compras.js               # órdenes, documentos y recepción
    inventario.js            # saldos y movimientos Kardex
    reportes.js              # consultas agregadas
  domain/
    cantidades.js            # unidades, empaques y fraccionamiento
    dinero.js                # cálculos monetarios y redondeos
    estados.js               # estados y transiciones válidas
  docs/
    ARQUITECTURA_Y_DEPENDENCIAS.md
    GUIA_OPERATIVA.md
```

Esta es la estructura objetivo, no una afirmación de que todos esos archivos ya existan. Los nuevos archivos se incorporarán cuando una función se extraiga y sus pruebas estén listas.

## Secuencia segura de refactorización

1. Inventariar las funciones globales y los módulos que las consumen.
2. Añadir pruebas de contrato antes de mover una función.
3. Extraer primero funciones puras de dominio (cantidades, dinero, fechas y estados).
4. Extraer servicios de datos por proceso, manteniendo las mismas consultas y RPC.
5. Adaptar un módulo a la vez mediante una interfaz explícita.
6. Mantener adaptadores temporales para las funciones globales mientras haya consumidores antiguos.
7. Ejecutar pruebas, revisar diff y probar el flujo completo en QA después de cada extracción.
8. Retirar compatibilidad antigua solo cuando no existan consumidores.

## Límites de seguridad y publicación

- Cambios de código y migraciones de esta etapa se limitan a la rama QA y al proyecto Supabase QA.
- No modificar `main`, el dominio productivo, las variables productivas ni los datos productivos.
- No fusionar ni desplegar a producción sin aprobación expresa.
- No ejecutar cambios destructivos de datos para limpiar inconsistencias históricas.
- No modificar el flujo de Pedidos ni los permisos generales del vendedor durante la reorganización.
- No reabrir ni crear sesiones de conteo físico como parte de esta refactorización.

## Criterios de aceptación

- Cada módulo tiene responsabilidad y dependencias documentadas.
- No hay clientes Supabase duplicados ni selección de entorno dentro de módulos.
- No hay dependencias circulares ni referencias ocultas entre módulos.
- Las funciones extraídas tienen pruebas unitarias/contratos.
- Los flujos de venta, impresión, fraccionamiento, pedido, recepción y Kardex mantienen su comportamiento.
- `npm test` y el CI pasan.
- La validación funcional autenticada en QA se completa antes de considerar lista una publicación.


## Mapa real de carga y dependencias (auditoría estática)

La página carga actualmente los scripts en este orden:

1. `supabase.js` — biblioteca cliente.
2. `base.js` — inicialización compartida y lógica central.
3. `xlsx.mini.min.js`, `html5-qrcode.min.js`, `qrcode.js` — bibliotecas de Excel y códigos QR.
4. `modules/gestion-negocio.js`
5. `modules/ayuda-sistema.js`
6. `modules/pedidos.js`
7. `modules/recepcion-mercancia.js`
8. `modules/conteo-fisico-api.js`
9. `modules/conteo-fisico.js`
10. `modules/informes.js`

CSS modular cargado por el shell: Pedidos, Recepción, Conteo, Informes, Ayuda/Sistema, Gestión del negocio y Exportaciones.

| Módulo actual | Dependencias globales observadas estáticamente |
|---|---|
| Gestión del negocio | `sb`, `CO`, `show` |
| Ayuda/Sistema | DOM y API de rendimiento del navegador; no consume `sb` |
| Pedidos | `sb`, `C`, `CO`, `esc`, `money`, `go`, `show` |
| Recepción | `sb`, `P`, `C`, `CO`, `esAdminDrosalud`, `esc`, `money`, `show`, `XLSX` |
| Conteo API | `sb` |
| Conteo UI | `sb`, `CO`, `esc` |
| Informes | `sb`, `C`, `CO`, `esc`, `money`, `XLSX` |

Este mapa es una fotografía de referencias identificadas por búsqueda estática; debe actualizarse al cambiar los módulos. No demuestra por sí solo que una referencia se use en todos los caminos de ejecución.

## Deuda técnica priorizada

- **Alta:** `index.html` sigue concentrando el shell, selección de entorno, creación del cliente, vistas y parte de la lógica; `base.js` también es grande. Reducirlos gradualmente sin alterar impresión ni POS.
- **Alta:** varios módulos acceden a variables y funciones globales del shell (`sb`, `show`, `esc`, `money`, estados compartidos). Documentar y reemplazar esas dependencias por interfaces explícitas, módulo por módulo.
- **Media:** algunas vistas y estilos de módulos permanecen declarados dentro de `index.html`; moverlos solo cuando el HTML y sus selectores estén cubiertos por pruebas.
- **Media:** bibliotecas de terceros se cargan como scripts globales. Mantener una lista de versiones/origen y no cambiarlas junto con refactorizaciones funcionales.
- **No hacer:** no cambiar a un framework ni añadir un empaquetador solo para resolver la deuda de organización. Primero estabilizar límites de módulos y pruebas.


## Primera extracción completada

Se extrajeron los formateadores puros a `domain/formatters.js`:
- `esc`: escape de texto para inserción HTML.
- `norm`: normalización de texto para búsquedas.
- `money`: formato monetario COP.

El archivo no depende del DOM, del cliente Supabase ni del estado del negocio. Expone una interfaz congelada en `window.DrosaludFormatters`; el shell conserva los nombres `esc`, `norm` y `money` como adaptador temporal para que los módulos existentes sigan funcionando sin cambios. El script se carga después de `base.js` y antes del script inline que lo consume.

Esta extracción no cambia las fórmulas ni la presentación de los valores. Se añadió un contrato de prueba para proteger el orden de carga y la independencia del dominio.


## Segunda extracción completada: presentaciones y cantidades de venta

Se extrajeron a `domain/presentaciones.js` las funciones puras:
- Factor de unidades por presentación.
- Conversión de cantidad de cajas a empaques.
- Conversión de precio por unidad a precio por caja.
- Preparación de las líneas que se envían a venta/cotización para productos normales y fraccionables.

El módulo no accede al DOM, Supabase, almacenamiento local ni estado global del carrito. El shell conserva el contrato de nombres mediante `window.DrosaludPresentations` y una asignación local, de modo que las pantallas y los módulos existentes mantienen sus llamadas.

Se agregaron pruebas Node nativas para casos normales, caja, unidades sueltas, caja más unidades sueltas y carrito vacío. No se agregó ninguna dependencia externa. `npm test` ahora incluye pruebas Python, pruebas puras del dominio y revisión de sintaxis JavaScript.


## Tercera extracción completada: precios

Se extrajeron a `domain/precios.js` las reglas puras:
- Calcular el precio sugerido a partir del costo, porcentaje de ganancia y regla de redondeo configurada.
- Respetar el precio de venta manual cuando ya existe.
- Devolver ausencia de precio cuando no existe precio manual ni costo positivo.

El módulo recibe la configuración como argumento; no lee `cfg`, no consulta productos y no accede a Supabase. El shell conserva las funciones `price(c)` y `pv(producto)` como adaptadores temporales para mantener la API existente.

Se agregaron pruebas para precio manual, margen sugerido, redondeo hacia arriba y costo vacío/cero.


## Cuarta extracción completada: cálculos monetarios

Se extrajeron a `domain/dinero.js`:
- Subtotal de líneas de recibo, calculado con precio por unidad base multiplicado por cantidad.
- Porcentaje de ganancia sobre costo de compra: `(precio de venta - costo) / costo × 100`, con protección para costo cero/no positivo.

Esto aclara que el porcentaje configurado en “Ganancia sobre la compra” es un *recargo sobre costo*, no un margen porcentual sobre el precio de venta. El módulo recibe los datos como argumentos y no depende de UI ni Supabase. El shell mantiene los nombres `sub` y `mg` como adaptadores temporales.

Se añadieron pruebas de subtotal, costo cero y porcentajes positivos/negativos.


La extracción de presentaciones también incluye ahora el cálculo de unidades base y el total del carrito para productos fraccionables y no fraccionables. La actualización de `q` del carrito sigue siendo responsabilidad del shell; el cálculo que utiliza es una función pura del dominio.


## Primera separación de servicios: ventas

Se creó `services/ventas.js` para encapsular las llamadas RPC de registrar venta y crear cotización. El cliente Supabase se recibe como argumento explícito; el servicio no lee variables globales ni accede al DOM. Así se mantiene una sola instancia del cliente y el servicio se puede probar con un cliente falso sin tocar la base de datos.

El shell conserva el flujo visual y entrega el cliente, la cabecera y las líneas al servicio. Se mantiene la misma RPC, los mismos nombres de argumentos y el mismo mensaje cuando no vuelve un recibo válido. Las pruebas comprueban el contrato y la propagación de errores.
