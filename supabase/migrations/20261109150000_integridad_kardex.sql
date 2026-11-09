-- Drosalud · Integridad del Kardex
-- Cada codigo identifica una presentacion concreta.
-- Si el producto ya tiene movimientos, su codigo y equivalencias quedan inmutables.
-- Las correcciones de una venta se realizan anulando el recibo y creando uno nuevo.
begin;

create or replace function public.proteger_presentacion_con_movimientos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
       new.codigo is distinct from old.codigo
    or new.fraccionable is distinct from old.fraccionable
    or new.unidades_por_caja is distinct from old.unidades_por_caja
    or new.unidades_por_venta is distinct from old.unidades_por_venta
  ) and exists (
    select 1
    from public.inventario_movimientos im
    where im.producto_id = old.id
  ) then
    raise exception
      'Este producto ya tiene movimientos en el Kardex. Registre la nueva presentacion con un codigo nuevo.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_presentacion_con_movimientos on public.productos;
create trigger trg_proteger_presentacion_con_movimientos
before update of codigo, fraccionable, unidades_por_caja, unidades_por_venta
on public.productos
for each row
execute function public.proteger_presentacion_con_movimientos();

revoke all on function public.proteger_presentacion_con_movimientos() from public, anon, authenticated;

-- Una linea que ya produjo salida de inventario no se edita ni elimina.
-- Para corregirla, se anula el recibo completo y se registra una venta nueva.
create or replace function public.proteger_linea_con_movimiento_kardex()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.inventario_movimientos im
    where im.tipo = 'venta'
      and im.referencia_id = old.id
  ) then
    raise exception
      'Esta linea ya esta registrada en el Kardex. Anule el recibo y cree uno nuevo para corregir la venta.'
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_linea_con_movimiento_kardex on public.recibo_items;
create trigger trg_proteger_linea_con_movimiento_kardex
before update or delete on public.recibo_items
for each row
execute function public.proteger_linea_con_movimiento_kardex();

revoke all on function public.proteger_linea_con_movimiento_kardex() from public, anon, authenticated;

-- Evita reactivar un recibo ya revertido o borrar una venta con movimientos.
create or replace function public.proteger_recibo_con_movimiento_kardex()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1
      from public.recibo_items ri
      join public.inventario_movimientos im
        on im.referencia_id = ri.id
       and im.tipo in ('venta','anulacion')
      where ri.recibo_id = old.id
    ) then
      raise exception
        'Este recibo ya tiene movimientos en el Kardex y no se puede eliminar.'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if old.anulado is true and new.anulado is false
     and exists (
       select 1
       from public.recibo_items ri
       join public.inventario_movimientos im
         on im.referencia_id = ri.id
        and im.tipo = 'anulacion'
       where ri.recibo_id = old.id
     ) then
    raise exception
      'Este recibo ya fue revertido en el Kardex y no se puede reactivar.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_proteger_recibo_con_movimiento_kardex on public.recibos;
create trigger trg_proteger_recibo_con_movimiento_kardex
before update of anulado or delete on public.recibos
for each row
execute function public.proteger_recibo_con_movimiento_kardex();

revoke all on function public.proteger_recibo_con_movimiento_kardex() from public, anon, authenticated;

commit;
