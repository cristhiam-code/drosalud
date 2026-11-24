-- Evita recibir una línea de factura asociada a un producto distinto al de la orden.
-- Esta migración reemplaza únicamente el wrapper documentado; no modifica datos existentes.
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
  v_doc_existente uuid;
  v_hash_existente text;
  v_hash_solicitado text;
  v_numero_documento text;
  v_item jsonb;
  v_doc_item public.documentos_proveedor_items%rowtype;
  v_orden_item public.ordenes_compra_items%rowtype;
  v_factor integer;
  v_ya_recibido integer;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_orden_id is null or p_documento_id is null or p_operacion_id is null
     or p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Orden, documento, operación e items son obligatorios';
  end if;

  select proveedor_id,numero_documento into v_doc_proveedor,v_numero_documento
  from public.documentos_proveedor
  where id=p_documento_id and estado <> 'anulado';
  if not found then raise exception 'Documento no existe o está anulado'; end if;

  v_hash_solicitado := pg_catalog.md5(
    p_orden_id::text || '|' ||
    coalesce(nullif(pg_catalog.btrim(v_numero_documento),''),'') || '|' ||
    coalesce(nullif(pg_catalog.btrim(p_notas),''),'') || '|' ||
    p_items::text
  );

  -- Reintentar la misma operación devuelve la recepción ya creada sin sumar dos veces.
  select id,documento_id,request_hash into v_recepcion,v_doc_existente,v_hash_existente
  from public.recepciones_compra
  where operacion_id=p_operacion_id;
  if found then
    if v_doc_existente is distinct from p_documento_id or v_hash_existente is distinct from v_hash_solicitado then
      raise exception 'La clave de operación ya fue utilizada con datos diferentes';
    end if;
    return v_recepcion;
  end if;

  select proveedor_id into v_proveedor
  from public.ordenes_compra
  where id=p_orden_id and estado in ('aprobada','parcial')
  for update;
  if not found then raise exception 'Orden no habilitada para recepción'; end if;
  if v_doc_proveedor <> v_proveedor then
    raise exception 'El documento no corresponde al proveedor de la orden';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    select * into v_orden_item from public.ordenes_compra_items
    where id=(v_item->>'orden_item_id')::uuid and orden_id=p_orden_id;
    if not found then raise exception 'Línea de recepción ajena a la orden'; end if;

    select * into v_doc_item from public.documentos_proveedor_items
    where documento_id=p_documento_id and orden_item_id=v_orden_item.id;
    if not found then raise exception 'El producto no aparece en el documento del proveedor'; end if;

    -- La línea documental debe referirse exactamente al producto de la línea ordenada.
    if v_doc_item.producto_id is distinct from v_orden_item.producto_id then
      raise exception 'El producto del documento no coincide con el producto de la orden';
    end if;

    select coalesce(pg_catalog.sum(unidades),0)::integer into v_ya_recibido
    from public.recepciones_compra_items rci
    join public.recepciones_compra rc on rc.id=rci.recepcion_id
    where rc.documento_id=p_documento_id and rci.orden_item_id=v_orden_item.id;

    if (v_item->>'unidades') is null or (v_item->>'unidades')::integer <= 0
       or v_ya_recibido + (v_item->>'unidades')::integer > v_doc_item.unidades_documentadas then
      raise exception 'La recepción supera la cantidad indicada en el documento o no es válida';
    end if;

    select greatest(coalesce(unidades_por_caja,1),1) into v_factor
    from public.productos where id=v_orden_item.producto_id;
    if v_factor <> v_doc_item.unidades_por_presentacion
       or (v_item->>'costo_unitario_base') is null
       or pg_catalog.abs((v_item->>'costo_unitario_base')::numeric - v_doc_item.costo_unitario_base) > 0.01 then
      raise exception 'El costo o la presentación no coincide con el documento. Revisa la conciliación antes de recibir';
    end if;
  end loop;

  select public.registrar_recepcion_compra(
    p_orden_id,v_numero_documento,p_items,p_operacion_id,p_notas
  ) into v_recepcion;

  update public.recepciones_compra set documento_id=p_documento_id where id=v_recepcion;

  update public.documentos_proveedor d
  set estado = case
    when exists (
      select 1
      from public.documentos_proveedor_items di
      left join (
        select rc.documento_id,rci.orden_item_id,pg_catalog.sum(rci.unidades) unidades_aceptadas
        from public.recepciones_compra rc
        join public.recepciones_compra_items rci on rci.recepcion_id=rc.id
        where rc.documento_id=p_documento_id
        group by rc.documento_id,rci.orden_item_id
      ) recibido on recibido.documento_id=di.documento_id and recibido.orden_item_id=di.orden_item_id
      where di.documento_id=p_documento_id
        and coalesce(recibido.unidades_aceptadas,0) < di.unidades_documentadas
    ) then 'parcial'
    else 'conciliado'
  end,
  actualizado_en=pg_catalog.now()
  where d.id=p_documento_id;

  return v_recepcion;
end
$function$;
