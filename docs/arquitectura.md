# Arquitectura actual de Drosalud

## Objetivo
Drosalud debe poder abrirse, comprenderse, corregirse y mantenerse desde un editor convencional como Visual Studio Code. No debe depender de una conversación ni de una persona que recuerde cómo se construyó.

## Estructura real en esta etapa

```text
drosalud/
├── index.html
├── modules/
│   ├── pedidos.js
│   └── pedidos.css
├── supabase/
│   └── migrations/
│       ├── 20261112210000_create_pedidos_module.sql
│       ├── 20261112220000_link_products_on_pedido_authorization.sql
│       └── 20261112223000_add_order_generation_idempotency.sql
└── docs/
    ├── arquitectura.md
    └── modulo-pedidos.md
```

### Responsabilidades
- **index.html:** carcasa principal de la aplicación, inicio de sesión, navegación y módulos históricos que todavía no se han extraído.
- **modules/pedidos.js:** lógica del módulo PEDIDOS. Consulta los datos, calcula el pedido sugerido, guarda borradores, envía solicitudes, autoriza y genera órdenes.
- **modules/pedidos.css:** estilos exclusivos de PEDIDOS.
- **supabase/migrations/:** cambios versionados del esquema, seguridad, vistas y funciones SQL.
- **docs/:** reglas de negocio y decisiones de arquitectura.

## Integración del módulo PEDIDOS
La aplicación comparte el cliente de Supabase mediante `window.sb`. El módulo expone `window.DrosaludPedidos.load()`, invocado por la navegación existente al abrir PEDIDOS. La lógica de PEDIDOS no se mezcla con la lógica del POS.

Esta integración es intencional y pequeña. No significa que todos los módulos antiguos ya estén separados.

## Flujo de abastecimiento
Ventas → análisis de rotación y existencias → pedido sugerido / urgente / extraordinario → autorización administrativa → una o varias órdenes por proveedor → recepción física → inventario y Kardex → informes.

La autorización de un pedido y la generación de órdenes no cambian el inventario. Solo la recepción física válida registra movimientos.

## Seguridad y ambientes
- Los cambios se desarrollan en ramas de trabajo.
- Los previews de Vercel se utilizan para pruebas contra `drosalud-pruebas`.
- `main` y el dominio de producción no se modifican durante el desarrollo de un módulo.
- Los permisos se validan en las funciones SQL; ocultar botones en el frontend no sustituye la seguridad del servidor.

## Cómo abrirlo en Visual Studio Code
1. Clona el repositorio `cristhiam-code/drosalud`.
2. Abre la carpeta del proyecto en Visual Studio Code.
3. Para revisar PEDIDOS, abre `modules/pedidos.js` y `modules/pedidos.css`.
4. Para revisar la estructura de base de datos, abre la migración dentro de `supabase/migrations/`.
5. Trabaja en una rama y prueba en el preview antes de integrar cambios.

## Estrategia de evolución
La extracción del resto del frontend será gradual, módulo por módulo. No se hará una conversión masiva del archivo principal: cada separación deberá conservar las funciones existentes y pasar pruebas antes de continuar.
