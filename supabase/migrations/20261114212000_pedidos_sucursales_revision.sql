
alter table public.pedidos_sucursal drop constraint pedidos_sucursal_estado_check;
alter table public.pedidos_sucursal add constraint pedidos_sucursal_estado_check
check (estado in ('pendiente_autorizacion','en_revision','aprobado','rechazado','en_preparacion','despachado','parcial','recibido','cancelado'));

create or replace function public.ps_iniciar_revision_pedido_sucursal(p_pedido_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede iniciar la revisión'; end if;
 update public.pedidos_sucursal set estado='en_revision',actualizado_en=now()
 where id=p_pedido_id and estado='pendiente_autorizacion';
 if not found and exists(select 1 from public.pedidos_sucursal where id=p_pedido_id and estado='en_revision') then return; end if;
 if not found then raise exception 'El pedido no existe o ya fue procesado'; end if;
end;$function$;

create or replace function public.ps_autorizar_pedido_sucursal(p_pedido_id uuid,p_items jsonb)
returns void language plpgsql security definer set search_path = '' as $function$
declare v_item jsonb; v_item_id uuid; v_qty integer; v_total integer; v_done integer:=0;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede autorizar pedidos'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Debes indicar las cantidades que vas a autorizar'; end if;
 perform 1 from public.pedidos_sucursal where id=p_pedido_id and estado='en_revision' for update;
 if not found then raise exception 'El pedido no está en revisión'; end if;
 select count(*) into v_total from public.pedidos_sucursal_items where pedido_id=p_pedido_id;
 if jsonb_array_length(p_items)<>v_total or
   (select count(distinct x.pedido_item_id) from jsonb_to_recordset(p_items) as x(pedido_item_id uuid,cantidad_autorizada integer))<>v_total then
   raise exception 'Debes revisar una sola vez todas las líneas del pedido';
 end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_item_id:=(v_item->>'pedido_item_id')::uuid; v_qty:=(v_item->>'cantidad_autorizada')::integer;
   if v_qty is null or v_qty<0 then raise exception 'La cantidad autorizada no puede ser negativa'; end if;
   update public.pedidos_sucursal_items set cantidad_autorizada=v_qty
   where id=v_item_id and pedido_id=p_pedido_id and v_qty<=cantidad_solicitada;
   if not found then raise exception 'Una cantidad supera lo solicitado o la línea no pertenece al pedido'; end if;
   v_done:=v_done+1;
 end loop;
 if v_done<>v_total or not exists(select 1 from public.pedidos_sucursal_items where pedido_id=p_pedido_id and cantidad_autorizada>0) then
   raise exception 'Debes autorizar al menos una unidad';
 end if;
 update public.pedidos_sucursal set estado='aprobado',autorizado_por=auth.uid(),autorizado_en=now(),actualizado_en=now() where id=p_pedido_id;
end;$function$;

create or replace function public.ps_rechazar_pedido_sucursal(p_pedido_id uuid,p_motivo text)
returns void language plpgsql security definer set search_path = '' as $function$
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede rechazar pedidos'; end if;
 if nullif(trim(p_motivo),'') is null then raise exception 'Debes indicar el motivo del rechazo'; end if;
 update public.pedidos_sucursal set estado='rechazado',rechazado_por=auth.uid(),rechazado_en=now(),motivo_rechazo=left(trim(p_motivo),500),actualizado_en=now()
 where id=p_pedido_id and estado='en_revision';
 if not found then raise exception 'El pedido no está en revisión'; end if;
end;$function$;

create or replace function public.ps_listar_pedidos_sucursal(p_filtro text default 'historial')
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_sucursal uuid; v_admin boolean; v_result jsonb;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 v_admin:=public.es_admin_drosalud();
 select sucursal_id into v_sucursal from public.usuarios_sucursales where user_id=auth.uid() and activo;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'numero',p.numero,'sucursal_id',p.sucursal_id,'sucursal_nombre',s.nombre,'tipo',p.tipo,'estado',p.estado,'creado_en',p.creado_en,'notas',p.notas,'motivo_rechazo',p.motivo_rechazo,
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'producto_id',i.producto_id,'producto_nombre',i.producto_nombre,'cantidad_solicitada',i.cantidad_solicitada,'cantidad_autorizada',i.cantidad_autorizada,'cantidad_despachada',i.cantidad_despachada,'cantidad_recibida',i.cantidad_recibida) order by i.creado_en) from public.pedidos_sucursal_items i where i.pedido_id=p.id),'[]'::jsonb),
  'despachos',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'numero',d.numero,'estado',d.estado,'creado_en',d.creado_en,'items',coalesce((select jsonb_agg(jsonb_build_object('id',di.id,'producto_id',di.producto_id,'producto_nombre',di.producto_nombre,'unidades_enviadas',di.unidades_enviadas,'unidades_recibidas',di.unidades_recibidas) order by di.creado_en) from public.despachos_sucursal_items di where di.despacho_id=d.id),'[]'::jsonb)) order by d.creado_en) from public.despachos_sucursal d where d.pedido_id=p.id),'[]'::jsonb)
 ) order by p.creado_en desc),'[]'::jsonb) into v_result
 from public.pedidos_sucursal p join public.sucursales s on s.id=p.sucursal_id
 where (v_admin or p.sucursal_id=v_sucursal)
 and (coalesce(p_filtro,'historial')<>'autorizados'
   or (v_admin and p.estado in ('pendiente_autorizacion','en_revision','aprobado','en_preparacion'))
   or (not v_admin and p.estado in ('aprobado','en_preparacion','despachado','parcial')));
 return v_result;
end;$function$;

revoke all on function public.ps_iniciar_revision_pedido_sucursal(uuid) from public,anon;
grant execute on function public.ps_iniciar_revision_pedido_sucursal(uuid) to authenticated;
