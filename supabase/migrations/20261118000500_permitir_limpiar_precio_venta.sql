drop function if exists public.actualizar_precios_drosalud_con_motivo(uuid,numeric,numeric,text);

create function public.actualizar_precios_drosalud_con_motivo(
  p_producto_id uuid,
  p_precio_compra numeric default null,
  p_precio_venta numeric default null,
  p_motivo text default null,
  p_limpiar_precio_venta boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prod public.productos%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario Drosalud no autorizado';
  end if;
  if p_precio_compra is null and p_precio_venta is null and not p_limpiar_precio_venta then
    raise exception 'Indica al menos un costo o precio';
  end if;
  if (p_precio_compra is not null and (p_precio_compra < 0 or p_precio_compra >= 1000000000))
     or (p_precio_venta is not null and (p_precio_venta < 0 or p_precio_venta >= 1000000000)) then
    raise exception 'Precio fuera de rango';
  end if;
  if nullif(pg_catalog.btrim(p_motivo),'') is null or pg_catalog.length(pg_catalog.btrim(p_motivo)) < 4 then
    raise exception 'Explica brevemente por qué cambió el costo o el precio';
  end if;
  perform pg_catalog.set_config('app.precio_motivo',pg_catalog.left(pg_catalog.btrim(p_motivo),250),true);
  select * into v_prod from public.productos where id=p_producto_id for update;
  if not found then raise exception 'Producto no encontrado'; end if;
  update public.productos
    set precio_compra=coalesce(p_precio_compra,precio_compra),
        precio_venta=case when p_limpiar_precio_venta then null else coalesce(p_precio_venta,precio_venta) end,
        actualizado_en=pg_catalog.now()
    where id=p_producto_id returning * into v_prod;
  return pg_catalog.jsonb_build_object(
    'id',v_prod.id,'precio_compra',v_prod.precio_compra,'precio_venta',v_prod.precio_venta,
    'margen_negativo',coalesce(v_prod.precio_venta,0)<v_prod.precio_compra
  );
end
$function$;

revoke all on function public.actualizar_precios_drosalud_con_motivo(uuid,numeric,numeric,text,boolean) from public,anon;
grant execute on function public.actualizar_precios_drosalud_con_motivo(uuid,numeric,numeric,text,boolean) to authenticated;
