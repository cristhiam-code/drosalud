
create index if not exists sucursales_creado_por_idx on public.sucursales(creado_por);
create index if not exists usuarios_sucursales_sucursal_idx on public.usuarios_sucursales(sucursal_id);
create index if not exists usuarios_sucursales_asignado_por_idx on public.usuarios_sucursales(asignado_por);
create index if not exists sucursal_dias_pedido_actualizado_por_idx on public.sucursal_dias_pedido(actualizado_por);
