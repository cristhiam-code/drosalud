-- PRODUCCIÓN / SCRIPT 2 DE 2
-- Ejecutar solo después de verificar el script 1 y con autorización expresa.
-- Admin y vendedor: SELECT. INSERT/UPDATE: solo RPC.
-- DELETE directo: admin exclusivamente.

BEGIN;

-- Eliminar únicamente las políticas actuales auditadas en catalogo.
DROP POLICY IF EXISTS compras_admin_total ON public.compras_pendientes;
DROP POLICY IF EXISTS compras_vendedor_propias ON public.compras_pendientes;
DROP POLICY IF EXISTS ordenes_compra_equipo ON public.ordenes_compra;
DROP POLICY IF EXISTS ordenes_compra_items_equipo ON public.ordenes_compra_items;
DROP POLICY IF EXISTS propuestas_precios_equipo ON public.propuestas_precios_venta;

-- Hacer explícito el acceso por privilegios SQL: SELECT y DELETE solamente.
REVOKE ALL ON TABLE
  public.ordenes_compra,
  public.ordenes_compra_items,
  public.propuestas_precios_venta,
  public.compras_pendientes
FROM PUBLIC, anon, authenticated;

GRANT SELECT, DELETE ON TABLE
  public.ordenes_compra,
  public.ordenes_compra_items,
  public.propuestas_precios_venta,
  public.compras_pendientes
TO authenticated;

ALTER TABLE public.ordenes_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ordenes_compra_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.propuestas_precios_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compras_pendientes ENABLE ROW LEVEL SECURITY;

-- SELECT: ambos roles en órdenes, líneas y propuestas.
CREATE POLICY ordenes_compra_select_equipo
ON public.ordenes_compra
FOR SELECT TO authenticated
USING (public.es_usuario_drosalud());

CREATE POLICY ordenes_compra_items_select_equipo
ON public.ordenes_compra_items
FOR SELECT TO authenticated
USING (public.es_usuario_drosalud());

CREATE POLICY propuestas_precios_select_equipo
ON public.propuestas_precios_venta
FOR SELECT TO authenticated
USING (public.es_usuario_drosalud());

-- Compras pendientes: admin ve todo; vendedor conserva solo sus propias filas.
CREATE POLICY compras_pendientes_select_propias_admin
ON public.compras_pendientes
FOR SELECT TO authenticated
USING (
  public.es_admin_drosalud()
  OR (public.es_usuario_drosalud() AND owner_id=auth.uid())
);

-- DELETE directo: solo admin.
CREATE POLICY ordenes_compra_delete_admin
ON public.ordenes_compra
FOR DELETE TO authenticated
USING (public.es_admin_drosalud());

CREATE POLICY ordenes_compra_items_delete_admin
ON public.ordenes_compra_items
FOR DELETE TO authenticated
USING (public.es_admin_drosalud());

CREATE POLICY propuestas_precios_delete_admin
ON public.propuestas_precios_venta
FOR DELETE TO authenticated
USING (public.es_admin_drosalud());

CREATE POLICY compras_pendientes_delete_admin
ON public.compras_pendientes
FOR DELETE TO authenticated
USING (public.es_admin_drosalud());

COMMIT;