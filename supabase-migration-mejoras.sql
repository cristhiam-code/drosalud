-- 1) Efectivo recibido (para calcular los vueltos)
alter table public.recibos
  add column if not exists recibido numeric;

-- 2) Historial de precios de compra
create table if not exists public.historial_precios (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id) on delete cascade,
  precio_anterior numeric not null,
  precio_nuevo numeric not null,
  creado_en timestamptz not null default now()
);

alter table public.historial_precios enable row level security;

drop policy if exists "solo con sesion" on public.historial_precios;
create policy "solo con sesion" on public.historial_precios
  for all to authenticated using (true) with check (true);

create or replace function public.log_precio_compra()
returns trigger
language plpgsql
as $$
begin
  if new.precio_compra is distinct from old.precio_compra then
    insert into public.historial_precios (producto_id, precio_anterior, precio_nuevo)
    values (new.id, old.precio_compra, new.precio_compra);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_precio on public.productos;
create trigger trg_log_precio
  after update of precio_compra on public.productos
  for each row execute function public.log_precio_compra();

-- 3) Índices para que los filtros por fecha sigan rápidos
create index if not exists recibos_creado_idx on public.recibos (creado_en desc);
create index if not exists recibo_items_recibo_idx on public.recibo_items (recibo_id);
create index if not exists historial_precios_prod_idx on public.historial_precios (producto_id, creado_en desc);
