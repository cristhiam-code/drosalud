-- Drosalud · Inventario y Kardex
-- Preparado para revisión. No ejecutar en producción hasta probar en entorno aislado.
begin;

-- Clasificación comercial editable por producto, utilizada por el filtro del Kardex.
alter table public.productos add column if not exists linea text;

-- Mantiene la vista de aplicación y expone la nueva clasificación al frontend.
create or replace view public.productos_app
with (security_barrier = true)
as
select id, codigo, nombre, laboratorio, precio_compra, actualizado_en,
       precio_venta, fraccionable, unidades_por_caja, unidades_por_venta,
       linea
from public.productos p
where es_usuario_drosalud();

create table if not exists public.inventario_movimientos (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id) on delete restrict,
  tipo text not null check (tipo in ('venta','anulacion','recepcion')),
  unidades_delta integer not null check (unidades_delta <> 0),
  referencia_id uuid,
  operacion_id uuid,
  notas text,
  creado_por uuid default auth.uid() references auth.users(id),
  creado_en timestamptz not null default now()
);

create index if not exists inventario_movimientos_producto_fecha_idx
  on public.inventario_movimientos(producto_id, creado_en desc);
create index if not exists inventario_movimientos_saldo_idx
  on public.inventario_movimientos(producto_id) include (unidades_delta);
create unique index if not exists inventario_movimientos_origen_unico_idx
  on public.inventario_movimientos(tipo, referencia_id)
  where referencia_id is not null and tipo in ('venta','anulacion');
create unique index if not exists inventario_movimientos_recepcion_operacion_unico_idx
  on public.inventario_movimientos(operacion_id)
  where tipo='recepcion' and operacion_id is not null;

alter table public.inventario_movimientos enable row level security;
revoke all on public.inventario_movimientos from anon, authenticated;
grant select on public.inventario_movimientos to authenticated;

drop policy if exists inventario_movimientos_lectura_autorizada on public.inventario_movimientos;
create policy inventario_movimientos_lectura_autorizada
  on public.inventario_movimientos for select to authenticated
  using (public.es_usuario_drosalud());

-- Saldo consolidado por producto; la vista respeta RLS del usuario que consulta.
create or replace view public.inventario_saldos
with (security_invoker = true)
as
select producto_id, sum(unidades_delta)::bigint as saldo_unidades
from public.inventario_movimientos
group by producto_id;

revoke all on public.inventario_saldos from anon, authenticated;
grant select on public.inventario_saldos to authenticated;

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
      (new.producto_id, 'venta', -(new.cantidad * coalesce(new.unidades_por_presentacion, 1)), new.id,
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
revoke all on function public.fn_inventario_descuenta_venta() from public, anon, authenticated;

create or replace function public.fn_inventario_revierte_anulacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(old.anulado, false) = false and new.anulado is true then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    select ri.producto_id, 'anulacion', -venta.unidades_delta, ri.id,
           'Reversión automática por anulación del recibo ' || new.numero::text,
           auth.uid()
    from public.recibo_items ri
    join public.inventario_movimientos venta
      on venta.tipo = 'venta'
     and venta.referencia_id = ri.id
     and venta.producto_id = ri.producto_id
     and venta.unidades_delta < 0
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
revoke all on function public.fn_inventario_revierte_anulacion() from public, anon, authenticated;

create or replace function public.registrar_recepcion_inventario(
  p_producto_id uuid,
  p_unidades integer,
  p_notas text,
  p_operacion_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_existente public.inventario_movimientos%rowtype;
  v_notas text;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_producto_id is null or p_unidades is null or p_unidades <= 0 or p_operacion_id is null then
    raise exception 'Producto, unidades y clave de operación deben ser válidos';
  end if;
  if not exists (select 1 from public.productos where id = p_producto_id) then
    raise exception 'Producto inexistente';
  end if;

  v_notas := nullif(left(trim(coalesce(p_notas,'')),500),'');
  insert into public.inventario_movimientos
    (producto_id, tipo, unidades_delta, operacion_id, notas, creado_por)
  values
    (p_producto_id, 'recepcion', p_unidades, p_operacion_id,
     v_notas, auth.uid())
  on conflict (operacion_id)
    where tipo='recepcion' and operacion_id is not null
  do nothing
  returning id into v_id;

  if v_id is null then
    select * into v_existente
    from public.inventario_movimientos
    where tipo='recepcion' and operacion_id=p_operacion_id;

    if not found then
      raise exception 'No fue posible confirmar la recepción';
    end if;
    if v_existente.producto_id <> p_producto_id
       or v_existente.unidades_delta <> p_unidades
       or coalesce(v_existente.notas,'') <> coalesce(v_notas,'') then
      raise exception 'La clave de operación ya fue utilizada con otros datos';
    end if;
    v_id := v_existente.id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.registrar_recepcion_inventario(uuid,integer,text,uuid) from public, anon;
grant execute on function public.registrar_recepcion_inventario(uuid,integer,text,uuid) to authenticated;

commit;
