CREATE OR REPLACE FUNCTION public.registrar_venta_drosalud(p_venta jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_admin boolean:=public.es_admin_drosalud();
 v_rec public.recibos%rowtype; v_item jsonb; v_prod public.productos%rowtype;
 v_costo numeric; v_subtotal numeric:=0; v_ganancia numeric:=0;
 v_desc numeric:=greatest(coalesce((p_venta->>'descuento')::numeric,0),0);
 v_dom numeric:=greatest(coalesce((p_venta->>'domicilio')::numeric,0),0);
 v_mens numeric:=case when public.es_admin_drosalud() then greatest(coalesce((p_venta->>'costo_mensajero')::numeric,0),0) else 0 end;
 v_total numeric;
begin
 if not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La venta no tiene productos'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if coalesce((v_item->>'cantidad')::numeric,0)<=0
   or coalesce((v_item->>'cantidad')::numeric,0)<>trunc((v_item->>'cantidad')::numeric)
   or coalesce((v_item->>'precio_venta')::numeric,-1)<0 then raise exception 'Cantidad o precio inválido'; end if;
  v_costo:=0;
  if nullif(v_item->>'producto_id','') is not null then
   select * into v_prod from public.productos where id=(v_item->>'producto_id')::uuid;
   if not found then raise exception 'Producto inexistente'; end if;
   if v_prod.fraccionable then
    if coalesce(nullif(v_item->>'presentacion',''),'Unidad')='Caja' then
     if greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1))<>greatest(v_prod.unidades_por_caja,1)
       or (v_item->>'cantidad')::integer % greatest(v_prod.unidades_por_caja,1)<>0 then
      raise exception 'La cantidad de cajas no coincide con la presentación del producto';
     end if;
    elsif coalesce(nullif(v_item->>'presentacion',''),'Unidad')='Unidad' then
     if greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1))<>1
       or (v_item->>'cantidad')::integer % greatest(v_prod.unidades_por_venta,1)<>0 then
      raise exception 'Este producto se vende en múltiplos de % unidades sueltas',greatest(v_prod.unidades_por_venta,1);
     end if;
    else
     raise exception 'Presentación de venta no válida para este producto';
    end if;
   end if;
   v_costo:=case when v_prod.fraccionable then v_prod.precio_compra/greatest(v_prod.unidades_por_caja,1) else v_prod.precio_compra end;
  end if;
  v_subtotal:=v_subtotal+(v_item->>'precio_venta')::numeric*(v_item->>'cantidad')::numeric;
  v_ganancia:=v_ganancia+(((v_item->>'precio_venta')::numeric-v_costo)*(v_item->>'cantidad')::numeric);
 end loop;
 v_total:=greatest(0,v_subtotal-v_desc+v_dom);
 v_ganancia:=v_ganancia-v_desc+v_dom-v_mens;
 if nullif(p_venta->>'recibido','') is not null and (p_venta->>'recibido')::numeric<v_total then raise exception 'El efectivo recibido es menor al total'; end if;
 insert into public.recibos(cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,cliente_direccion,
  descuento,domicilio,costo_mensajero,forma_pago,recibido,vendedor,total,ganancia,creado_por)
 values(nullif(p_venta->>'cliente_id','')::uuid,nullif(p_venta->>'cliente_nombre',''),
  nullif(p_venta->>'cliente_cedula',''),nullif(p_venta->>'cliente_telefono',''),
  nullif(p_venta->>'cliente_direccion',''),v_desc,v_dom,v_mens,
  nullif(p_venta->>'forma_pago',''),nullif(p_venta->>'recibido','')::numeric,
  nullif(p_venta->>'vendedor',''),v_total,v_ganancia,v_user)
 returning * into v_rec;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_costo:=0;
  if nullif(v_item->>'producto_id','') is not null then
   select * into v_prod from public.productos where id=(v_item->>'producto_id')::uuid;
   if not found then raise exception 'Producto inexistente'; end if;
   v_costo:=case when v_prod.fraccionable then v_prod.precio_compra/greatest(v_prod.unidades_por_caja,1) else v_prod.precio_compra end;
  end if;
  insert into public.recibo_items(recibo_id,producto_id,nombre,cantidad,precio_compra,precio_venta,presentacion,unidades_por_presentacion)
  values(v_rec.id,nullif(v_item->>'producto_id','')::uuid,v_item->>'nombre',
   (v_item->>'cantidad')::integer,v_costo,(v_item->>'precio_venta')::numeric,
   coalesce(nullif(v_item->>'presentacion',''),'Unidad'),
   greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1)));
 end loop;
 if v_admin then return to_jsonb(v_rec); end if;
 return to_jsonb(v_rec)-'ganancia';
end $function$
;
