
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
 if v_total<>jsonb_array_length(p_items) or (select count(distinct x.producto_id) from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad_solicitada integer))<>v_total then
   raise exception 'El pedido contiene productos repetidos o identificadores inválidos';
 end if;
 insert into public.pedidos_sucursal(sucursal_id,bodega_destino_id,tipo,estado,creado_por,notas)
 values(v_sucursal,v_bodega,p_tipo,'pendiente_autorizacion',v_uid,nullif(trim(p_notas),'')) returning id into v_pedido;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_producto:=nullif(v_item->>'producto_id','')::uuid; v_cantidad:=(v_item->>'cantidad_solicitada')::integer;
   if v_producto is null or v_cantidad is null or v_cantidad<=0 then raise exception 'Cada producto debe tener una cantidad entera mayor que cero'; end if;
   if not exists(select 1 from public.productos p where p.id=v_producto) then raise exception 'Uno de los productos ya no existe en el catálogo'; end if;
   select coalesce(s.saldo_unidades,0) into v_stock from (select 1) x left join public.inventario_sucursal_saldos s on s.bodega_id=v_bodega and s.producto_id=v_producto;
   if p_tipo='urgente' and coalesce(v_stock,0)>=0 then raise exception 'El pedido urgente solo permite productos con inventario negativo. Producto: %',v_producto; end if;
   select coalesce(sum(-m.unidades_delta),0)::integer into v_ventas from public.inventario_sucursal_movimientos m
   where m.bodega_id=v_bodega and m.producto_id=v_producto and m.tipo='venta' and m.unidades_delta<0 and m.creado_en>=now()-interval '7 days';
   select coalesce(sum(greatest(0,coalesce(i.cantidad_autorizada,i.cantidad_solicitada)-i.cantidad_recibida)),0)::integer into v_pendientes
   from public.pedidos_sucursal_items i join public.pedidos_sucursal p on p.id=i.pedido_id
   where p.sucursal_id=v_sucursal and i.producto_id=v_producto and p.estado not in ('rechazado','cancelado','recibido');
   insert into public.pedidos_sucursal_items(pedido_id,producto_id,producto_nombre,cantidad_solicitada,ventas_7_dias,saldo_al_solicitar,pendientes_al_solicitar)
   select v_pedido,p.id,p.nombre,v_cantidad,coalesce(v_ventas,0),coalesce(v_stock,0),coalesce(v_pendientes,0) from public.productos p where p.id=v_producto;
 end loop;
 return v_pedido;
end;$function$;

create or replace function public.ps_autorizar_pedido_sucursal(p_pedido_id uuid,p_items jsonb)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_item jsonb; v_item_id uuid; v_qty integer; v_total integer; v_done integer:=0;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede autorizar pedidos'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Debes indicar las cantidades que vas a autorizar'; end if;
 perform 1 from public.pedidos_sucursal where id=p_pedido_id and estado='pendiente_autorizacion' for update;
 if not found then raise exception 'El pedido no existe o ya fue revisado'; end if;
 select count(*) into v_total from public.pedidos_sucursal_items where pedido_id=p_pedido_id;
 if jsonb_array_length(p_items)<>v_total or (select count(distinct x.pedido_item_id) from jsonb_to_recordset(p_items) as x(pedido_item_id uuid,cantidad_autorizada integer))<>v_total then
   raise exception 'Debes revisar una sola vez todas las líneas del pedido';
 end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_item_id:=(v_item->>'pedido_item_id')::uuid; v_qty:=(v_item->>'cantidad_autorizada')::integer;
   if v_qty is null or v_qty<0 then raise exception 'La cantidad autorizada no puede ser negativa'; end if;
   update public.pedidos_sucursal_items set cantidad_autorizada=v_qty where id=v_item_id and pedido_id=p_pedido_id and v_qty<=cantidad_solicitada;
   if not found then raise exception 'Una cantidad supera lo solicitado o la línea no pertenece al pedido'; end if;
   v_done:=v_done+1;
 end loop;
 if v_done<>v_total or not exists(select 1 from public.pedidos_sucursal_items where pedido_id=p_pedido_id and cantidad_autorizada>0) then raise exception 'Debes autorizar al menos una unidad'; end if;
 update public.pedidos_sucursal set estado='aprobado',autorizado_por=auth.uid(),autorizado_en=now(),actualizado_en=now() where id=p_pedido_id;
end;$function$;

create or replace function public.ps_rechazar_pedido_sucursal(p_pedido_id uuid,p_motivo text)
returns void language plpgsql security definer set search_path = '' as $function$
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede rechazar pedidos'; end if;
 if nullif(trim(p_motivo),'') is null then raise exception 'Debes indicar el motivo del rechazo'; end if;
 update public.pedidos_sucursal set estado='rechazado',rechazado_por=auth.uid(),rechazado_en=now(),motivo_rechazo=left(trim(p_motivo),500),actualizado_en=now()
 where id=p_pedido_id and estado='pendiente_autorizacion';
 if not found then raise exception 'El pedido no existe o ya fue revisado'; end if;
end;$function$;

create or replace function public.ps_registrar_despacho_sucursal(p_pedido_id uuid,p_items jsonb,p_notas text default null)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_despacho uuid; v_item jsonb; v_item_id uuid; v_producto uuid; v_qty integer; v_restante integer; v_stock integer; v_total integer; v_done integer:=0; v_central uuid; v_nombre text; v_dispatch_item uuid;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede registrar despachos'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Indica al menos una línea para despachar'; end if;
 perform 1 from public.pedidos_sucursal where id=p_pedido_id and estado in ('aprobado','en_preparacion') for update;
 if not found then raise exception 'El pedido no está autorizado o no puede despacharse'; end if;
 select id into v_central from public.bodegas where es_central=true and activa=true limit 1;
 if v_central is null then raise exception 'No existe una bodega central activa'; end if;
 select count(*) into v_total from jsonb_to_recordset(p_items) as x(pedido_item_id uuid,unidades_despachadas integer);
 if v_total<>jsonb_array_length(p_items) or (select count(distinct x.pedido_item_id) from jsonb_to_recordset(p_items) as x(pedido_item_id uuid,unidades_despachadas integer))<>v_total then raise exception 'Hay líneas repetidas o identificadores inválidos'; end if;
 insert into public.despachos_sucursal(pedido_id,estado,creado_por,notas) values(p_pedido_id,'despachado',auth.uid(),nullif(trim(p_notas),'')) returning id into v_despacho;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_item_id:=(v_item->>'pedido_item_id')::uuid; v_qty:=(v_item->>'unidades_despachadas')::integer;
   if v_qty is null or v_qty<=0 then raise exception 'Las unidades despachadas deben ser mayores que cero'; end if;
   select i.producto_id,i.producto_nombre,coalesce(i.cantidad_autorizada,0)-i.cantidad_despachada into v_producto,v_nombre,v_restante
   from public.pedidos_sucursal_items i where i.id=v_item_id and i.pedido_id=p_pedido_id for update;
   if v_producto is null or v_qty>v_restante then raise exception 'La cantidad despachada supera las unidades autorizadas pendientes'; end if;
   select coalesce(s.saldo_unidades,0) into v_stock from (select 1) x left join public.inventario_sucursal_saldos s on s.bodega_id=v_central and s.producto_id=v_producto;
   if coalesce(v_stock,0)<v_qty then raise exception 'Existencia insuficiente en bodega central para %: disponible %, solicitado %',v_nombre,coalesce(v_stock,0),v_qty; end if;
   insert into public.despachos_sucursal_items(despacho_id,pedido_item_id,producto_id,producto_nombre,unidades_enviadas)
   values(v_despacho,v_item_id,v_producto,v_nombre,v_qty) returning id into v_dispatch_item;
   update public.pedidos_sucursal_items set cantidad_despachada=cantidad_despachada+v_qty where id=v_item_id;
   insert into public.inventario_sucursal_movimientos(bodega_id,producto_id,tipo,unidades_delta,referencia_id,operacion_id,notas,creado_por)
   values(v_central,v_producto,'despacho_salida',-v_qty,v_dispatch_item,v_despacho,'Salida por despacho de pedido de sucursal',auth.uid());
   v_done:=v_done+1;
 end loop;
 if v_done<>v_total then raise exception 'No se pudieron registrar todas las líneas del despacho'; end if;
 update public.pedidos_sucursal p set estado=case when not exists(select 1 from public.pedidos_sucursal_items i where i.pedido_id=p.id and coalesce(i.cantidad_autorizada,0)>i.cantidad_despachada) then 'despachado' else 'en_preparacion' end,actualizado_en=now()
 where p.id=p_pedido_id;
 return v_despacho;
end;$function$;

create or replace function public.ps_confirmar_recepcion_sucursal(p_despacho_id uuid,p_items jsonb,p_notas text default null)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_sucursal uuid; v_bodega uuid; v_pedido uuid; v_estado text; v_item jsonb; v_item_id uuid; v_qty integer; v_enviado integer; v_producto uuid; v_pedido_item uuid; v_total integer; v_autorizado integer; v_recibido integer;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 select p.id,p.sucursal_id into v_pedido,v_sucursal from public.despachos_sucursal d join public.pedidos_sucursal p on p.id=d.pedido_id where d.id=p_despacho_id for update;
 if v_pedido is null then raise exception 'El despacho no existe'; end if;
 if not exists(select 1 from public.usuarios_sucursales us where us.user_id=auth.uid() and us.sucursal_id=v_sucursal and us.activo) then raise exception 'No puedes confirmar la recepción de otra sucursal'; end if;
 select estado into v_estado from public.despachos_sucursal where id=p_despacho_id for update;
 if v_estado<>'despachado' then raise exception 'Este despacho ya fue confirmado o no está disponible'; end if;
 select id into v_bodega from public.bodegas where sucursal_id=v_sucursal and activa limit 1;
 if v_bodega is null then raise exception 'La sucursal no tiene una bodega activa'; end if;
 select count(*) into v_total from public.despachos_sucursal_items where despacho_id=p_despacho_id;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<>v_total or (select count(distinct x.despacho_item_id) from jsonb_to_recordset(p_items) as x(despacho_item_id uuid,unidades_recibidas integer))<>v_total then
   raise exception 'Debes confirmar todas las líneas del despacho una sola vez';
 end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_item_id:=(v_item->>'despacho_item_id')::uuid; v_qty:=(v_item->>'unidades_recibidas')::integer;
   select unidades_enviadas,producto_id,pedido_item_id into v_enviado,v_producto,v_pedido_item from public.despachos_sucursal_items where id=v_item_id and despacho_id=p_despacho_id for update;
   if v_producto is null or v_qty is null or v_qty<0 or v_qty>v_enviado then raise exception 'La cantidad recibida no puede superar la cantidad enviada'; end if;
   update public.despachos_sucursal_items set unidades_recibidas=v_qty where id=v_item_id;
   update public.pedidos_sucursal_items set cantidad_recibida=cantidad_recibida+v_qty where id=v_pedido_item;
   if v_qty>0 then
     insert into public.inventario_sucursal_movimientos(bodega_id,producto_id,tipo,unidades_delta,referencia_id,operacion_id,notas,creado_por)
     values(v_bodega,v_producto,'recepcion_traslado',v_qty,v_item_id,p_despacho,coalesce(nullif(trim(p_notas),''),'Recepción de despacho de bodega central'),auth.uid());
   end if;
 end loop;
 update public.despachos_sucursal set estado=case when exists(select 1 from public.despachos_sucursal_items di where di.despacho_id=p_despacho_id and coalesce(di.unidades_recibidas,0)<di.unidades_enviadas) then 'parcial' else 'recibido' end,recibido_por=auth.uid(),recibido_en=now(),notas=coalesce(nullif(trim(p_notas),''),notas) where id=p_despacho_id;
 select coalesce(sum(cantidad_autorizada),0),coalesce(sum(cantidad_recibida),0) into v_autorizado,v_recibido from public.pedidos_sucursal_items where pedido_id=v_pedido;
 update public.pedidos_sucursal set estado=case when v_recibido>=v_autorizado and v_autorizado>0 then 'recibido' when v_recibido>0 then 'parcial' when exists(select 1 from public.pedidos_sucursal_items where pedido_id=v_pedido and cantidad_despachada>0) then 'despachado' else 'aprobado' end,actualizado_en=now() where id=v_pedido;
end;$function$;

revoke all on function public.ps_crear_pedido_sucursal(text,jsonb,text),public.ps_autorizar_pedido_sucursal(uuid,jsonb),
 public.ps_rechazar_pedido_sucursal(uuid,text),public.ps_registrar_despacho_sucursal(uuid,jsonb,text),
 public.ps_confirmar_recepcion_sucursal(uuid,jsonb,text) from public,anon;
grant execute on function public.ps_crear_pedido_sucursal(text,jsonb,text),public.ps_autorizar_pedido_sucursal(uuid,jsonb),
 public.ps_rechazar_pedido_sucursal(uuid,text),public.ps_registrar_despacho_sucursal(uuid,jsonb,text),
 public.ps_confirmar_recepcion_sucursal(uuid,jsonb,text) to authenticated;
