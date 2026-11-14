-- Restaura en QA las vistas de aplicación exactas de producción.
-- Esto mantiene la visibilidad de costo, ganancia y costo de mensajero
-- que la operación productiva ya tiene habilitada para el equipo.
-- Todas las vistas continúan usando security_invoker=true.

CREATE OR REPLACE VIEW public.cotizacion_venta_items_app WITH (security_invoker = true) AS
SELECT i.id,
    i.cotizacion_id,
    i.producto_id,
    i.nombre,
    i.cantidad,
    i.precio_compra::numeric AS precio_compra,
    i.precio_venta,
    i.presentacion,
    i.unidades_por_presentacion
   FROM cotizacion_venta_items i
     JOIN cotizaciones_venta c ON c.id = i.cotizacion_id
  WHERE es_usuario_drosalud() AND (es_admin_drosalud() OR c.owner_id = (( SELECT auth.uid() AS uid)));

CREATE OR REPLACE VIEW public.cotizaciones_venta_app WITH (security_invoker = true) AS
SELECT id,
    numero,
    owner_id,
    cliente_id,
    cliente_nombre,
    cliente_cedula,
    cliente_telefono,
    vendedor,
    descuento,
    domicilio,
    subtotal,
    total,
    estado,
    valida_hasta,
    recibo_id,
    creado_en
   FROM cotizaciones_venta
  WHERE es_usuario_drosalud() AND (es_admin_drosalud() OR owner_id = (( SELECT auth.uid() AS uid)));

CREATE OR REPLACE VIEW public.recibo_items_app WITH (security_invoker = true) AS
SELECT id,
    recibo_id,
    producto_id,
    nombre,
    cantidad,
    precio_compra,
    precio_venta,
    costo_real_unitario,
    presentacion,
    unidades_por_presentacion
   FROM recibo_items i
  WHERE es_usuario_drosalud();

CREATE OR REPLACE VIEW public.recibos_app WITH (security_invoker = true) AS
SELECT id,
    numero,
    cliente_id,
    cliente_nombre,
    total,
    ganancia,
    creado_en,
    descuento,
    domicilio,
    forma_pago,
    cliente_cedula,
    cliente_telefono,
    cliente_direccion,
    recibido,
    anulado,
    anulado_en,
    motivo_anulacion,
    vendedor,
    costo_mensajero::numeric AS costo_mensajero,
    creado_por
   FROM recibos
  WHERE es_usuario_drosalud();
