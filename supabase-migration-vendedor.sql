-- Vendedor (opcional) en cada recibo
alter table public.recibos
  add column if not exists vendedor text;
