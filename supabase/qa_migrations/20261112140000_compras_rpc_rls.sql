-- Tarea 3: centralizar escrituras de compras y propuestas en RPC.
-- Aplicar primero en drosalud-pruebas. No ejecutar en catalogo sin autorización.

CREATE OR REPLACE FUNCTION public.guardar_compra_pendiente(
  p_compra_id uuid,
  p_producto_nombre text,
  p_cantidad integer,
  p_proveedor_id uuid,
  p_costo_estimado numeric,
  p_estado text,
  p_notas text,
  p_recibo_id uuid,
  p_recibo_item_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_admin boolean := public.es_admin_drosalud();
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.es_usuario_drosalud() THEN
    RAISE EXCEPTION 'Usuario no autorizado';
  END IF;

  IF nullif(trim(p_producto_nombre), '') IS NULL THEN
    RAISE EXCEPTION 'Escribe el medicamento.';
  END IF;
  IF p_cantidad IS NULL OR p_cantidad < 1 THEN
    RAISE EXCEPTION 'La cantidad debe ser al menos 1.';
  END IF;
  IF p_costo_estimado IS NOT NULL AND p_costo_estimado < 0 THEN
    RAISE EXCEPTION 'El costo estimado no puede ser negativo.';
  END IF;
  IF p_estado NOT IN ('pendiente','cotizando','comprado','entregado','cancelado') THEN
    RAISE EXCEPTION 'Estado de compra no válido.';
  END IF;
  IF p_proveedor_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.proveedores WHERE id=p_proveedor_id) THEN
    RAISE EXCEPTION 'El proveedor no existe.';
  END IF;

  IF p_recibo_id IS NOT NULL
     AND NOT (v_admin OR public.es_recibo_propio_drosalud(p_recibo_id)) THEN
    RAISE EXCEPTION 'No tienes permiso para vincular la compra a ese recibo.';
  END IF;
  IF p_recibo_item_id IS NOT NULL THEN
    IF p_recibo_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.recibo_items
      WHERE id=p_recibo_item_id AND recibo_id=p_recibo_id
    ) THEN
      RAISE EXCEPTION 'La línea no pertenece al recibo indicado.';
    END IF;
  END IF;

  IF p_compra_id IS NULL THEN
    INSERT INTO public.compras_pendientes (
      owner_id, producto_nombre, cantidad, proveedor_id,
      costo_estimado, estado, notas, recibo_id, recibo_item_id
    ) VALUES (
      v_uid, trim(p_producto_nombre), p_cantidad, p_proveedor_id,
      p_costo_estimado, p_estado, p_notas, p_recibo_id, p_recibo_item_id
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.compras_pendientes
       SET producto_nombre=trim(p_producto_nombre),
           cantidad=p_cantidad,
           proveedor_id=p_proveedor_id,
           costo_estimado=p_costo_estimado,
           estado=p_estado,
           notas=p_notas,
           recibo_id=p_recibo_id,
           recibo_item_id=p_recibo_item_id,
           actualizado_en=now()
     WHERE id=p_compra_id
       AND (owner_id=v_uid OR v_admin)
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'No se encontró la compra o no tienes permiso.';
    END IF;
  END IF;

  RETURN v_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid) TO authenticated;

-- Sincronización de RPCs existentes en catalogo hacia QA.
CREATE OR REPLACE FUNCTION public.aplicar_propuestas_precios_venta(p_productos uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
 v_count integer := 0;
 v_row record;
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_usuario_drosalud() THEN
  RAISE EXCEPTION 'Usuario no autorizado';
 END IF;
 IF p_productos IS NULL OR cardinality(p_productos)=0 THEN
  RAISE EXCEPTION 'Selecciona productos aprobados';
 END IF;
 FOR v_row IN
  SELECT producto_id,precio_venta_sugerido
  FROM public.propuestas_precios_venta
  WHERE producto_id=ANY(p_productos) AND estado='aprobado'
  FOR UPDATE
 LOOP
  UPDATE public.productos SET precio_venta=v_row.precio_venta_sugerido,actualizado_en=now()
   WHERE id=v_row.producto_id;
  UPDATE public.propuestas_precios_venta
   SET estado='aplicado',aplicado_en=now(),revisado_por=auth.uid(),revisado_en=now()
   WHERE producto_id=v_row.producto_id;
  v_count := v_count+1;
 END LOOP;
 RETURN v_count;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.aplicar_propuestas_precios_venta(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aplicar_propuestas_precios_venta(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.aprobar_propuesta_precio_venta(
 p_producto_id uuid, p_precio numeric, p_observacion text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_usuario_drosalud() THEN
  RAISE EXCEPTION 'Usuario no autorizado';
 END IF;
 IF p_precio IS NULL OR p_precio<=0 OR p_precio>=1000000000 THEN
  RAISE EXCEPTION 'Precio de venta inválido';
 END IF;
 UPDATE public.propuestas_precios_venta
 SET precio_venta_sugerido=p_precio,
     estado='aprobado',
     observacion=nullif(left(trim(coalesce(p_observacion,'')),500),''),
     revisado_por=auth.uid(),revisado_en=now()
 WHERE producto_id=p_producto_id AND estado='pendiente';
 IF NOT FOUND THEN RAISE EXCEPTION 'La propuesta no existe o ya fue revisada'; END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.aprobar_propuesta_precio_venta(uuid,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aprobar_propuesta_precio_venta(uuid,numeric,text) TO authenticated;

-- Función/trigger que existe en catalogo y faltaba en QA.
CREATE OR REPLACE FUNCTION public.fijar_costo_real_item_venta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.costo_real_unitario IS NULL THEN
    NEW.costo_real_unitario := NEW.precio_compra;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_fijar_costo_real_item_venta ON public.recibo_items;
CREATE TRIGGER trg_fijar_costo_real_item_venta
BEFORE INSERT ON public.recibo_items
FOR EACH ROW EXECUTE FUNCTION public.fijar_costo_real_item_venta();

-- Las cuatro tablas quedan consultables por el equipo; las escrituras ordinarias
-- quedan reservadas a funciones SECURITY DEFINER. DELETE directo solo admin.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('ordenes_compra','ordenes_compra_items','propuestas_precios_venta','compras_pendientes')
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I',r.policyname,r.schemaname,r.tablename);
  END LOOP;
END;
$$;

ALTER TABLE public.ordenes_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ordenes_compra_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.propuestas_precios_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compras_pendientes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.ordenes_compra, public.ordenes_compra_items,
  public.propuestas_precios_venta, public.compras_pendientes FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON TABLE public.ordenes_compra, public.ordenes_compra_items,
  public.propuestas_precios_venta, public.compras_pendientes TO authenticated;

CREATE POLICY ordenes_compra_select_equipo ON public.ordenes_compra
FOR SELECT TO authenticated USING (public.es_usuario_drosalud());
CREATE POLICY ordenes_compra_delete_admin ON public.ordenes_compra
FOR DELETE TO authenticated USING (public.es_admin_drosalud());

CREATE POLICY ordenes_compra_items_select_equipo ON public.ordenes_compra_items
FOR SELECT TO authenticated USING (public.es_usuario_drosalud());
CREATE POLICY ordenes_compra_items_delete_admin ON public.ordenes_compra_items
FOR DELETE TO authenticated USING (public.es_admin_drosalud());

CREATE POLICY propuestas_precios_select_equipo ON public.propuestas_precios_venta
FOR SELECT TO authenticated USING (public.es_usuario_drosalud());
CREATE POLICY propuestas_precios_delete_admin ON public.propuestas_precios_venta
FOR DELETE TO authenticated USING (public.es_admin_drosalud());

CREATE POLICY compras_pendientes_select_propias_admin ON public.compras_pendientes
FOR SELECT TO authenticated
USING (public.es_admin_drosalud() OR (public.es_usuario_drosalud() AND owner_id=auth.uid()));
CREATE POLICY compras_pendientes_delete_admin ON public.compras_pendientes
FOR DELETE TO authenticated USING (public.es_admin_drosalud());
