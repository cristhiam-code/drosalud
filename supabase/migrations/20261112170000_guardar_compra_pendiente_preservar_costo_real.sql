-- Preserva costo_real si el cliente omite el campo.
-- La pantalla envía p_actualizar_costo_real=true para cambiarlo explícitamente.
-- PRODUCCIÓN / SCRIPT (a) v2
-- RPC segura para compras pendientes.
-- Incluye p_costo_real (campo de saveBuy), owner_id desde auth.uid(),
-- y bloquea cambios de recibo/línea cuando la compra ya tiene costo_real.
-- No modifica costo_real_unitario de recibo_items ni ganancia de recibos.

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
  p_recibo_item_id uuid,
  p_costo_real numeric DEFAULT NULL,
  p_actualizar_costo_real boolean DEFAULT false
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
  v_compra public.compras_pendientes%rowtype;
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
  IF p_actualizar_costo_real AND p_costo_real IS NOT NULL AND p_costo_real < 0 THEN
    RAISE EXCEPTION 'El costo real no puede ser negativo.';
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
    IF p_actualizar_costo_real AND p_costo_real IS NOT NULL THEN
      RAISE EXCEPTION 'Para actualizar el costo real de una línea utiliza guardar_compra_con_costo_real.';
    END IF;
  END IF;

  IF p_compra_id IS NULL THEN
    INSERT INTO public.compras_pendientes (
      owner_id,producto_nombre,cantidad,proveedor_id,costo_estimado,
      costo_real,estado,notas,recibo_id,recibo_item_id
    ) VALUES (
      v_uid,trim(p_producto_nombre),p_cantidad,p_proveedor_id,p_costo_estimado,
      CASE WHEN p_actualizar_costo_real THEN p_costo_real ELSE NULL END,p_estado,p_notas,p_recibo_id,p_recibo_item_id
    )
    RETURNING id INTO v_id;
  ELSE
    SELECT * INTO v_compra
    FROM public.compras_pendientes
    WHERE id=p_compra_id AND (owner_id=v_uid OR v_admin)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró la compra o no tienes permiso.';
    END IF;

    IF v_compra.costo_real IS NOT NULL
       AND (
         v_compra.recibo_id IS DISTINCT FROM p_recibo_id
         OR v_compra.recibo_item_id IS DISTINCT FROM p_recibo_item_id
       ) THEN
      RAISE EXCEPTION 'Esta compra ya tiene costo real. No cambies el recibo ni la línea vinculada.';
    END IF;

    UPDATE public.compras_pendientes
       SET producto_nombre=trim(p_producto_nombre),
           cantidad=p_cantidad,
           proveedor_id=p_proveedor_id,
           costo_estimado=p_costo_estimado,
           costo_real=CASE WHEN p_actualizar_costo_real THEN p_costo_real ELSE v_compra.costo_real END,
           estado=p_estado,
           notas=p_notas,
           recibo_id=p_recibo_id,
           recibo_item_id=p_recibo_item_id,
           actualizado_en=now()
     WHERE id=p_compra_id
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$function$;

DROP FUNCTION IF EXISTS public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid);
DROP FUNCTION IF EXISTS public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric,boolean);

REVOKE EXECUTE ON FUNCTION public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_compra_pendiente(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric,boolean) TO authenticated;

COMMIT;
