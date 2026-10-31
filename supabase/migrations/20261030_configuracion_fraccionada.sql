-- Configuración de venta fraccionada por producto.
-- Los precios de productos siguen guardándose por empaque completo.
ALTER TABLE public.productos
  ADD COLUMN IF NOT EXISTS unidades_por_caja integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS unidades_por_venta integer NOT NULL DEFAULT 1;

-- Los productos que ya estaban marcados como fraccionables usaban grupos de 10.
UPDATE public.productos
SET unidades_por_caja = 10, unidades_por_venta = 10
WHERE fraccionable = true
  AND unidades_por_caja = 1
  AND unidades_por_venta = 1;

ALTER TABLE public.productos
  DROP CONSTRAINT IF EXISTS productos_unidades_por_caja_check,
  DROP CONSTRAINT IF EXISTS productos_unidades_por_venta_check;
ALTER TABLE public.productos
  ADD CONSTRAINT productos_unidades_por_caja_check CHECK (unidades_por_caja >= 1),
  ADD CONSTRAINT productos_unidades_por_venta_check CHECK (unidades_por_venta >= 1 AND unidades_por_venta <= unidades_por_caja);

COMMENT ON COLUMN public.productos.unidades_por_caja IS 'Cantidad de unidades individuales contenidas en el empaque cuyo costo y precio están guardados en el catálogo.';
COMMENT ON COLUMN public.productos.unidades_por_venta IS 'Cantidad de unidades individuales por cada incremento de venta fraccionada.';
