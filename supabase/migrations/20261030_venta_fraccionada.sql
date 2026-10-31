-- Venta fraccionada de medicamentos en Drosalud.
-- Cambio aditivo: registros anteriores conservan presentación Unidad y factor 1.
-- No crea existencias ni modifica cantidades, precios o ventas históricas.

ALTER TABLE public.productos
  ADD COLUMN IF NOT EXISTS fraccionable boolean NOT NULL DEFAULT false;

ALTER TABLE public.recibo_items
  ADD COLUMN IF NOT EXISTS presentacion text NOT NULL DEFAULT 'Unidad',
  ADD COLUMN IF NOT EXISTS unidades_por_presentacion integer NOT NULL DEFAULT 1;

ALTER TABLE public.cotizacion_venta_items
  ADD COLUMN IF NOT EXISTS presentacion text NOT NULL DEFAULT 'Unidad',
  ADD COLUMN IF NOT EXISTS unidades_por_presentacion integer NOT NULL DEFAULT 1;

ALTER TABLE public.recibo_items
  DROP CONSTRAINT IF EXISTS recibo_items_unidades_presentacion_check;
ALTER TABLE public.recibo_items
  ADD CONSTRAINT recibo_items_unidades_presentacion_check
  CHECK (unidades_por_presentacion >= 1);

ALTER TABLE public.cotizacion_venta_items
  DROP CONSTRAINT IF EXISTS cotizacion_venta_items_unidades_presentacion_check;
ALTER TABLE public.cotizacion_venta_items
  ADD CONSTRAINT cotizacion_venta_items_unidades_presentacion_check
  CHECK (unidades_por_presentacion >= 1);

COMMENT ON COLUMN public.productos.fraccionable IS
  'Indica si el producto se vende en sobres de 10 unidades; no representa inventario.';
COMMENT ON COLUMN public.recibo_items.presentacion IS
  'Presentación comercial vendida, guardada como fotografía histórica de la venta.';
COMMENT ON COLUMN public.recibo_items.unidades_por_presentacion IS
  'Cantidad de unidades individuales por presentación vendida.';
COMMENT ON COLUMN public.cotizacion_venta_items.presentacion IS
  'Presentación comercial cotizada, guardada como fotografía histórica de la cotización.';
COMMENT ON COLUMN public.cotizacion_venta_items.unidades_por_presentacion IS
  'Cantidad de unidades individuales por presentación cotizada.';
