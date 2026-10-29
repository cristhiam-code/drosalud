alter table public.clientes
add column if not exists direccion text;

alter table public.recibos
add column if not exists cliente_direccion text;
