-- Drosalud · Permitir ajustes de costo sin alterar el Kardex
-- El movimiento de inventario depende de producto, cantidad y recibo.
-- Los cambios de precio/costo no cambian unidades y deben seguir permitidos.
begin;

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
    if tg_op = 'DELETE'
       or new.producto_id is distinct from old.producto_id
       or new.cantidad is distinct from old.cantidad
       or new.recibo_id is distinct from old.recibo_id then
      raise exception
        'Esta linea ya esta registrada en el Kardex. Anule el recibo y cree uno nuevo para cambiar producto o cantidad.'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.proteger_linea_con_movimiento_kardex() from public, anon, authenticated;

commit;
