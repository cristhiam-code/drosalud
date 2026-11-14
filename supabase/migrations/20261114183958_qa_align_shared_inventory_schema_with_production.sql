-- Alinea reglas e índices de las tablas operativas de QA con el baseline productivo.
-- No modifica datos existentes. Los conteos previos confirmaron cero nulos en estos campos.
-- Se conservan índices adicionales de QA usados por pruebas de ajustes de inventario.

ALTER TABLE public.productos
  ALTER COLUMN precio_compra DROP DEFAULT,
  ALTER COLUMN precio_compra SET NOT NULL,
  ALTER COLUMN actualizado_en SET NOT NULL,
  ALTER COLUMN fraccionable SET NOT NULL,
  ALTER COLUMN unidades_por_caja SET NOT NULL,
  ALTER COLUMN unidades_por_venta SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_movimientos_proveedor
  ON public.inventario_movimientos (proveedor_id, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_ordenes_compra_proveedor_estado
  ON public.ordenes_compra (proveedor_id, estado, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_recepciones_compra_items_producto
  ON public.recepciones_compra_items (producto_id, creado_en DESC);
