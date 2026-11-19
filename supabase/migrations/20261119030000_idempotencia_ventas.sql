ALTER TABLE public.recibos ADD COLUMN IF NOT EXISTS operacion_id uuid;
ALTER TABLE public.recibos ADD COLUMN IF NOT EXISTS operacion_hash text;
CREATE UNIQUE INDEX IF NOT EXISTS recibos_operacion_id_uidx ON public.recibos(operacion_id);

CREATE OR REPLACE FUNCTION public.registrar_venta_drosalud(p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_admin boolean := public.es_admin_drosalud();
  v_rec public.recibos%rowtype;
  v_item jsonb;
  v_prod public.productos%rowtype;
  v_costo numeric;
  v_subtotal numeric := 0;
  v_ganancia numeric := 0;
  v_desc numeric := greatest(coalesce((p_venta->>'descuento')::numeric,0),0);
  v_dom numeric := greatest(coalesce((p_venta->>'domicilio')::numeric,0),0);
  v_mens numeric := case when public.es_admin_drosalud() then greatest(coalesce((p_venta->>'costo_mensajero')::numeric,0),0) else 0 end;
  v_total numeric;
  v_operacion_id uuid := coalesce(nullif(p_venta->>'operacion_id','')::uuid, gen_random_uuid());
  v_operacion_hash text;
BEGIN
  IF NOT public.es_usuario_drosalud() THEN
    RAISE EXCEPTION 'Usuario no autorizado';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'La venta no tiene productos';
  END IF;

  v_operacion_hash := md5((p_venta - 'operacion_id')::text || '|' || p_items::text);
  SELECT * INTO v_rec FROM public.recibos WHERE operacion_id = v_operacion_id;
  IF FOUND THEN
    IF v_rec.operacion_hash IS DISTINCT FROM v_operacion_hash THEN
      RAISE EXCEPTION 'La clave de operación ya fue utilizada con otros datos';
    END IF;
    RETURN to_jsonb(v_rec);
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF coalesce((v_item->>'cantidad')::numeric,0)<=0
       OR coalesce((v_item->>'cantidad')::numeric,0)<>trunc((v_item->>'cantidad')::numeric)
       OR coalesce((v_item->>'precio_venta')::numeric,-1)<0 THEN
      RAISE EXCEPTION 'Cantidad o precio inválido';
    END IF;
    v_costo := 0;
    IF nullif(v_item->>'producto_id','') IS NOT NULL THEN
      SELECT * INTO v_prod FROM public.productos WHERE id=(v_item->>'producto_id')::uuid;
      IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente'; END IF;
      IF v_prod.fraccionable THEN
        IF coalesce(nullif(v_item->>'presentacion',''),'Unidad')='Caja' THEN
          IF greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1))<>greatest(v_prod.unidades_por_caja,1)
             OR (v_item->>'cantidad')::integer % greatest(v_prod.unidades_por_caja,1)<>0 THEN
            RAISE EXCEPTION 'La cantidad de cajas no coincide con la presentación del producto';
          END IF;
        ELSIF coalesce(nullif(v_item->>'presentacion',''),'Unidad')='Unidad' THEN
          IF greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1))<>1
             OR (v_item->>'cantidad')::integer % greatest(v_prod.unidades_por_venta,1)<>0 THEN
            RAISE EXCEPTION 'Este producto se vende en múltiplos de % unidades sueltas',greatest(v_prod.unidades_por_venta,1);
          END IF;
        ELSE
          RAISE EXCEPTION 'Presentación de venta no válida para este producto';
        END IF;
      END IF;
      v_costo := CASE WHEN v_prod.fraccionable
        THEN v_prod.precio_compra/greatest(v_prod.unidades_por_caja,1)
        ELSE v_prod.precio_compra END;
    END IF;
    v_subtotal := v_subtotal+(v_item->>'precio_venta')::numeric*(v_item->>'cantidad')::numeric;
    v_ganancia := v_ganancia+(((v_item->>'precio_venta')::numeric-v_costo)*(v_item->>'cantidad')::numeric);
  END LOOP;

  v_total := greatest(0,v_subtotal-v_desc+v_dom);
  v_ganancia := v_ganancia-v_desc+v_dom-v_mens;

  IF nullif(p_venta->>'recibido','') IS NOT NULL
     AND (p_venta->>'recibido')::numeric<v_total THEN
    RAISE EXCEPTION 'El efectivo recibido es menor al total';
  END IF;

  INSERT INTO public.recibos(
    cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,cliente_direccion,
    descuento,domicilio,costo_mensajero,forma_pago,recibido,vendedor,total,ganancia,creado_por,operacion_id,operacion_hash
  )
  VALUES(
    nullif(p_venta->>'cliente_id','')::uuid,
    nullif(p_venta->>'cliente_nombre',''),
    nullif(p_venta->>'cliente_cedula',''),
    nullif(p_venta->>'cliente_telefono',''),
    nullif(p_venta->>'cliente_direccion',''),
    v_desc,v_dom,v_mens,
    nullif(p_venta->>'forma_pago',''),
    nullif(p_venta->>'recibido','')::numeric,
    nullif(p_venta->>'vendedor',''),
    v_total,v_ganancia,v_user,v_operacion_id,v_operacion_hash
  )
  ON CONFLICT (operacion_id) DO NOTHING
  RETURNING * INTO v_rec;

  IF v_rec.id IS NULL THEN
    SELECT * INTO v_rec FROM public.recibos WHERE operacion_id=v_operacion_id;
    IF NOT FOUND OR v_rec.operacion_hash IS DISTINCT FROM v_operacion_hash THEN
      RAISE EXCEPTION 'La clave de operación ya fue utilizada con otros datos';
    END IF;
    RETURN to_jsonb(v_rec);
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_costo := 0;
    IF nullif(v_item->>'producto_id','') IS NOT NULL THEN
      SELECT * INTO v_prod FROM public.productos WHERE id=(v_item->>'producto_id')::uuid;
      IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente'; END IF;
      v_costo := CASE WHEN v_prod.fraccionable
        THEN v_prod.precio_compra/greatest(v_prod.unidades_por_caja,1)
        ELSE v_prod.precio_compra END;
    END IF;

    INSERT INTO public.recibo_items(
      recibo_id,producto_id,nombre,cantidad,precio_compra,precio_venta,
      presentacion,unidades_por_presentacion
    )
    VALUES(
      v_rec.id,
      nullif(v_item->>'producto_id','')::uuid,
      v_item->>'nombre',
      (v_item->>'cantidad')::integer,
      v_costo,
      (v_item->>'precio_venta')::numeric,
      coalesce(nullif(v_item->>'presentacion',''),'Unidad'),
      greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1))
    );
  END LOOP;

  -- Ambos perfiles autorizados reciben la ganancia calculada.
  RETURN to_jsonb(v_rec);
END
$function$
;
