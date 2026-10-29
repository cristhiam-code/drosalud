# Evolución de Drosalud

Este trabajo se desarrolla en la rama `mejoras-drosalud`. No modifica `main`, Supabase de producción ni despliega cambios.

## Objetivo

Conservar el diseño y los flujos actuales de ventas, recibos, catálogo, clientes e historial. Evolucionar Drosalud como herramienta ligera para una operación bajo demanda, sin inventario ni control de existencias.

## Etapas

1. **Utilidad real por venta**
   - Diferenciar costo estimado y costo real.
   - Registrar el costo efectivamente pagado al proveedor.
   - Acordar y aplicar un criterio único para distribuir descuentos y calcular utilidad neta.
   - No alterar los recibos históricos.

2. **Proveedores y cotizaciones**
   - Contactos de proveedores.
   - Registro de consultas de disponibilidad y precios por producto.
   - Historial de cotizaciones para comparar antes de comprar.

3. **Compras pendientes bajo demanda**
   - Registrar un medicamento que falta por conseguir, incluso después de haber vendido.
   - Relacionar la solicitud con el recibo cuando corresponda.
   - Marcar estados pendiente, cotizando, comprado, entregado o cancelado.
   - No crear existencias ni movimientos de inventario.

4. **Seguimiento comercial**
   - Aprovechar el historial actual de clientes.
   - Mostrar oportunidades de recompra y tareas de seguimiento sin duplicar clientes.
   - Mantener WhatsApp como canal manual de contacto.

5. **Panel sencillo**
   - Ventas, utilidad calculada con costo real, solicitudes por resolver, compras y clientes por contactar.

## Migración SQL inicial

`supabase-migration-proveedores-compras.sql` agrega tablas nuevas para proveedores, solicitudes de compra y cotizaciones. Las tablas nuevas usan `owner_id = auth.uid()` en sus políticas RLS. La migración no modifica tablas actuales y no debe ejecutarse en producción durante esta etapa.

## Criterios de seguridad y aceptación

- No tocar `main` ni desplegar producción.
- No eliminar ni reescribir recibos existentes.
- No implementar inventario ni existencias.
- Revisar políticas y esquema antes de cualquier cambio sobre tablas actuales.
- Probar los flujos con datos de prueba en un entorno separado.
- Presentar los cambios para aprobación antes de integrarlos.
