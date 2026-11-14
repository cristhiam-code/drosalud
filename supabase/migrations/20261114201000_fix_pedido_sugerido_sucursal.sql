
create or replace function public.ps_obtener_pedido_sugerido()
returns table(producto_id uuid,codigo text,producto_nombre text,laboratorio text,ventas_7_dias integer,saldo_unidades integer,pendientes_unidades integer,cantidad_sugerida integer)
language plpgsql stable security definer set search_path = '' as $function$
declare v_sucursal uuid; v_bodega uuid;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 select us.sucursal_id,b.id into v_sucursal,v_bodega
 from public.usuarios_sucursales us join public.bodegas b on b.sucursal_id=us.sucursal_id and b.activa
 where us.user_id=auth.uid() and us.activo limit 1;
 if v_bodega is null then raise exception 'No hay bodega asignada a esta sucursal'; end if;
 return query
 with ventas as (
   select m.producto_id,sum(-m.unidades_delta)::integer as unidades
   from public.inventario_sucursal_movimientos m
   where m.bodega_id=v_bodega and m.tipo='venta' and m.unidades_delta<0
     and m.creado_en>=now()-interval '7 days'
   group by m.producto_id
 ), pendientes as (
   select i.producto_id,sum(greatest(0,coalesce(i.cantidad_autorizada,i.cantidad_solicitada)-i.cantidad_recibida))::integer as unidades
   from public.pedidos_sucursal_items i join public.pedidos_sucursal p on p.id=i.pedido_id
   where p.sucursal_id=v_sucursal and p.estado not in ('rechazado','cancelado','recibido')
   group by i.producto_id
 ), saldos as (
   select ss.producto_id,ss.saldo_unidades from public.inventario_sucursal_saldos ss where ss.bodega_id=v_bodega
 )
 select pr.id,pr.codigo,pr.nombre,pr.laboratorio,coalesce(v.unidades,0),coalesce(s.saldo_unidades,0),coalesce(pe.unidades,0),
   greatest(0,ceil(coalesce(v.unidades,0)-coalesce(s.saldo_unidades,0)-coalesce(pe.unidades,0)))::integer
 from public.productos pr left join ventas v on v.producto_id=pr.id
 left join saldos s on s.producto_id=pr.id left join pendientes pe on pe.producto_id=pr.id
 where coalesce(v.unidades,0)>0 order by pr.laboratorio nulls last,pr.nombre;
end;$function$;
