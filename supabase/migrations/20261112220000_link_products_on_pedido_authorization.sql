-- Permite al administrador vincular líneas de texto al catálogo al autorizar el pedido.
create or replace function public.autorizar_pedido(p_pedido_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_item jsonb;
  v_item_id uuid;
  v_producto_id uuid;
  v_cantidad integer;
  v_total integer;
  v_actualizados integer := 0;
begin
  if auth.uid() is null or not public.es_admin_drosalud() then
    raise exception 'Solo el administrador puede autorizar pedidos';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Debes indicar las cantidades que autorizas';
  end if;
  perform 1 from public.pedidos where id = p_pedido_id and estado = 'pendiente_autorizacion' for update;
  if not found then
    raise exception 'El pedido no existe o no está pendiente de autorización';
  end if;
  select count(*) into v_total from public.pedidos_items where pedido_id = p_pedido_id;
  if jsonb_array_length(p_items) <> v_total
     or (select count(distinct x.pedido_item_id)
           from jsonb_to_recordset(p_items) as x(pedido_item_id uuid, cantidad_autorizada integer, producto_id uuid)) <> v_total then
    raise exception 'Debes revisar una sola vez todas las líneas del pedido';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_item_id := (v_item->>'pedido_item_id')::uuid;
    v_cantidad := (v_item->>'cantidad_autorizada')::integer;
    v_producto_id := nullif(v_item->>'producto_id','')::uuid;
    if v_cantidad is null or v_cantidad < 0 then
      raise exception 'La cantidad autorizada no puede ser negativa';
    end if;
    if v_producto_id is not null and not exists (
      select 1 from public.productos where id = v_producto_id
    ) then
      raise exception 'El producto vinculado ya no existe en el catálogo';
    end if;
    update public.pedidos_items
       set cantidad_autorizada = v_cantidad,
           producto_id = coalesce(v_producto_id, producto_id),
           actualizado_en = now()
     where id = v_item_id
       and pedido_id = p_pedido_id
       and v_cantidad <= cantidad_solicitada;
    if not found then
      raise exception 'Una cantidad autorizada supera lo solicitado o una línea no pertenece al pedido';
    end if;
    v_actualizados := v_actualizados + 1;
  end loop;

  if v_actualizados <> v_total or not exists (
    select 1 from public.pedidos_items
     where pedido_id = p_pedido_id and cantidad_autorizada > 0
  ) then
    raise exception 'Debes autorizar al menos una unidad';
  end if;

  update public.pedidos
     set estado = 'autorizado',
         autorizado_por = auth.uid(),
         autorizado_en = now(),
         actualizado_en = now()
   where id = p_pedido_id;
end;
$function$;

revoke all on function public.autorizar_pedido(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.autorizar_pedido(uuid,jsonb) to authenticated;
