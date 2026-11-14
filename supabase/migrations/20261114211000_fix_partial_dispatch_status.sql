
create or replace function public.ps_confirmar_recepcion_sucursal(p_despacho_id uuid,p_items jsonb,p_notas text,p_operacion_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
declare
 v_sucursal uuid; v_bodega uuid; v_pedido uuid; v_estado text; v_item jsonb; v_item_id uuid;
 v_qty integer; v_enviado integer; v_producto uuid; v_pedido_item uuid; v_total integer;
 v_autorizado integer; v_recibido integer; v_despachado integer; v_existing_op uuid;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 if p_operacion_id is null then raise exception 'Falta el identificador de operación de recepción'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_operacion_id::text,0));
 select p.id,p.sucursal_id,d.recepcion_operacion_id into v_pedido,v_sucursal,v_existing_op
 from public.despachos_sucursal d join public.pedidos_sucursal p on p.id=d.pedido_id
 where d.id=p_despacho_id for update;
 if v_pedido is null then raise exception 'El despacho no existe'; end if;
 if v_existing_op is not null then
   if v_existing_op=p_operacion_id then return; else raise exception 'Este despacho ya tiene una recepción confirmada'; end if;
 end if;
 if not exists(select 1 from public.usuarios_sucursales us where us.user_id=auth.uid() and us.sucursal_id=v_sucursal and us.activo) then raise exception 'No puedes confirmar la recepción de otra sucursal'; end if;
 select d.estado into v_estado from public.despachos_sucursal d where d.id=p_despacho_id for update;
 if v_estado<>'despachado' then raise exception 'Este despacho ya fue confirmado o no está disponible'; end if;
 select b.id into v_bodega from public.bodegas b where b.sucursal_id=v_sucursal and b.activa limit 1;
 if v_bodega is null then raise exception 'La sucursal no tiene una bodega activa'; end if;
 select count(*) into v_total from public.despachos_sucursal_items where despacho_id=p_despacho_id;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<>v_total or
   (select count(distinct x.despacho_item_id) from jsonb_to_recordset(p_items) as x(despacho_item_id uuid,unidades_recibidas integer))<>v_total then
   raise exception 'Debes confirmar todas las líneas del despacho una sola vez';
 end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_item_id:=(v_item->>'despacho_item_id')::uuid; v_qty:=(v_item->>'unidades_recibidas')::integer;
   select di.unidades_enviadas,di.producto_id,di.pedido_item_id into v_enviado,v_producto,v_pedido_item
   from public.despachos_sucursal_items di where di.id=v_item_id and di.despacho_id=p_despacho_id for update;
   if v_producto is null or v_qty is null or v_qty<0 or v_qty>v_enviado then raise exception 'La cantidad recibida no puede superar la cantidad enviada'; end if;
   update public.despachos_sucursal_items set unidades_recibidas=v_qty where id=v_item_id;
   update public.pedidos_sucursal_items set cantidad_recibida=cantidad_recibida+v_qty where id=v_pedido_item;
   if v_qty>0 then
     insert into public.inventario_sucursal_movimientos(bodega_id,producto_id,tipo,unidades_delta,referencia_id,operacion_id,notas,creado_por)
     values(v_bodega,v_producto,'recepcion_traslado',v_qty,v_item_id,p_operacion_id,
       coalesce(nullif(trim(p_notas),''),'Recepción de despacho de bodega central'),auth.uid());
   end if;
 end loop;
 update public.despachos_sucursal set
   estado=case when exists(select 1 from public.despachos_sucursal_items di where di.despacho_id=p_despacho_id and coalesce(di.unidades_recibidas,0)<di.unidades_enviadas) then 'parcial' else 'recibido' end,
   recibido_por=auth.uid(),recibido_en=now(),notas=coalesce(nullif(trim(p_notas),''),notas),recepcion_operacion_id=p_operacion_id
 where id=p_despacho_id;
 select coalesce(sum(i.cantidad_autorizada),0),coalesce(sum(i.cantidad_recibida),0),coalesce(sum(i.cantidad_despachada),0)
 into v_autorizado,v_recibido,v_despachado
 from public.pedidos_sucursal_items i where i.pedido_id=v_pedido;
 update public.pedidos_sucursal set
   estado=case
     when v_recibido>=v_autorizado and v_autorizado>0 then 'recibido'
     when v_despachado<v_autorizado then 'en_preparacion'
     when v_recibido>0 then 'parcial'
     when v_despachado>0 then 'despachado'
     else 'aprobado'
   end,
   actualizado_en=now()
 where id=v_pedido;
end;$function$;
