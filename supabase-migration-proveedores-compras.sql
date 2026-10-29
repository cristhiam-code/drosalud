-- Drosalud: proveedores y compras bajo demanda
-- Ejecutar manualmente en Supabase SQL Editor DESPUES de revisar el archivo.
-- No crea inventario ni modifica tablas existentes.

create table if not exists public.proveedores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  contacto text,
  telefono text,
  whatsapp text,
  email text,
  notas text,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table if not exists public.compras_pendientes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  producto_id uuid references public.productos(id) on delete set null,
  producto_nombre text not null,
  cantidad integer not null default 1 check (cantidad > 0),
  recibo_id uuid references public.recibos(id) on delete set null,
  proveedor_id uuid references public.proveedores(id) on delete set null,
  costo_estimado numeric check (costo_estimado is null or costo_estimado >= 0),
  costo_real numeric check (costo_real is null or costo_real >= 0),
  estado text not null default 'pendiente'
    check (estado in ('pendiente','cotizando','comprado','entregado','cancelado')),
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  comprado_en timestamptz
);

create table if not exists public.cotizaciones_proveedor (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  compra_id uuid not null references public.compras_pendientes(id) on delete cascade,
  proveedor_id uuid not null references public.proveedores(id) on delete cascade,
  precio_unitario numeric not null check (precio_unitario >= 0),
  disponible boolean,
  consultado_en timestamptz not null default now(),
  notas text
);

create index if not exists proveedores_owner_nombre_idx
  on public.proveedores (owner_id, nombre);
create index if not exists compras_pendientes_owner_estado_idx
  on public.compras_pendientes (owner_id, estado, creado_en desc);
create index if not exists compras_pendientes_recibo_idx
  on public.compras_pendientes (recibo_id);
create index if not exists cotizaciones_compra_idx
  on public.cotizaciones_proveedor (compra_id, consultado_en desc);

alter table public.proveedores enable row level security;
alter table public.compras_pendientes enable row level security;
alter table public.cotizaciones_proveedor enable row level security;

drop policy if exists "propietario gestiona proveedores" on public.proveedores;
create policy "propietario gestiona proveedores" on public.proveedores
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "propietario gestiona compras" on public.compras_pendientes;
create policy "propietario gestiona compras" on public.compras_pendientes
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "propietario gestiona cotizaciones" on public.cotizaciones_proveedor;
create policy "propietario gestiona cotizaciones" on public.cotizaciones_proveedor
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create or replace function public.actualizar_fecha_compras()
returns trigger language plpgsql as $$
begin
  new.actualizado_en = now();
  return new;
end;
$$;

drop trigger if exists trg_proveedores_actualizado on public.proveedores;
create trigger trg_proveedores_actualizado
before update on public.proveedores
for each row execute function public.actualizar_fecha_compras();

drop trigger if exists trg_compras_pendientes_actualizado on public.compras_pendientes;
create trigger trg_compras_pendientes_actualizado
before update on public.compras_pendientes
for each row execute function public.actualizar_fecha_compras();
