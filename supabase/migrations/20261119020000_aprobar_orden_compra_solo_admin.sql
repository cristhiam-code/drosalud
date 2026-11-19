CREATE OR REPLACE FUNCTION public.aprobar_orden_compra(p_orden_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_admin_drosalud() THEN
  RAISE EXCEPTION 'Solo el administrador puede aprobar órdenes de compra';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ordenes_compra_items WHERE orden_id=p_orden_id) THEN
  RAISE EXCEPTION 'No se puede aprobar una orden vacía';
 END IF;
 UPDATE public.ordenes_compra
 SET estado='aprobada', actualizado_en=now()
 WHERE id=p_orden_id AND estado='borrador';
 IF NOT FOUND THEN RAISE EXCEPTION 'La orden no existe o no está en borrador'; END IF;
END $function$
;
