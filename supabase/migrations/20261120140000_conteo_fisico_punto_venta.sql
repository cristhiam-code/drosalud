-- DROSalud: conteo físico para un único punto de venta.
-- La referencia de ubicación se conserva internamente por compatibilidad con
-- el esquema QA existente; no se solicita ni se muestra al usuario.
-- Fuente de saldo: Kardex principal inventario_movimientos.
-- Los movimientos y el conteo se serializan sobre la misma fila de productos.

begin;

-- La pantalla ya utiliza la RPC de tres argumentos. QA tenía una firma antigua
-- de cuatro argumentos que obligaba a enviar una bodega desde el cliente.
drop function if exists public.crear_conteo_inventario(uuid[], text, uuid, uuid);

create function public.crear_conteo_inventario(
  p_productos uuid[],
  p_motivo text,
  p_solicitud_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ids uuid[];
  v_hash text;
  v_id uuid;
  v_existente public.inventario_conteos%rowtype;
  v_producto uuid;
  v_bodega uuid;
  v_ubicaciones integer;
begin
  if auth.uid() is null
     or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para crear conteos';
  end if;

  if p_productos is null
     or cardinality(p_productos) = 0
     or p_solicitud_id is null
     or nullif(btrim(p_motivo), '') is null
     or length(btrim(p_motivo)) > 500 then
    raise exception 'Selecciona productos, motivo y clave de solicitud';
  end if;

  select array_agg(x order by x)
    into v_ids
  from (select distinct unnest(p_productos) as x) s;

  if cardinality(v_ids) <> cardinality(p_productos)
     or array_position(v_ids, null) is not null then
    raise exception 'La lista contiene productos repetidos o inválidos';
  end if;

  -- QA conserva una sola referencia técnica de ubicación. Se resuelve aquí,
  -- sin exponer "bodega" ni pedir selección al usuario.
  select count(*) into v_ubicaciones
  from public.bodegas
  where activa = true and es_central = true;

  if v_ubicaciones <> 1 then
    raise exception 'El inventario del punto de venta no tiene una ubicación técnica única activa';
  end if;

  select id into v_bodega
  from public.bodegas
  where activa = true and es_central = true
  order by id
  limit 1;

  v_hash := md5(v_bodega::text || '|' || array_to_string(v_ids, ',') || '|' || btrim(p_motivo));

  insert into public.inventario_conteos(
    solicitud_creacion_id, solicitud_creacion_hash, motivo, creado_por, bodega_id
  )
  values (p_solicitud_id, v_hash, btrim(p_motivo), auth.uid(), v_bodega)
  on conflict (solicitud_creacion_id) do nothing
  returning id into v_id;

  if v_id is null then
    select * into v_existente
    from public.inventario_conteos
    where solicitud_creacion_id = p_solicitud_id;

    if not found
       or v_existente.solicitud_creacion_hash <> v_hash
       or v_existente.creado_por <> auth.uid() then
      raise exception 'Clave de solicitud reutilizada con otros datos';
    end if;

    return v_existente.id;
  end if;

  foreach v_producto in array v_ids loop
    perform 1 from public.productos p where p.id = v_producto;
    if not found then
      raise exception 'Producto inexistente: %', v_producto;
    end if;

    insert into public.inventario_conteos_items(
      conteo_id, producto_id, bodega_id, codigo_corte, nombre_corte,
      laboratorio_corte, fraccionable_corte, unidades_por_caja_corte,
      unidades_por_venta_corte
    )
    select v_id, p.id, v_bodega, p.codigo, p.nombre, p.laboratorio,
      coalesce(p.fraccionable, false),
      greatest(coalesce(p.unidades_por_caja, 1), 1),
      greatest(coalesce(p.unidades_por_venta, 1), 1)
    from public.productos p
    where p.id = v_producto;
  end loop;

  return v_id;
end;
$function$;

revoke all on function public.crear_conteo_inventario(uuid[], text, uuid)
  from public, anon, authenticated;
grant execute on function public.crear_conteo_inventario(uuid[], text, uuid)
  to authenticated;

-- Inicio: el corte de saldo y los movimientos comparten el bloqueo de la fila
-- del producto. No se utiliza un bloqueo por bodega ni el ledger secundario.
create or replace function public.iniciar_linea_conteo(
  p_item_id uuid,
  p_solicitud_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_producto uuid;
  v_bodega uuid;
  v_prod public.productos%rowtype;
  v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype;
  v_saldo bigint;
begin
  if auth.uid() is null
     or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para contar';
  end if;

  if p_solicitud_id is null then
    raise exception 'Falta clave de solicitud';
  end if;

  select producto_id, bodega_id
    into v_producto, v_bodega
  from public.inventario_conteos_items
  where id = p_item_id;

  if not found then
    raise exception 'Línea de conteo inexistente';
  end if;

  -- Orden común de bloqueo: producto -> sesión -> línea.
  select * into v_prod
  from public.productos
  where id = v_producto
  for update;

  if not found then
    raise exception 'Producto inexistente para conteo';
  end if;

  select * into v_item
  from public.inventario_conteos_items
  where id = p_item_id;

  select * into v_sesion
  from public.inventario_conteos
  where id = v_item.conteo_id
  for update;

  select * into v_item
  from public.inventario_conteos_items
  where id = p_item_id
  for update;

  if v_sesion.estado <> 'abierto' then
    raise exception 'La sesión no está abierta';
  end if;

  if v_item.inicio_operacion_id is not null then
    if v_item.inicio_operacion_id <> p_solicitud_id
       or v_item.contador_asignado_a <> auth.uid() then
      raise exception 'La línea ya fue iniciada por otra operación o persona';
    end if;

    return jsonb_build_object(
      'item_id', v_item.id, 'estado', v_item.estado,
      'codigo', v_item.codigo_corte, 'nombre', v_item.nombre_corte
    );
  end if;

  if v_item.estado <> 'seleccionado' then
    raise exception 'La línea no está disponible para iniciar';
  end if;

  if exists (
    select 1 from public.inventario_conteos_bloqueos b
    where b.producto_id = v_producto
  ) then
    raise exception 'El producto ya está protegido por otro conteo'
      using errcode = '55P03';
  end if;

  select coalesce(sum(m.unidades_delta), 0)::bigint
    into v_saldo
  from public.inventario_movimientos m
  where m.producto_id = v_producto;

  insert into public.inventario_conteos_bloqueos(
    bodega_id, producto_id, conteo_item_id, conteo_id, activado_por
  )
  values (v_bodega, v_producto, v_item.id, v_item.conteo_id, auth.uid());

  update public.inventario_conteos_items
  set estado = 'contando',
      saldo_teorico_corte = v_saldo,
      codigo_corte = v_prod.codigo,
      nombre_corte = v_prod.nombre,
      laboratorio_corte = v_prod.laboratorio,
      fraccionable_corte = coalesce(v_prod.fraccionable, false),
      unidades_por_caja_corte = greatest(coalesce(v_prod.unidades_por_caja, 1), 1),
      unidades_por_venta_corte = greatest(coalesce(v_prod.unidades_por_venta, 1), 1),
      contador_asignado_a = auth.uid(),
      inicio_operacion_id = p_solicitud_id
  where id = p_item_id;

  return jsonb_build_object(
    'item_id', p_item_id, 'estado', 'contando',
    'codigo', v_prod.codigo, 'nombre', v_prod.nombre,
    'unidades_por_caja', greatest(coalesce(v_prod.unidades_por_caja, 1), 1),
    'fraccionable', coalesce(v_prod.fraccionable, false)
  );
end;
$function$;

-- Aprobación: retiene el bloqueo del producto hasta confirmar el ajuste y la
-- liberación en una única transacción. Evita que una venta se cuele entre ambos.
create or replace function public.aprobar_linea_conteo(
  p_item_id uuid,
  p_solicitud_id uuid,
  p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_producto uuid;
  v_conteo uuid;
  v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype;
  v_delta numeric;
  v_movimiento uuid;
  v_existing public.inventario_movimientos%rowtype;
begin
  if auth.uid() is null
     or not public.es_usuario_drosalud()
     or not public.inventario_conteo_tiene_permiso(true) then
    raise exception 'No tienes permiso para aprobar conteos';
  end if;

  if p_solicitud_id is null
     or nullif(btrim(p_motivo), '') is null
     or length(btrim(p_motivo)) > 500 then
    raise exception 'Motivo y clave de aprobación son obligatorios';
  end if;

  select producto_id, conteo_id
    into v_producto, v_conteo
  from public.inventario_conteos_items
  where id = p_item_id;

  if not found then
    raise exception 'Línea inexistente';
  end if;

  perform 1 from public.productos p
  where p.id = v_producto
  for update;

  if not found then
    raise exception 'Producto inexistente para aprobación';
  end if;

  select * into v_sesion
  from public.inventario_conteos
  where id = v_conteo
  for update;

  select * into v_item
  from public.inventario_conteos_items
  where id = p_item_id
  for update;

  if v_item.estado = 'aprobado' then
    if v_item.operacion_aprobacion_id <> p_solicitud_id
       or v_item.aprobado_por <> auth.uid()
       or v_item.motivo_aprobacion <> btrim(p_motivo) then
      raise exception 'La aprobación ya fue registrada con otros datos';
    end if;

    return jsonb_build_object(
      'item_id', p_item_id, 'estado', 'aprobado',
      'movimiento_id', v_item.movimiento_id,
      'diferencia', v_item.diferencia_base
    );
  end if;

  if v_sesion.estado <> 'abierto'
     or v_item.estado <> 'pendiente_aprobacion'
     or v_item.cantidad_confirmada_base is null
     or v_item.saldo_teorico_corte is null then
    raise exception 'La línea no está lista para aprobar';
  end if;

  if exists (
    select 1 from public.inventario_conteo_capturas c
    where c.conteo_item_id = p_item_id
      and c.contado_por = auth.uid()
  ) then
    raise exception 'Quien contó o recontó el producto no puede aprobarlo';
  end if;

  if not exists (
    select 1 from public.inventario_conteos_bloqueos b
    where b.conteo_item_id = p_item_id
      and b.producto_id = v_producto
  ) then
    raise exception 'El producto ya no está protegido por esta sesión';
  end if;

  v_delta := v_item.cantidad_confirmada_base - v_item.saldo_teorico_corte;

  if v_delta < -2147483648 or v_delta > 2147483647 then
    raise exception 'La diferencia excede el rango admitido por Kardex';
  end if;

  if v_delta <> 0 then
    select * into v_existing
    from public.inventario_movimientos
    where tipo = 'ajuste' and referencia_id = p_item_id;

    if found then
      raise exception 'La línea ya tiene un ajuste Kardex';
    end if;
  end if;

  -- El trigger de Kardex valida que la línea ya esté aprobada y que el actor,
  -- producto, delta y clave de operación coincidan.
  delete from public.inventario_conteos_bloqueos
  where conteo_item_id = p_item_id;

  update public.inventario_conteos_items
  set estado = 'aprobado',
      aprobado_por = auth.uid(),
      aprobado_en = now(),
      operacion_aprobacion_id = p_solicitud_id,
      motivo_aprobacion = btrim(p_motivo)
  where id = p_item_id;

  if v_delta <> 0 then
    insert into public.inventario_movimientos(
      producto_id, tipo, unidades_delta, referencia_id,
      operacion_id, notas, creado_por
    )
    values (
      v_producto, 'ajuste', v_delta::integer, p_item_id,
      p_solicitud_id,
      left('Conteo físico: ' || v_sesion.motivo || ' | Aprobación: ' || btrim(p_motivo), 500),
      auth.uid()
    )
    returning id into v_movimiento;

    update public.inventario_conteos_items
    set movimiento_id = v_movimiento
    where id = p_item_id;
  end if;

  if not exists (
    select 1 from public.inventario_conteos_items i
    where i.conteo_id = v_sesion.id
      and i.estado not in ('aprobado', 'cancelado')
  ) then
    update public.inventario_conteos
    set estado = 'cerrado', cerrado_por = auth.uid(), cerrado_en = now()
    where id = v_sesion.id;
  end if;

  return jsonb_build_object(
    'item_id', p_item_id, 'estado', 'aprobado',
    'movimiento_id', v_movimiento, 'diferencia', v_delta
  );
end;
$function$;

-- Cancelación: bloquea todos los productos afectados por UUID antes de la
-- sesión. Las operaciones que esperan verán el producto liberado al confirmar.
create or replace function public.cancelar_conteo_inventario(
  p_conteo_id uuid,
  p_solicitud_id uuid,
  p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_producto uuid;
  v_sesion public.inventario_conteos%rowtype;
begin
  if auth.uid() is null
     or not public.es_usuario_drosalud()
     or not public.es_admin_drosalud() then
    raise exception 'Solo administración puede cancelar un conteo';
  end if;

  if p_solicitud_id is null
     or nullif(btrim(p_motivo), '') is null
     or length(btrim(p_motivo)) > 500 then
    raise exception 'Motivo y clave de cancelación son obligatorios';
  end if;

  for v_producto in
    select distinct b.producto_id
    from public.inventario_conteos_bloqueos b
    where b.conteo_id = p_conteo_id
    order by b.producto_id
  loop
    perform 1 from public.productos p
    where p.id = v_producto
    for update;

    if not found then
      raise exception 'Producto inexistente al cancelar el conteo';
    end if;
  end loop;

  select * into v_sesion
  from public.inventario_conteos
  where id = p_conteo_id
  for update;

  if not found then
    raise exception 'Conteo inexistente';
  end if;

  if v_sesion.estado = 'cancelado' then
    if v_sesion.solicitud_cancelacion_id <> p_solicitud_id
       or v_sesion.cancelado_por <> auth.uid()
       or v_sesion.motivo_cancelacion <> btrim(p_motivo) then
      raise exception 'Cancelación ya registrada con otros datos';
    end if;

    return jsonb_build_object('conteo_id', p_conteo_id, 'estado', 'cancelado');
  end if;

  if v_sesion.estado <> 'abierto' then
    raise exception 'La sesión ya está cerrada';
  end if;

  update public.inventario_conteos_items
  set estado = 'cancelado'
  where conteo_id = p_conteo_id
    and estado <> 'aprobado';

  delete from public.inventario_conteos_bloqueos
  where conteo_id = p_conteo_id;

  update public.inventario_conteos
  set estado = 'cancelado',
      cancelado_por = auth.uid(),
      cancelado_en = now(),
      motivo_cancelacion = left(btrim(p_motivo), 500),
      solicitud_cancelacion_id = p_solicitud_id
  where id = p_conteo_id;

  return jsonb_build_object('conteo_id', p_conteo_id, 'estado', 'cancelado');
end;
$function$;

notify pgrst, 'reload schema';

commit;
