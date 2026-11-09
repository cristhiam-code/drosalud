-- Drosalud · Inventario y Kardex
-- Preparado para revisión. No ejecutar en producción hasta probar en entorno aislado.
begin;

create table if not exists public.inventario_movimientos (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id) on delete restrict,
  tipo text not null check (tipo in ('venta','anulacion','recepcion')),
  unidades_delta integer not null check (unidades_delta <> 0),
  referencia_id uuid,
  notas text,
  creado_por uuid default auth.uid() references auth.users(id),
  creado_en timestamptz not null default now()
);

create index if not exists inventario_movimientos_producto_fecha_idx
  on public.inventario_movimientos(producto_id, creado_en desc);
create unique index if not exists inventario_movimientos_origen_unico_idx
  on public.inventario_movimientos(tipo, referencia_id)
  where referencia_id is not null and tipo in ('venta','anulacion');

alter table public.inventario_movimientos enable row level security;
revoke all on public.inventario_movimientos from anon, authenticated;
grant select on public.inventario_movimientos to authenticated;

drop policy if exists inventario_movimientos_lectura_autorizada on public.inventario_movimientos;
create policy inventario_movimientos_lectura_autorizada
  on public.inventario_movimientos for select to authenticated
  using (public.es_usuario_drosalud());

create or replace function public.fn_inventario_descuenta_venta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.producto_id is not null then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    values
      (new.producto_id, 'venta', -new.cantidad, new.id,
       'Descuento automático por recibo', auth.uid())
    on conflict (tipo, referencia_id) where referencia_id is not null and tipo in ('venta','anulacion')
    do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inventario_venta_recibo_item on public.recibo_items;
create trigger trg_inventario_venta_recibo_item
  after insert on public.recibo_items
  for each row execute function public.fn_inventario_descuenta_venta();

create or replace function public.fn_inventario_revierte_anulacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.anulado is false and new.anulado is true then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    select ri.producto_id, 'anulacion', ri.cantidad, ri.id,
           'Reversión automática por anulación del recibo ' || new.numero::text,
           auth.uid()
    from public.recibo_items ri
    where ri.recibo_id = new.id
      and ri.producto_id is not null
    on conflict (tipo, referencia_id) where referencia_id is not null and tipo in ('venta','anulacion')
    do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inventario_anulacion_recibo on public.recibos;
create trigger trg_inventario_anulacion_recibo
  after update of anulado on public.recibos
  for each row execute function public.fn_inventario_revierte_anulacion();

create or replace function public.registrar_recepcion_inventario(
  p_producto_id uuid,
  p_unidades integer,
  p_notas text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_producto_id is null or p_unidades is null or p_unidades <= 0 then
    raise exception 'Producto y unidades recibidas deben ser válidos';
  end if;
  if not exists (select 1 from public.productos where id = p_producto_id) then
    raise exception 'Producto inexistente';
  end if;
  insert into public.inventario_movimientos
    (producto_id, tipo, unidades_delta, notas, creado_por)
  values
    (p_producto_id, 'recepcion', p_unidades,
     nullif(left(trim(coalesce(p_notas,'')),500),''), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.registrar_recepcion_inventario(uuid,integer,text) from public, anon;
grant execute on function public.registrar_recepcion_inventario(uuid,integer,text) to authenticated;

commit;
