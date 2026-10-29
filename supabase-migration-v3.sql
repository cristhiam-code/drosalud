-- 1) Anular recibos (el recibo queda guardado, pero no cuenta en las ventas)
alter table public.recibos
  add column if not exists anulado boolean not null default false,
  add column if not exists anulado_en timestamptz,
  add column if not exists motivo_anulacion text;

-- 2) Productos más vendidos (últimos N días, sin contar recibos anulados)
create or replace function public.mas_vendidos(dias int default 60)
returns table (producto_id uuid, nombre text, unidades bigint)
language sql
stable
as $$
  select i.producto_id, max(i.nombre) as nombre, sum(i.cantidad)::bigint as unidades
  from public.recibo_items i
  join public.recibos r on r.id = i.recibo_id
  where r.creado_en >= now() - make_interval(days => dias)
    and not r.anulado
    and i.producto_id is not null
  group by i.producto_id
  order by unidades desc
  limit 12;
$$;

-- 3) Historial por cliente más rápido
create index if not exists recibos_cliente_idx on public.recibos (cliente_id);

-- 4) Que no se repita ningún número de recibo
create unique index if not exists recibos_numero_uk on public.recibos (numero);

-- 5) Reiniciar la numeración en 1, SOLO si ya no queda ningún recibo
do $$
begin
  if not exists (select 1 from public.recibos) then
    alter table public.recibos alter column numero restart with 1;
  end if;
end $$;
