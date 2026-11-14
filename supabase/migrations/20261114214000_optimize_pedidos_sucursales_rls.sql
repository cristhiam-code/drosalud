
drop policy if exists ps_sucursales_select on public.sucursales;
create policy ps_sucursales_select on public.sucursales for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.usuarios_sucursales us
  where us.user_id=(select auth.uid()) and us.sucursal_id=sucursales.id and us.activo
));

drop policy if exists ps_bodegas_select on public.bodegas;
create policy ps_bodegas_select on public.bodegas for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.usuarios_sucursales us
  where us.user_id=(select auth.uid()) and us.sucursal_id=bodegas.sucursal_id and us.activo
));

drop policy if exists ps_usuarios_sucursales_select on public.usuarios_sucursales;
create policy ps_usuarios_sucursales_select on public.usuarios_sucursales for select to authenticated
using ((select public.es_admin_drosalud()) or user_id=(select auth.uid()));

drop policy if exists ps_dias_pedido_select on public.sucursal_dias_pedido;
create policy ps_dias_pedido_select on public.sucursal_dias_pedido for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.usuarios_sucursales us
  where us.user_id=(select auth.uid()) and us.sucursal_id=sucursal_dias_pedido.sucursal_id and us.activo
));

drop policy if exists ps_inv_mov_select on public.inventario_sucursal_movimientos;
create policy ps_inv_mov_select on public.inventario_sucursal_movimientos for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.bodegas b join public.usuarios_sucursales us on us.sucursal_id=b.sucursal_id
  where b.id=inventario_sucursal_movimientos.bodega_id and us.user_id=(select auth.uid()) and us.activo
));

drop policy if exists ps_pedidos_select on public.pedidos_sucursal;
create policy ps_pedidos_select on public.pedidos_sucursal for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.usuarios_sucursales us
  where us.user_id=(select auth.uid()) and us.sucursal_id=pedidos_sucursal.sucursal_id and us.activo
));

drop policy if exists ps_pedido_items_select on public.pedidos_sucursal_items;
create policy ps_pedido_items_select on public.pedidos_sucursal_items for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.pedidos_sucursal p join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id
  where p.id=pedidos_sucursal_items.pedido_id and us.user_id=(select auth.uid()) and us.activo
));

drop policy if exists ps_despachos_select on public.despachos_sucursal;
create policy ps_despachos_select on public.despachos_sucursal for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.pedidos_sucursal p join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id
  where p.id=despachos_sucursal.pedido_id and us.user_id=(select auth.uid()) and us.activo
));

drop policy if exists ps_despacho_items_select on public.despachos_sucursal_items;
create policy ps_despacho_items_select on public.despachos_sucursal_items for select to authenticated
using ((select public.es_admin_drosalud()) or exists (
  select 1 from public.despachos_sucursal d join public.pedidos_sucursal p on p.id=d.pedido_id
  join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id
  where d.id=despachos_sucursal_items.despacho_id and us.user_id=(select auth.uid()) and us.activo
));
