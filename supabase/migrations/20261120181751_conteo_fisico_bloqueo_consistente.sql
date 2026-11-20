-- Alinear el bloqueo de todas las operaciones de conteo.
-- Cada RPC bloquea producto -> sesión -> línea, igual que los movimientos del Kardex.
begin;

create or replace function public.guardar_conteo_fisico(
  p_item_id uuid,p_cantidad_base bigint,p_solicitud_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_producto uuid; v_bodega uuid;
  v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para registrar conteos';
  end if;
  if p_cantidad_base is null or p_cantidad_base<0 or p_solicitud_id is null then
    raise exception 'Cantidad o solicitud inválida';
  end if;

  select producto_id,bodega_id into v_producto,v_bodega
  from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;

  perform 1 from public.productos p where p.id=v_producto for update;
  if not found then raise exception 'Producto inexistente para conteo'; end if;

  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;

  select * into v_c from public.inventario_conteo_capturas where solicitud_id=p_solicitud_id;
  if found then
    if v_c.conteo_item_id<>p_item_id or v_c.cantidad_base<>p_cantidad_base
       or v_c.contado_por<>auth.uid() then
      raise exception 'Clave de captura reutilizada con otros datos';
    end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado,'guardado',true);
  end if;

  if v_sesion.estado<>'abierto' or v_item.estado<>'contando'
     or v_item.contador_asignado_a<>auth.uid()
     or not exists(select 1 from public.inventario_conteos_bloqueos b
       where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está asignada a tu usuario o dejó de estar protegida';
  end if;
  if exists(select 1 from public.inventario_conteo_capturas c where c.conteo_item_id=p_item_id) then
    raise exception 'La primera captura ya existe';
  end if;

  insert into public.inventario_conteo_capturas(
    conteo_item_id,numero,cantidad_base,contado_por,solicitud_id
  ) values(p_item_id,1,p_cantidad_base,auth.uid(),p_solicitud_id);
  update public.inventario_conteos_items
  set captura_operacion_id=p_solicitud_id
  where id=p_item_id;

  return jsonb_build_object('item_id',p_item_id,'estado','contando','guardado',true);
end;
$function$;

create or replace function public.enviar_linea_conteo_a_revision(
  p_item_id uuid,p_solicitud_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_producto uuid; v_bodega uuid;
  v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype;
  v_estado text;
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para enviar conteos';
  end if;
  if p_solicitud_id is null then raise exception 'Falta clave de envío'; end if;

  select producto_id,bodega_id into v_producto,v_bodega
  from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;

  perform 1 from public.productos p where p.id=v_producto for update;
  if not found then raise exception 'Producto inexistente para envío'; end if;

  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;

  if v_item.envio_revision_operacion_id is not null then
    if v_item.envio_revision_operacion_id<>p_solicitud_id then
      raise exception 'La línea ya fue enviada';
    end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado);
  end if;

  if v_sesion.estado<>'abierto' or v_item.estado<>'contando'
     or v_item.contador_asignado_a<>auth.uid()
     or not exists(select 1 from public.inventario_conteos_bloqueos b
       where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está lista o no está asignada a tu usuario';
  end if;

  select * into v_c from public.inventario_conteo_capturas
  where conteo_item_id=p_item_id and numero=1;
  if not found then raise exception 'Guarda la cantidad antes de enviar'; end if;

  if v_c.cantidad_base=v_item.saldo_teorico_corte then
    v_estado:='pendiente_aprobacion';
    update public.inventario_conteos_items
    set cantidad_confirmada_base=v_c.cantidad_base
    where id=p_item_id;
  else
    v_estado:='pendiente_reconteo';
  end if;

  update public.inventario_conteos_items
  set estado=v_estado,envio_revision_operacion_id=p_solicitud_id
  where id=p_item_id;
  return jsonb_build_object('item_id',p_item_id,'estado',v_estado);
end;
$function$;

create or replace function public.registrar_reconteo_fisico(
  p_item_id uuid,p_cantidad_base bigint,p_solicitud_id uuid,p_motivo text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_producto uuid; v_bodega uuid;
  v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype;
  v_consenso bigint; v_numero integer;
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para recontar';
  end if;
  if p_cantidad_base is null or p_cantidad_base<0 or p_solicitud_id is null then
    raise exception 'Cantidad o solicitud inválida';
  end if;

  select producto_id,bodega_id into v_producto,v_bodega
  from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;

  perform 1 from public.productos p where p.id=v_producto for update;
  if not found then raise exception 'Producto inexistente para reconteo'; end if;

  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;

  select * into v_c from public.inventario_conteo_capturas where solicitud_id=p_solicitud_id;
  if found then
    if v_c.conteo_item_id<>p_item_id or v_c.cantidad_base<>p_cantidad_base
       or v_c.contado_por<>auth.uid()
       or v_c.motivo is distinct from nullif(left(btrim(coalesce(p_motivo,'')),500),'') then
      raise exception 'Clave de reconteo reutilizada con otros datos';
    end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado,'guardado',true);
  end if;

  if v_sesion.estado<>'abierto' or v_item.estado<>'pendiente_reconteo'
     or not exists(select 1 from public.inventario_conteos_bloqueos b
       where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está pendiente de reconteo o dejó de estar protegida';
  end if;
  if exists(select 1 from public.inventario_conteo_capturas c
    where c.conteo_item_id=p_item_id and c.contado_por=auth.uid()) then
    raise exception 'Cada reconteo debe hacerlo una persona que no haya contado este producto';
  end if;

  select coalesce(max(numero),0)+1 into v_numero
  from public.inventario_conteo_capturas where conteo_item_id=p_item_id;

  insert into public.inventario_conteo_capturas(
    conteo_item_id,numero,cantidad_base,contado_por,solicitud_id,motivo
  ) values(
    p_item_id,v_numero,p_cantidad_base,auth.uid(),p_solicitud_id,
    nullif(left(btrim(coalesce(p_motivo,'')),500),'')
  );

  select cantidad_base into v_consenso
  from public.inventario_conteo_capturas
  where conteo_item_id=p_item_id
  group by cantidad_base
  having count(*)>=2
  order by min(numero)
  limit 1;

  if found then
    update public.inventario_conteos_items
    set cantidad_confirmada_base=v_consenso,estado='pendiente_aprobacion'
    where id=p_item_id;
    return jsonb_build_object('item_id',p_item_id,'estado','pendiente_aprobacion','consenso',true);
  end if;

  return jsonb_build_object('item_id',p_item_id,'estado','pendiente_reconteo','consenso',false);
end;
$function$;

-- La RPC histórica de conteo no pertenece al nuevo flujo y ya está bloqueada
-- por el trigger de Kardex para generar ajustes. Se cierra su acceso público.
revoke all on function public.registrar_conteo_inventario(uuid,integer,uuid,text)
  from public,anon,authenticated;

notify pgrst, 'reload schema';
commit;