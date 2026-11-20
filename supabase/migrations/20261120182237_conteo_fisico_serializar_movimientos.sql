-- Asegurar que ventas, recepciones y conteo compartan el mismo orden de bloqueo:
-- producto -> cerrojo de ubicación -> sesión/línea.
begin;

create or replace function public.proteger_movimiento_durante_conteo()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_item public.inventario_conteos_items%rowtype;
begin
  -- Todos los movimientos del Kardex principal bloquean la misma fila que el
  -- inicio del conteo. Esto incluye las ventas generadas por trigger.
  perform 1 from public.productos p
  where p.id=new.producto_id
  for update;

  if not found then
    raise exception 'Producto inexistente para movimiento de inventario';
  end if;

  -- Un reintento idéntico de recepción es un no-op: conserva idempotencia.
  if new.tipo='recepcion' and new.operacion_id is not null and exists(
    select 1 from public.inventario_movimientos m
    where m.tipo=new.tipo and m.operacion_id=new.operacion_id
      and m.producto_id=new.producto_id and m.unidades_delta=new.unidades_delta
      and m.referencia_id is not distinct from new.referencia_id
      and m.notas is not distinct from new.notas
      and m.creado_por is not distinct from new.creado_por
      and m.proveedor_id is not distinct from new.proveedor_id
      and m.recepcion_compra_id is not distinct from new.recepcion_compra_id
      and m.costo_unitario_base is not distinct from new.costo_unitario_base
  ) then
    return new;
  end if;

  -- Bloqueo autoritativo: se comprueba antes de aceptar cualquier movimiento
  -- nuevo. El producto ya está bloqueado con FOR UPDATE.
  if exists(
    select 1 from public.inventario_conteos_bloqueos b
    where b.producto_id=new.producto_id
  ) then
    raise exception 'Producto protegido por conteo físico'
      using errcode='55P03';
  end if;

  -- La RPC histórica no puede registrar conteos por fuera de aprobación.
  -- El fraccionamiento conserva operacion_id NULL y no queda afectado.
  if new.tipo in ('ajuste','saldo_inicial')
     and new.referencia_id is null
     and new.operacion_id is not null then
    raise exception 'Los ajustes de conteo deben pasar por aprobación del conteo físico'
      using errcode='42501';
  end if;

  if new.tipo='ajuste' and new.referencia_id is not null then
    select i.* into v_item
    from public.inventario_conteos_items i
    where i.id=new.referencia_id;

    if not found
       or v_item.estado<>'aprobado'
       or v_item.producto_id<>new.producto_id
       or v_item.movimiento_id is not null
       or v_item.operacion_aprobacion_id is distinct from new.operacion_id
       or v_item.aprobado_por is distinct from new.creado_por
       or v_item.diferencia_base is distinct from new.unidades_delta
       or not public.inventario_conteo_tiene_permiso(true)
       or exists(
         select 1 from public.inventario_conteo_capturas c
         where c.conteo_item_id=v_item.id and c.contado_por=new.creado_por
       ) then
      raise exception 'Ajuste físico sin aprobación válida';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.proteger_movimiento_sucursal_durante_conteo()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  -- Mismo orden que el Kardex principal y el inicio del conteo:
  -- primero producto, luego cerrojo compartido por ubicación.
  perform 1 from public.productos p
  where p.id=new.producto_id
  for update;

  if not found then
    raise exception 'Producto inexistente para movimiento de inventario';
  end if;

  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended(new.bodega_id::text,0)
  );

  -- Reintento del espejo central: solo permitir el mismo movimiento ya escrito.
  if new.movimiento_origen_id is not null and exists(
    select 1 from public.inventario_sucursal_movimientos m
    where m.movimiento_origen_id=new.movimiento_origen_id
      and m.bodega_id=new.bodega_id
      and m.producto_id=new.producto_id
      and m.tipo=new.tipo
      and m.unidades_delta=new.unidades_delta
      and m.referencia_id is not distinct from new.referencia_id
      and m.notas is not distinct from new.notas
      and m.creado_por is not distinct from new.creado_por
      and m.creado_en is not distinct from new.creado_en
  ) then
    return new;
  end if;

  if exists(
    select 1 from public.inventario_conteos_bloqueos b
    where b.bodega_id=new.bodega_id and b.producto_id=new.producto_id
  ) then
    raise exception 'Producto protegido por conteo físico'
      using errcode='55P03';
  end if;

  return new;
end;
$function$;

-- Reemplazar inicio con el cerrojo exclusivo correspondiente al espejo.
create or replace function public.iniciar_linea_conteo(p_item_id uuid,p_solicitud_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_producto uuid; v_bodega uuid; v_prod public.productos%rowtype;
  v_item public.inventario_conteos_items%rowtype; v_sesion public.inventario_conteos%rowtype;
  v_saldo bigint;
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para contar';
  end if;
  if p_solicitud_id is null then raise exception 'Falta clave de solicitud'; end if;

  select producto_id,bodega_id into v_producto,v_bodega
  from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea de conteo inexistente'; end if;

  -- Orden estricto: fila del producto -> cerrojo exclusivo de ubicación.
  select * into v_prod from public.productos where id=v_producto for update;
  if not found then raise exception 'Producto inexistente para conteo'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_bodega::text,0)
  );

  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;

  if v_sesion.estado<>'abierto' then raise exception 'La sesión no está abierta'; end if;
  if v_item.inicio_operacion_id is not null then
    if v_item.inicio_operacion_id<>p_solicitud_id or v_item.contador_asignado_a<>auth.uid() then
      raise exception 'La línea ya fue iniciada por otra operación o persona';
    end if;
    return jsonb_build_object('item_id',v_item.id,'estado',v_item.estado,
      'codigo',v_item.codigo_corte,'nombre',v_item.nombre_corte);
  end if;
  if v_item.estado<>'seleccionado' then raise exception 'La línea no está disponible para iniciar'; end if;
  if exists(select 1 from public.inventario_conteos_bloqueos b where b.producto_id=v_producto) then
    raise exception 'El producto ya está protegido por otro conteo' using errcode='55P03';
  end if;

  select coalesce(sum(m.unidades_delta),0)::bigint into v_saldo
  from public.inventario_movimientos m where m.producto_id=v_producto;

  insert into public.inventario_conteos_bloqueos(bodega_id,producto_id,conteo_item_id,conteo_id,activado_por)
    values(v_bodega,v_producto,v_item.id,v_item.conteo_id,auth.uid());

  update public.inventario_conteos_items set estado='contando',saldo_teorico_corte=v_saldo,
    codigo_corte=v_prod.codigo,nombre_corte=v_prod.nombre,laboratorio_corte=v_prod.laboratorio,
    fraccionable_corte=coalesce(v_prod.fraccionable,false),
    unidades_por_caja_corte=greatest(coalesce(v_prod.unidades_por_caja,1),1),
    unidades_por_venta_corte=greatest(coalesce(v_prod.unidades_por_venta,1),1),
    contador_asignado_a=auth.uid(),inicio_operacion_id=p_solicitud_id
  where id=p_item_id;

  return jsonb_build_object('item_id',p_item_id,'estado','contando','codigo',v_prod.codigo,
    'nombre',v_prod.nombre,'unidades_por_caja',greatest(coalesce(v_prod.unidades_por_caja,1),1),
    'fraccionable',coalesce(v_prod.fraccionable,false));
end;
$function$;

notify pgrst, 'reload schema';
commit;