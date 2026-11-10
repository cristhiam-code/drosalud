-- Drosalud · Permitir al equipo activo actualizar costo y precio de catálogo
-- La escritura directa en productos sigue restringida por RLS al administrador.
-- Los usuarios activos solo pueden cambiar los dos campos de precio mediante esta RPC auditada.
begin;

create or replace function public.proteger_costo_productos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.precio_compra is distinct from old.precio_compra
     and not public.es_usuario_drosalud() then
    raise exception 'Usuario Drosalud no autorizado para modificar el costo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.actualizar_precios_drosalud(
  p_producto_id uuid,
  p_precio_compra numeric default null,
  p_precio_venta numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prod public.productos%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then
    raise exception 'Usuario Drosalud no autorizado';
  end if;

  if p_precio_compra is null and p_precio_venta is null then
    raise exception 'Indica al menos un precio';
  end if;

  if (p_precio_compra is not null and (p_precio_compra < 0 or p_precio_compra >= 1000000000))
     or (p_precio_venta is not null and (p_precio_venta < 0 or p_precio_venta >= 1000000000)) then
    raise exception 'Precio fuera de rango';
  end if;

  select * into v_prod
  from public.productos
  where id = p_producto_id
  for update;

  if not found then
    raise exception 'Producto no encontrado';
  end if;

  update public.productos
     set precio_compra = coalesce(p_precio_compra, precio_compra),
         precio_venta = coalesce(p_precio_venta, precio_venta),
         actualizado_en = now()
   where id = p_producto_id
   returning * into v_prod;

  return jsonb_build_object(
    'id', v_prod.id,
    'precio_compra', v_prod.precio_compra,
    'precio_venta', v_prod.precio_venta,
    'margen_negativo', coalesce(v_prod.precio_venta, 0) < v_prod.precio_compra
  );
end;
$$;

revoke all on function public.actualizar_precios_drosalud(uuid,numeric,numeric) from public, anon, authenticated;
grant execute on function public.actualizar_precios_drosalud(uuid,numeric,numeric) to authenticated;
-- El trigger debe existir también al instalar la migración desde cero.
drop trigger if exists trg_proteger_costo_productos on public.productos;
create trigger trg_proteger_costo_productos
before update of precio_compra on public.productos
for each row
execute function public.proteger_costo_productos();

revoke all on function public.proteger_costo_productos() from public, anon, authenticated;

commit;
