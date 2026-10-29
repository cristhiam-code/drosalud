-- Drosalud: guardar compra y aplicar costo real en una sola transacción.
-- Ejecutar una vez en el SQL Editor del mismo proyecto Supabase.
-- Si cualquier validación o actualización falla, PostgreSQL revierte TODA la operación.

create or replace function public.guardar_compra_con_costo_real(
  p_compra_id uuid,
  p_producto_nombre text,
  p_cantidad integer,
  p_proveedor_id uuid,
  p_costo_estimado numeric,
  p_estado text,
  p_notas text,
  p_recibo_id uuid,
  p_recibo_item_id uuid,
  p_costo_real numeric
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_compra public.compras_pendientes%rowtype;
  v_item public.recibo_items%rowtype;
  v_id uuid;
  v_delta numeric;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if nullif(trim(p_producto_nombre), '') is null then
    raise exception 'Escribe el medicamento.';
  end if;
  if p_cantidad is null or p_cantidad < 1 then
    raise exception 'La cantidad debe ser al menos 1.';
  end if;
  if p_costo_real is null or p_costo_real < 0 then
    raise exception 'El costo real debe ser mayor o igual a cero.';
  end if;
  if p_costo_estimado is not null and p_costo_estimado < 0 then
    raise exception 'El costo estimado no puede ser negativo.';
  end if;
  if p_estado not in ('pendiente','cotizando','comprado','entregado','cancelado') then
    raise exception 'Estado de compra no válido.';
  end if;
  if p_recibo_id is null or p_recibo_item_id is null then
    raise exception 'Selecciona el recibo y la línea que recibirá el costo real.';
  end if;

  if p_proveedor_id is not null and not exists (
    select 1 from public.proveedores
    where id = p_proveedor_id and owner_id = v_uid
  ) then
    raise exception 'El proveedor no existe o no te pertenece.';
  end if;

  if p_compra_id is null then
    insert into public.compras_pendientes (
      owner_id, producto_nombre, cantidad, proveedor_id,
      costo_estimado, costo_real, estado, notas, recibo_id, recibo_item_id,
      comprado_en
    ) values (
      v_uid, trim(p_producto_nombre), p_cantidad, p_proveedor_id,
      p_costo_estimado, null, p_estado, p_notas, p_recibo_id, p_recibo_item_id,
      now()
    )
    returning id into v_id;
    select * into v_compra from public.compras_pendientes where id = v_id for update;
  else
    select * into v_compra
    from public.compras_pendientes
    where id = p_compra_id and owner_id = v_uid
    for update;

    if not found then
      raise exception 'No se encontró la compra o no tienes permiso.';
    end if;

    if v_compra.recibo_item_id is not null and
       (v_compra.recibo_item_id <> p_recibo_item_id or v_compra.recibo_id <> p_recibo_id) then
      raise exception 'Esta compra ya está vinculada a una línea. No cambies el recibo ni la línea.';
    end if;
    v_id := v_compra.id;
  end if;

  select * into v_item
  from public.recibo_items
  where id = p_recibo_item_id and recibo_id = p_recibo_id
  for update;

  if not found then
    raise exception 'La línea seleccionada no pertenece al recibo indicado.';
  end if;

  v_delta := (coalesce(v_item.costo_real_unitario, v_item.precio_compra) - p_costo_real)
             * v_item.cantidad;

  update public.recibo_items
  set costo_real_unitario = p_costo_real
  where id = p_recibo_item_id;

  update public.recibos
  set ganancia = coalesce(ganancia, 0) + v_delta
  where id = p_recibo_id;

  update public.compras_pendientes
  set producto_nombre = trim(p_producto_nombre),
      cantidad = p_cantidad,
      proveedor_id = p_proveedor_id,
      costo_estimado = p_costo_estimado,
      costo_real = p_costo_real,
      estado = case when p_estado in ('pendiente','cotizando') then 'comprado' else p_estado end,
      notas = p_notas,
      recibo_id = p_recibo_id,
      recibo_item_id = p_recibo_item_id,
      comprado_en = coalesce(comprado_en, now()),
      actualizado_en = now()
  where id = v_id and owner_id = v_uid;

  return v_id;
end;
$$;

revoke all on function public.guardar_compra_con_costo_real(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric) from public;
grant execute on function public.guardar_compra_con_costo_real(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric) to authenticated;

-- La interfaz ya utiliza la función atómica; elimina la RPC anterior de dos pasos.
drop function if exists public.aplicar_costo_real_compra(uuid, uuid, numeric);
