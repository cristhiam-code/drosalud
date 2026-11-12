-- 03_rollback_rls_compras.sql
-- Reversión exclusiva de los cambios de RLS/GRANTS del script (b).
-- Restaura las cinco políticas originales observadas en catalogo.
-- No elimina datos ni revierte la RPC guardar_compra_pendiente.
-- Ejecutar únicamente si se autoriza la reversión.

BEGIN;

DROP POLICY IF EXISTS compras_pendientes_select_propias_admin ON public.compras_pendientes;
DROP POLICY IF EXISTS compras_pendientes_delete_admin ON public.compras_pendientes;
DROP POLICY IF EXISTS ordenes_compra_select_equipo ON public.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_delete_admin ON public.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_items_select_equipo ON public.ordenes_compra_items;
DROP POLICY IF EXISTS ordenes_compra_items_delete_admin ON public.ordenes_compra_items;
DROP POLICY IF EXISTS propuestas_precios_select_equipo ON public.propuestas_precios_venta;
DROP POLICY IF EXISTS propuestas_precios_delete_admin ON public.propuestas_precios_venta;

CREATE POLICY compras_admin_total
ON public.compras_pendientes
FOR ALL TO authenticated
USING (public.es_admin_drosalud())
WITH CHECK (public.es_admin_drosalud());

CREATE POLICY compras_vendedor_propias
ON public.compras_pendientes
FOR ALL TO authenticated
USING (
  public.es_usuario_drosalud()
  AND owner_id=auth.uid()
)
WITH CHECK (
  public.es_usuario_drosalud()
  AND owner_id=auth.uid()
  AND (
    recibo_id IS NULL
    OR public.es_admin_drosalud()
    OR public.es_recibo_propio_drosalud(recibo_id)
  )
);

CREATE POLICY ordenes_compra_equipo
ON public.ordenes_compra
FOR ALL TO authenticated
USING (public.es_usuario_drosalud())
WITH CHECK (public.es_usuario_drosalud());

CREATE POLICY ordenes_compra_items_equipo
ON public.ordenes_compra_items
FOR ALL TO authenticated
USING (public.es_usuario_drosalud())
WITH CHECK (public.es_usuario_drosalud());

CREATE POLICY propuestas_precios_equipo
ON public.propuestas_precios_venta
FOR ALL TO authenticated
USING (public.es_usuario_drosalud())
WITH CHECK (public.es_usuario_drosalud());

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.compras_pendientes
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.ordenes_compra
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.ordenes_compra_items
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.propuestas_precios_venta
TO authenticated;

COMMIT;
