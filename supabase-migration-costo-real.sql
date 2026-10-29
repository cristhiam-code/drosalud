-- Drosalud: vincular el costo real de compra con una línea de recibo.
-- Ejecutar primero en un proyecto Supabase de pruebas. No modifica datos históricos existentes.

alter table public.recibo_items
  add column if not exists costo_real_unitario numeric
  check (costo_real_unitario is null or costo_real_unitario >= 0);

alter table public.compras_pendientes
  add column if not exists recibo_item_id uuid
  references public.recibo_items(id) on delete set null;

create index if not exists compras_pendientes_recibo_item_idx
  on public.compras_pendientes (recibo_item_id);

create or replace function public.aplicar_costo_real_compra(
  p_compra_id uuid,
  p_recibo_item_id uuid,
  p_costo_real numeric
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_compra public.compras_pendientes%rowtype;
  v_item public.recibo_items%rowtype;
  v_costo_anterior numeric;
  v_delta numeric;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if p_costo_real is null or p_costo_real < 0 then
    raise exception 'El costo real debe ser un valor mayor o igual a cero.';
  end if;

  select * into v_compra
  from public.compras_pendientes
  where id = p_compra_id and owner_id = auth.uid()
  for update;

  if not found then
    raise exception 'No se encontró la compra o no tienes permiso.';
  end if;

  select * into v_item
  from public.recibo_items
  where id = p_recibo_item_id
  for update;

  if not found then
    raise exception 'No se encontró la línea del recibo.';
  end if;

  if v_compra.recibo_id is null or v_item.recibo_id <> v_compra.recibo_id then
    raise exception 'La línea seleccionada no pertenece al recibo asociado a esta compra.';
  end if;

  v_costo_anterior := coalesce(v_item.costo_real_unitario, v_item.precio_compra);
  v_delta := (v_costo_anterior - p_costo_real) * v_item.cantidad;

  update public.recibo_items
  set costo_real_unitario = p_costo_real
  where id = p_recibo_item_id;

  update public.recibos
  set ganancia = ganancia + v_delta
  where id = v_item.recibo_id;

  update public.compras_pendientes
  set recibo_item_id = p_recibo_item_id,
      costo_real = p_costo_real,
      estado = case when estado in ('pendiente','cotizando') then 'comprado' else estado end,
      comprado_en = coalesce(comprado_en, now()),
      actualizado_en = now()
  where id = p_compra_id;
end;
$$;

revoke all on function public.aplicar_costo_real_compra(uuid, uuid, numeric) from public;
grant execute on function public.aplicar_costo_real_compra(uuid, uuid, numeric) to authenticated;
