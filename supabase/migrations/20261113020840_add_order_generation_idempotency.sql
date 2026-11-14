-- Idempotencia para reintentos de generación de órdenes por pedido.
alter table public.ordenes_compra
  add column operacion_id uuid,
  add column request_hash text;

create unique index ordenes_compra_pedido_operacion_proveedor_uidx
  on public.ordenes_compra(pedido_id, operacion_id, proveedor_id)
  where pedido_id is not null and operacion_id is not null;

drop function if exists public.generar_ordenes_compra_pedido(uuid,jsonb);

create function public.generar_ordenes_compra_pedido(
  p_pedido_id uuid,
  p_asignaciones jsonb,
  p_operacion_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_provider record;
  v_line record;
  v_order_id uuid;
  v_order_numero bigint;
  v_autorizada integer;
  v_producto_id uuid;
  v_ya_asignado integer;
  v_nuevo integer;
  v_ordenes jsonb := '[]'::jsonb;
  v_hash text;
  v_hash_existente text;
begin
  if auth.uid() is null or not public.es_admin_drosalud() then
    raise exception 'Solo el administrador puede generar órdenes de compra';
  end if;
  if p_operacion_id is null then
    raise exception 'Falta el identificador de operación para evitar duplicados';
  end if;
  perform 1 from public.pedidos where id = p_pedido_id and estado = 'autorizado' for update;
  if not found then
    raise exception 'El pedido debe estar autorizado antes de generar órdenes';
  end if;

  v_hash := md5(coalesce(p_asignaciones::text,'null'));
  select min(oc.request_hash) into v_hash_existente
    from public.ordenes_compra oc
   where oc.pedido_id = p_pedido_id and oc.operacion_id = p_operacion_id;
  if v_hash_existente is not null then
    if v_hash_existente <> v_hash then
      raise exception 'El identificador de operación ya fue usado con otras asignaciones';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',oc.id,'numero',oc.numero,'proveedor_id',oc.proveedor_id
    ) order by oc.numero),'[]'::jsonb)
      into v_ordenes
      from public.ordenes_compra oc
     where oc.pedido_id = p_pedido_id and oc.operacion_id = p_operacion_id;
    return jsonb_build_object('pedido_id',p_pedido_id,'ordenes',v_ordenes,'repetida',true);
  end if;

  if p_asignaciones is null or jsonb_typeof(p_asignaciones) <> 'array'
     or jsonb_array_length(p_asignaciones) = 0 then
    raise exception 'Debes asignar productos a proveedores';
  end if;

  if exists (
    select 1
      from jsonb_to_recordset(p_asignaciones) as a(
        pedido_item_id uuid, proveedor_id uuid, unidades integer, costo_unitario_base numeric
      )
     where a.pedido_item_id is null or a.proveedor_id is null
        or a.unidades is null or a.unidades <= 0
        or a.costo_unitario_base is null or a.costo_unitario_base < 0
  ) then
    raise exception 'Hay asignaciones con proveedor, unidades o costo inválido';
  end if;

  for v_line in
    select a.pedido_item_id, sum(a.unidades)::integer as unidades
      from jsonb_to_recordset(p_asignaciones) as a(
        pedido_item_id uuid, proveedor_id uuid, unidades integer, costo_unitario_base numeric
      )
     group by a.pedido_item_id
  loop
    select pi.cantidad_autorizada, pi.producto_id
      into v_autorizada, v_producto_id
      from public.pedidos_items pi
     where pi.id = v_line.pedido_item_id and pi.pedido_id = p_pedido_id;
    if not found then
      raise exception 'Una línea no pertenece al pedido autorizado';
    end if;
    if v_producto_id is null then
      raise exception 'Vincula todos los productos sin catálogo antes de generar la orden';
    end if;
    if coalesce(v_autorizada, 0) <= 0 then
      raise exception 'La línea no tiene unidades autorizadas';
    end if;

    select coalesce(sum(oi.unidades_solicitadas), 0)::integer
      into v_ya_asignado
      from public.ordenes_compra_items oi
      join public.ordenes_compra oc on oc.id = oi.orden_id
     where oi.pedido_item_id = v_line.pedido_item_id
       and oc.estado <> 'cancelada';

    if v_ya_asignado + v_line.unidades > v_autorizada then
      raise exception 'La suma de órdenes supera las unidades autorizadas para una línea';
    end if;
  end loop;

  for v_provider in
    select distinct a.proveedor_id
      from jsonb_to_recordset(p_asignaciones) as a(
        pedido_item_id uuid, proveedor_id uuid, unidades integer, costo_unitario_base numeric
      )
     order by a.proveedor_id
  loop
    if not exists (
      select 1 from public.proveedores p
       where p.id = v_provider.proveedor_id and p.activo = true
    ) then
      raise exception 'Uno de los proveedores no existe o está inactivo';
    end if;

    insert into public.ordenes_compra(
      pedido_id, proveedor_id, estado, notas, creado_por, operacion_id, request_hash
    )
    select p_pedido_id, v_provider.proveedor_id, 'aprobada',
           'Generada desde pedido interno #' || p.numero, auth.uid(), p_operacion_id, v_hash
      from public.pedidos p
     where p.id = p_pedido_id
    returning id, numero into v_order_id, v_order_numero;

    for v_line in
      select a.pedido_item_id,
             sum(a.unidades)::integer as unidades,
             (sum(a.unidades * a.costo_unitario_base) / sum(a.unidades))::numeric(14,2) as costo
        from jsonb_to_recordset(p_asignaciones) as a(
          pedido_item_id uuid, proveedor_id uuid, unidades integer, costo_unitario_base numeric
        )
       where a.proveedor_id = v_provider.proveedor_id
       group by a.pedido_item_id
    loop
      select pi.producto_id into v_producto_id
        from public.pedidos_items pi
       where pi.id = v_line.pedido_item_id and pi.pedido_id = p_pedido_id;

      insert into public.ordenes_compra_items(
        orden_id, producto_id, unidades_solicitadas, costo_unitario_base, pedido_item_id
      ) values (
        v_order_id, v_producto_id, v_line.unidades, v_line.costo, v_line.pedido_item_id
      );
    end loop;

    v_ordenes := v_ordenes || jsonb_build_array(jsonb_build_object(
      'id', v_order_id, 'numero', v_order_numero, 'proveedor_id', v_provider.proveedor_id
    ));
  end loop;

  return jsonb_build_object('pedido_id', p_pedido_id, 'ordenes', v_ordenes,'repetida',false);
end;
$function$;

revoke all on function public.generar_ordenes_compra_pedido(uuid,jsonb,uuid) from public, anon, authenticated;
grant execute on function public.generar_ordenes_compra_pedido(uuid,jsonb,uuid) to authenticated;
