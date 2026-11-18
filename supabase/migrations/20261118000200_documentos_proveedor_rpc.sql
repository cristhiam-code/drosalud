-- Compras y recepción: registro seguro de documentos del proveedor.
-- Solo QA. La recepción de inventario sigue delegada a la RPC existente.

create or replace function public.registrar_documento_proveedor(
  p_orden_id uuid,
  p_tipo_documento text,
  p_numero_documento text,
  p_fecha_emision date,
  p_subtotal numeric,
  p_descuentos numeric default 0,
  p_impuestos numeric default 0,
  p_flete numeric default 0,
  p_total numeric default null,
  p_notas text default null,
  p_items jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_doc uuid;
  v_proveedor uuid;
  v_item jsonb;
  v_orden_item public.ordenes_compra_items%rowtype;
  v_producto public.productos%rowtype;
  v_factor integer;
  v_cantidad integer;
  v_precio numeric;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario no autorizado';
  end if;

  if p_orden_id is null
     or p_tipo_documento not in ('factura','remision','nota_credito','otro')
     or nullif(pg_catalog.btrim(p_numero_documento),'') is null
     or p_items is null
     or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Completa tipo, número, orden y detalle del documento';
  end if;

  if coalesce(p_descuentos,0) < 0 or coalesce(p_impuestos,0) < 0
     or coalesce(p_flete,0) < 0 or (p_subtotal is not null and p_subtotal < 0)
     or (p_total is not null and p_total < 0) then
    raise exception 'Los valores del documento no pueden ser negativos';
  end if;

  select proveedor_id into v_proveedor
  from public.ordenes_compra
  where id = p_orden_id and estado in ('aprobada','parcial','recibida')
  for update;

  if not found then
    raise exception 'La orden no existe o no está habilitada para asociar documentos';
  end if;

  -- Validar todas las líneas antes de insertar la cabecera.
  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    select * into v_orden_item
    from public.ordenes_compra_items
    where id = (v_item->>'orden_item_id')::uuid and orden_id = p_orden_id;

    if not found then raise exception 'Una línea no pertenece a la orden seleccionada'; end if;

    select * into v_producto
    from public.productos where id = v_orden_item.producto_id;

    if not found then raise exception 'Producto inexistente'; end if;

    v_factor := greatest(coalesce(v_producto.unidades_por_caja,1),1);
    v_cantidad := (v_item->>'cantidad_documentada')::integer;
    v_precio := (v_item->>'precio_por_presentacion')::numeric;

    if coalesce((v_item->>'unidades_por_presentacion')::integer,0) <> v_factor
       or v_cantidad is null or v_cantidad <= 0
       or v_precio is null or v_precio < 0 then
      raise exception 'Revisa cantidad, precio y equivalencia de presentación para %', v_producto.nombre;
    end if;

    if exists (
      select 1 from pg_catalog.jsonb_array_elements(p_items) x
      where x->>'orden_item_id' = v_item->>'orden_item_id'
      group by x->>'orden_item_id' having count(*) > 1
    ) then
      raise exception 'No repitas una línea de orden en el documento';
    end if;
  end loop;

  insert into public.documentos_proveedor(
    proveedor_id,tipo_documento,numero_documento,fecha_emision,
    subtotal,descuentos,impuestos,flete,total,notas,creado_por
  ) values (
    v_proveedor,p_tipo_documento,pg_catalog.btrim(p_numero_documento),p_fecha_emision,
    p_subtotal,coalesce(p_descuentos,0),coalesce(p_impuestos,0),
    coalesce(p_flete,0),p_total,nullif(pg_catalog.btrim(p_notas),''),auth.uid()
  ) returning id into v_doc;

  insert into public.documentos_proveedor_ordenes(documento_id,orden_id)
  values (v_doc,p_orden_id);

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    select * into v_orden_item
    from public.ordenes_compra_items
    where id = (v_item->>'orden_item_id')::uuid and orden_id = p_orden_id;

    select * into v_producto from public.productos where id = v_orden_item.producto_id;
    v_factor := greatest(coalesce(v_producto.unidades_por_caja,1),1);

    insert into public.documentos_proveedor_items(
      documento_id,orden_item_id,producto_id,descripcion_documento,
      presentacion_documento,unidades_por_presentacion,cantidad_documentada,
      precio_por_presentacion
    ) values (
      v_doc,v_orden_item.id,v_orden_item.producto_id,
      coalesce(nullif(pg_catalog.btrim(v_item->>'descripcion_documento'),''),v_producto.nombre),
      coalesce(nullif(pg_catalog.btrim(v_item->>'presentacion_documento'),''),'Caja x '||v_factor),
      v_factor,(v_item->>'cantidad_documentada')::integer,
      (v_item->>'precio_por_presentacion')::numeric
    );
  end loop;

  return v_doc;
exception
  when unique_violation then
    raise exception 'Ya existe un documento con ese número, tipo y proveedor';
end
$function$;

create or replace function public.registrar_recepcion_compra_documentada(
  p_orden_id uuid,
  p_documento_id uuid,
  p_items jsonb,
  p_operacion_id uuid,
  p_notas text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_proveedor uuid;
  v_doc_proveedor uuid;
  v_recepcion uuid;
  v_item jsonb;
  v_doc_item public.documentos_proveedor_items%rowtype;
  v_orden_item public.ordenes_compra_items%rowtype;
  v_factor integer;
  v_ya_recibido integer;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_documento_id is null or p_items is null
     or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Selecciona un documento y al menos un producto recibido';
  end if;

  select proveedor_id into v_proveedor
  from public.ordenes_compra
  where id=p_orden_id and estado in ('aprobada','parcial')
  for update;
  if not found then raise exception 'Orden no habilitada para recepción'; end if;

  select proveedor_id into v_doc_proveedor
  from public.documentos_proveedor
  where id=p_documento_id and estado <> 'anulado';
  if not found or v_doc_proveedor <> v_proveedor then
    raise exception 'El documento no corresponde al proveedor de la orden';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    select * into v_orden_item
    from public.ordenes_compra_items
    where id=(v_item->>'orden_item_id')::uuid and orden_id=p_orden_id;
    if not found then raise exception 'Línea de recepción ajena a la orden'; end if;

    select * into v_doc_item
    from public.documentos_proveedor_items
    where documento_id=p_documento_id and orden_item_id=v_orden_item.id;
    if not found then raise exception 'El producto no aparece en el documento del proveedor'; end if;

    select coalesce(sum(unidades),0)::integer into v_ya_recibido
    from public.recepciones_compra_items rci
    join public.recepciones_compra rc on rc.id=rci.recepcion_id
    where rc.documento_id=p_documento_id and rci.orden_item_id=v_orden_item.id;

    if v_ya_recibido + (v_item->>'unidades')::integer > v_doc_item.unidades_documentadas then
      raise exception 'La recepción supera la cantidad indicada en el documento';
    end if;

    select greatest(coalesce(unidades_por_caja,1),1) into v_factor
    from public.productos where id=v_orden_item.producto_id;

    if v_factor <> v_doc_item.unidades_por_presentacion
       or abs((v_item->>'costo_unitario_base')::numeric - v_doc_item.costo_unitario_base) > 0.01 then
      raise exception 'El costo o la presentación no coincide con el documento. Revisa la conciliación antes de recibir';
    end if;
  end loop;

  select public.registrar_recepcion_compra(
    p_orden_id,
    (select numero_documento from public.documentos_proveedor where id=p_documento_id),
    p_items,
    p_operacion_id,
    p_notas
  ) into v_recepcion;

  update public.recepciones_compra
  set documento_id=p_documento_id
  where id=v_recepcion;

  return v_recepcion;
end
$function$;

revoke all on function public.registrar_documento_proveedor(uuid,text,text,date,numeric,numeric,numeric,numeric,numeric,text,jsonb) from public, anon;
grant execute on function public.registrar_documento_proveedor(uuid,text,text,date,numeric,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;

revoke all on function public.registrar_recepcion_compra_documentada(uuid,uuid,jsonb,uuid,text) from public, anon;
grant execute on function public.registrar_recepcion_compra_documentada(uuid,uuid,jsonb,uuid,text) to authenticated;
