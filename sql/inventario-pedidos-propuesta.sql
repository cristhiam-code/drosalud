-- DROSalud · Inventario y pedidos · PROPUESTA
-- No ejecutar en producción hasta revisar y aprobar pruebas.
-- Modelo: saldo = SUM(movimientos.unidades). Las ventas descuentan la cantidad
-- guardada en recibo_items (ya expresada en unidades individuales por el POS).

begin;

create table if not exists public.inventario_movimientos (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id),
  unidades integer not null check (unidades <> 0),
  tipo text not null check (tipo in ('venta','anulacion','recepcion','ajuste')),
  origen_id uuid,
  origen_item_id uuid,
  referencia text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  constraint inventario_movimientos_origen_uk
    unique (tipo, origen_id, origen_item_id)
);

create index if not exists inventario_movimientos_producto_fecha_idx
  on public.inventario_movimientos(producto_id, creado_en);

alter table public.inventario_movimientos enable row level security;

drop policy if exists inventario_movimientos_lectura_usuario on public.inventario_movimientos;
create policy inventario_movimientos_lectura_usuario
  on public.inventario_movimientos for select to authenticated
  using (public.es_usuario_drosalud());

revoke insert, update, delete on public.inventario_movimientos from anon, authenticated;
grant select on public.inventario_movimientos to authenticated;

create or replace function public.fn_inventario_venta_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.producto_id is not null then
    insert into public.inventario_movimientos
      (producto_id, unidades, tipo, origen_id, origen_item_id, referencia, creado_por)
    values
      (new.producto_id, -new.cantidad, 'venta', new.recibo_id, new.id,
       'Venta', (select r.creado_por from public.recibos r where r.id=new.recibo_id))
    on conflict (tipo, origen_id, origen_item_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inventario_venta_item on public.recibo_items;
create trigger trg_inventario_venta_item
after insert on public.recibo_items
for each row execute function public.fn_inventario_venta_item();

create or replace function public.fn_inventario_anulacion_recibo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.anulado is false and new.anulado is true then
    insert into public.inventario_movimientos
      (producto_id, unidades, tipo, origen_id, origen_item_id, referencia, creado_por)
    select ri.producto_id, ri.cantidad, 'anulacion', new.id, ri.id,
           'Reversión por anulación del recibo ' || new.numero::text, auth.uid()
    from public.recibo_items ri
    where ri.recibo_id=new.id and ri.producto_id is not null
    on conflict (tipo, origen_id, origen_item_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inventario_anulacion_recibo on public.recibos;
create trigger trg_inventario_anulacion_recibo
after update of anulado on public.recibos
for each row execute function public.fn_inventario_anulacion_recibo();

create or replace function public.registrar_recepcion_inventario(
  p_producto_id uuid,
  p_unidades integer,
  p_referencia text default null
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
  if not exists(select 1 from public.productos where id=p_producto_id) then
    raise exception 'Producto inexistente';
  end if;
  insert into public.inventario_movimientos
    (producto_id, unidades, tipo, referencia, creado_por)
  values
    (p_producto_id, p_unidades, 'recepcion',
     nullif(btrim(p_referencia), ''), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.registrar_recepcion_inventario(uuid,integer,text) from public, anon;
grant execute on function public.registrar_recepcion_inventario(uuid,integer,text) to authenticated;

create or replace view public.inventario_saldos
with (security_invoker = true)
as
select p.id as producto_id,
       coalesce(sum(m.unidades),0)::bigint as saldo_unidades
from public.productos p
left join public.inventario_movimientos m on m.producto_id=p.id
group by p.id;

grant select on public.inventario_saldos to authenticated;

commit;
