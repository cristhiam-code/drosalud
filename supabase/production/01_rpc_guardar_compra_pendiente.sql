-- PRODUCCIÓN / SCRIPT 1 DE 2
-- Ejecutar solo tras autorización expresa.
-- No modifica datos históricos ni costos reales ni ganancia.

BEGIN;

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
  IF p_estado IS NULL OR p_estado NOT IN ('pendiente','cotizando','comprado','entregado','cancelado') THEN
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
      owner_id,producto_nombre,cantidad,proveedor_id,costo_estimado,
      estado,notas,recibo_id,recibo_item_id
    ) VALUES (
      v_uid,trim(p_producto_nombre),p_cantidad,p_proveedor_id,p_costo_estimado,
      p_estado,p_notas,p_recibo_id,p_recibo_item_id
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

COMMIT;