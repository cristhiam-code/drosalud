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
