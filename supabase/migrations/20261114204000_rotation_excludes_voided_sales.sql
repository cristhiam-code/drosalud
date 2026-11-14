
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
   select m.producto_id,greatest(0,sum(-m.unidades_delta))::integer as unidades
   from public.inventario_sucursal_movimientos m
   where m.bodega_id=v_bodega and m.tipo in ('venta','anulacion')
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

create or replace function public.ps_crear_pedido_sucursal(p_tipo text,p_items jsonb,p_notas text default null)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
 v_uid uuid:=auth.uid(); v_sucursal uuid; v_bodega uuid; v_central boolean; v_pedido uuid;
 v_item jsonb; v_producto uuid; v_cantidad integer; v_stock integer; v_ventas integer; v_pendientes integer; v_dia integer; v_total integer;
begin
 if v_uid is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 if p_tipo not in ('sugerido','urgente') then raise exception 'Tipo de pedido inválido'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'El pedido debe contener al menos un producto'; end if;
 select us.sucursal_id,s.es_central,b.id into v_sucursal,v_central,v_bodega
 from public.usuarios_sucursales us join public.sucursales s on s.id=us.sucursal_id and s.activa
 join public.bodegas b on b.sucursal_id=s.id and b.activa where us.user_id=v_uid and us.activo limit 1;
 if v_bodega is null then raise exception 'No tienes una sucursal y bodega activa asignada'; end if;
 if v_central then raise exception 'La bodega central no puede generar pedidos para sí misma. Asigna este usuario a una sucursal.'; end if;
 if p_tipo='sugerido' then
   v_dia:=extract(dow from (now() at time zone 'America/Bogota'))::integer;
   if not exists(select 1 from public.sucursal_dias_pedido d where d.sucursal_id=v_sucursal and d.dia_semana=v_dia and d.habilitado) then
     raise exception 'HOY NO ES TU DIA DE PEDIDO. PODRÁ realizarlo cuando el sistema le Habilite esta Opción';
   end if;
 end if;
 select count(*) into v_total from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad_solicitada integer);
 if v_total<>jsonb_array_length(p_items) or (select count(distinct x.producto_id) from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad_solicitada integer))<>v_total then raise exception 'El pedido contiene productos repetidos o identificadores inválidos'; end if;
 insert into public.pedidos_sucursal(sucursal_id,bodega_destino_id,tipo,estado,creado_por,notas)
 values(v_sucursal,v_bodega,p_tipo,'pendiente_autorizacion',v_uid,nullif(trim(p_notas),'')) returning id into v_pedido;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_producto:=nullif(v_item->>'producto_id','')::uuid; v_cantidad:=(v_item->>'cantidad_solicitada')::integer;
   if v_producto is null or v_cantidad is null or v_cantidad<=0 then raise exception 'Cada producto debe tener una cantidad entera mayor que cero'; end if;
   if not exists(select 1 from public.productos p where p.id=v_producto) then raise exception 'Uno de los productos ya no existe en el catálogo'; end if;
   select coalesce(s.saldo_unidades,0) into v_stock from (select 1) x left join public.inventario_sucursal_saldos s on s.bodega_id=v_bodega and s.producto_id=v_producto;
   if p_tipo='urgente' and coalesce(v_stock,0)>=0 then raise exception 'El pedido urgente solo permite productos con inventario negativo. Producto: %',v_producto; end if;
   select greatest(0,coalesce(sum(-m.unidades_delta),0))::integer into v_ventas
   from public.inventario_sucursal_movimientos m where m.bodega_id=v_bodega and m.producto_id=v_producto
     and m.tipo in ('venta','anulacion') and m.creado_en>=now()-interval '7 days';
   select coalesce(sum(greatest(0,coalesce(i.cantidad_autorizada,i.cantidad_solicitada)-i.cantidad_recibida)),0)::integer into v_pendientes
   from public.pedidos_sucursal_items i join public.pedidos_sucursal p on p.id=i.pedido_id
   where p.sucursal_id=v_sucursal and i.producto_id=v_producto and p.estado not in ('rechazado','cancelado','recibido');
   insert into public.pedidos_sucursal_items(pedido_id,producto_id,producto_nombre,cantidad_solicitada,ventas_7_dias,saldo_al_solicitar,pendientes_al_solicitar)
   select v_pedido,p.id,p.nombre,v_cantidad,coalesce(v_ventas,0),coalesce(v_stock,0),coalesce(v_pendientes,0) from public.productos p where p.id=v_producto;
 end loop;
 return v_pedido;
end;$function$;
