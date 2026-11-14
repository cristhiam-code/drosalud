-- Restaura en QA las reglas y definiciones RPC que existen en producción.
-- Mantiene el comportamiento operativo actual de Compras mientras se valida Pedidos.
-- Producción no se modifica con esta migración.

CREATE OR REPLACE FUNCTION public.aprobar_orden_compra(p_orden_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_usuario_drosalud() THEN
  RAISE EXCEPTION 'Usuario no autorizado';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.ordenes_compra_items WHERE orden_id=p_orden_id) THEN
  RAISE EXCEPTION 'No se puede aprobar una orden vacía';
 END IF;
 UPDATE public.ordenes_compra
 SET estado='aprobada', actualizado_en=now()
 WHERE id=p_orden_id AND estado='borrador';
 IF NOT FOUND THEN RAISE EXCEPTION 'La orden no existe o no está en borrador'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.crear_orden_compra(p_proveedor_id uuid, p_items jsonb, p_documento text DEFAULT NULL::text, p_notas text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_id uuid;
 v_item jsonb;
 v_producto uuid;
 v_unidades integer;
 v_costo numeric;
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_usuario_drosalud() THEN
  RAISE EXCEPTION 'Usuario no autorizado';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.proveedores WHERE id=p_proveedor_id AND activo) THEN
  RAISE EXCEPTION 'Proveedor inexistente o inactivo';
 END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'La orden debe contener productos';
 END IF;
 INSERT INTO public.ordenes_compra(proveedor_id,documento_proveedor,notas,creado_por)
 VALUES(p_proveedor_id,nullif(trim(p_documento),''),nullif(trim(p_notas),''),auth.uid())
 RETURNING id INTO v_id;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  v_producto := (v_item->>'producto_id')::uuid;
  v_unidades := (v_item->>'unidades_solicitadas')::integer;
  v_costo := (v_item->>'costo_unitario_base')::numeric;
  IF v_unidades IS NULL OR v_unidades<=0 OR v_costo IS NULL OR v_costo<0 THEN
   RAISE EXCEPTION 'Unidades o costo inválido en orden';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.productos WHERE id=v_producto) THEN
   RAISE EXCEPTION 'Producto inexistente en orden';
  END IF;
  INSERT INTO public.ordenes_compra_items(orden_id,producto_id,unidades_solicitadas,costo_unitario_base)
  VALUES(v_id,v_producto,v_unidades,v_costo);
 END LOOP;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.registrar_recepcion_compra(p_orden_id uuid, p_documento_proveedor text, p_items jsonb, p_operacion_id uuid, p_notas text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_recepcion uuid;
 v_proveedor uuid;
 v_item jsonb;
 v_orden_item public.ordenes_compra_items%rowtype;
 v_producto public.productos%rowtype;
 v_unidades integer;
 v_costo numeric;
 v_presentacion numeric;
 v_factor integer;
 v_operacion_linea uuid;
 v_hash text;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then
  raise exception 'Usuario no autorizado';
 end if;
 if p_operacion_id is null or p_items is null or jsonb_typeof(p_items)<>'array'
    or jsonb_array_length(p_items)=0 then
  raise exception 'Operación e items son obligatorios';
 end if;

 v_hash := pg_catalog.md5(
   p_orden_id::text || '|' ||
   coalesce(nullif(trim(p_documento_proveedor),''),'') || '|' ||
   coalesce(nullif(trim(p_notas),''),'') || '|' ||
   p_items::text
 );

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacion_id::text,0));

 select id, request_hash into v_recepcion, v_hash
 from public.recepciones_compra
 where operacion_id=p_operacion_id;

 if v_recepcion is not null then
  if v_hash is not null and v_hash <> pg_catalog.md5(
    p_orden_id::text || '|' ||
    coalesce(nullif(trim(p_documento_proveedor),''),'') || '|' ||
    coalesce(nullif(trim(p_notas),''),'') || '|' ||
    p_items::text
  ) then
   raise exception 'La clave de operación ya fue utilizada con datos diferentes';
  end if;
  return v_recepcion;
 end if;

 select proveedor_id into v_proveedor
 from public.ordenes_compra
 where id=p_orden_id and estado in ('aprobada','parcial')
 for update;
 if not found then raise exception 'Orden no existe o no está habilitada para recepción'; end if;

 -- Validar todas las líneas antes de insertar movimientos o cambiar costos.
 for v_item in select value from jsonb_array_elements(p_items) loop
  select * into v_orden_item
  from public.ordenes_compra_items
  where id=(v_item->>'orden_item_id')::uuid and orden_id=p_orden_id
  for update;
  if not found then raise exception 'La línea no pertenece a la orden'; end if;
  v_unidades := (v_item->>'unidades')::integer;
  v_costo := (v_item->>'costo_unitario_base')::numeric;
  if v_unidades is null or v_unidades<=0 or v_costo is null or v_costo<0
     or v_orden_item.unidades_recibidas+v_unidades>v_orden_item.unidades_solicitadas then
   raise exception 'Cantidad/costo inválido o recepción excede lo ordenado';
  end if;
  if exists (
   select 1 from jsonb_array_elements(p_items) x
   where x->>'orden_item_id'=v_item->>'orden_item_id'
   group by x->>'orden_item_id' having count(*)>1
  ) then
   raise exception 'No repitas una línea de orden en la misma recepción';
  end if;
 end loop;

 insert into public.recepciones_compra(
  orden_id,proveedor_id,documento_proveedor,operacion_id,notas,recibido_por,request_hash
 ) values (
  p_orden_id,v_proveedor,nullif(trim(p_documento_proveedor),''),p_operacion_id,
  nullif(trim(p_notas),''),auth.uid(),
  pg_catalog.md5(p_orden_id::text || '|' ||
   coalesce(nullif(trim(p_documento_proveedor),''),'') || '|' ||
   coalesce(nullif(trim(p_notas),''),'') || '|' || p_items::text)
 ) returning id into v_recepcion;

 for v_item in select value from jsonb_array_elements(p_items) loop
  select * into v_orden_item
  from public.ordenes_compra_items
  where id=(v_item->>'orden_item_id')::uuid and orden_id=p_orden_id
  for update;

  v_unidades := (v_item->>'unidades')::integer;
  v_costo := (v_item->>'costo_unitario_base')::numeric;
  select * into v_producto from public.productos
  where id=v_orden_item.producto_id for update;
  if not found then raise exception 'Producto inexistente'; end if;

  v_factor := greatest(coalesce(v_producto.unidades_por_caja,1),1);
  v_presentacion := v_costo*v_factor;
  v_operacion_linea := (pg_catalog.md5(p_operacion_id::text || ':' || v_producto.id::text))::uuid;

  insert into public.recepciones_compra_items(
   recepcion_id,orden_item_id,producto_id,unidades,costo_unitario_base
  ) values(v_recepcion,v_orden_item.id,v_orden_item.producto_id,v_unidades,v_costo);

  insert into public.inventario_movimientos(
   producto_id,tipo,unidades_delta,referencia_id,operacion_id,notas,creado_por,
   proveedor_id,recepcion_compra_id,costo_unitario_base
  ) values(
   v_orden_item.producto_id,'recepcion',v_unidades,v_recepcion,v_operacion_linea,
   'Recepción de compra '||coalesce(p_documento_proveedor,'sin documento'),auth.uid(),
   v_proveedor,v_recepcion,v_costo
  );

  update public.ordenes_compra_items
   set unidades_recibidas=unidades_recibidas+v_unidades
   where id=v_orden_item.id;

  update public.productos set precio_compra=v_presentacion,actualizado_en=now()
   where id=v_producto.id;

  insert into public.historial_costos(
   producto_id,proveedor_id,costo_unitario_base,costo_presentacion,
   unidades_por_presentacion,origen,referencia_id,registrado_por
  ) values(
   v_producto.id,v_proveedor,v_costo,v_presentacion,v_factor,
   'recepcion',v_recepcion,auth.uid()
  );
 end loop;

 update public.ordenes_compra o set
  estado=case
   when not exists(select 1 from public.ordenes_compra_items i
     where i.orden_id=o.id and i.unidades_recibidas<i.unidades_solicitadas) then 'recibida'
   else 'parcial' end,
  actualizado_en=now()
 where o.id=p_orden_id;

 return v_recepcion;
end
$function$;
