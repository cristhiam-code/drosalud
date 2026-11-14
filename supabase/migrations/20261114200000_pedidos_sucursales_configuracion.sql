
create index if not exists despachos_sucursal_creado_por_idx on public.despachos_sucursal(creado_por);
create index if not exists despachos_sucursal_recibido_por_idx on public.despachos_sucursal(recibido_por);
create index if not exists despachos_sucursal_items_pedido_item_idx on public.despachos_sucursal_items(pedido_item_id);
create index if not exists despachos_sucursal_items_producto_idx on public.despachos_sucursal_items(producto_id);
create index if not exists inventario_sucursal_mov_creado_por_idx on public.inventario_sucursal_movimientos(creado_por);
create index if not exists pedidos_sucursal_bodega_destino_idx on public.pedidos_sucursal(bodega_destino_id);
create index if not exists pedidos_sucursal_creado_por_idx on public.pedidos_sucursal(creado_por);
create index if not exists pedidos_sucursal_autorizado_por_idx on public.pedidos_sucursal(autorizado_por);
create index if not exists pedidos_sucursal_rechazado_por_idx on public.pedidos_sucursal(rechazado_por);
create index if not exists pedidos_sucursal_items_producto_idx on public.pedidos_sucursal_items(producto_id);

create or replace function public.ps_admin_listar_configuracion()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_result jsonb;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede consultar la configuración de sucursales'; end if;
 select jsonb_build_object(
   'sucursales',coalesce((
     select jsonb_agg(jsonb_build_object(
       'id',s.id,'codigo',s.codigo,'nombre',s.nombre,'activa',s.activa,'es_central',s.es_central,
       'bodega_id',b.id,
       'dias_pedido',coalesce((select jsonb_agg(d.dia_semana order by d.dia_semana) from public.sucursal_dias_pedido d where d.sucursal_id=s.id and d.habilitado),'[]'::jsonb)
     ) order by s.es_central desc,s.nombre)
     from public.sucursales s left join public.bodegas b on b.sucursal_id=s.id and b.activa
   ),'[]'::jsonb),
   'usuarios',coalesce((
     select jsonb_agg(jsonb_build_object('user_id',u.user_id,'rol',u.rol,'activo',u.activo,
       'email',a.email,'sucursal_id',us.sucursal_id) order by u.rol,u.user_id)
     from public.usuarios_drosalud u
     left join auth.users a on a.id=u.user_id
     left join public.usuarios_sucursales us on us.user_id=u.user_id and us.activo
     where u.activo
   ),'[]'::jsonb)
 ) into v_result;
 return v_result;
end;$function$;

revoke all on function public.ps_admin_listar_configuracion() from public,anon;
grant execute on function public.ps_admin_listar_configuracion() to authenticated;
