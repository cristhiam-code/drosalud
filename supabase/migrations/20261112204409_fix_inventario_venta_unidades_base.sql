create or replace function public.fn_inventario_descuenta_venta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.producto_id is not null then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    values
      (new.producto_id, 'venta', -new.cantidad, new.id,
       'Descuento automático por recibo (cantidad en unidades base)', auth.uid())
    on conflict (tipo, referencia_id)
      where referencia_id is not null and tipo in ('venta','anulacion')
    do nothing;
  end if;
  return new;
end;
$function$;

do $validation$
begin
  if exists (
    select 1
    from public.recibo_items ri
    join public.inventario_movimientos m
      on m.tipo = 'venta' and m.referencia_id = ri.id
    where ri.producto_id is not null
      and m.unidades_delta <> -ri.cantidad
  ) then
    raise exception 'Prueba fallida: existen movimientos de venta que no coinciden con unidades base';
  end if;
  if exists (
    select 1
    from public.recibos r
    join public.recibo_items ri on ri.recibo_id = r.id
    left join public.inventario_movimientos v
      on v.tipo='venta' and v.referencia_id=ri.id
    left join public.inventario_movimientos a
      on a.tipo='anulacion' and a.referencia_id=ri.id
    where ri.producto_id is not null
      and ((r.anulado and (v.id is null or a.unidades_delta is distinct from ri.cantidad))
        or (not r.anulado and a.id is not null))
  ) then
    raise exception 'Prueba fallida: ventas/anulaciones no están reconciliadas';
  end if;
end;
$validation$;
