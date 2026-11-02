-- Drosalud · migración propuesta de roles y seguridad
-- Revisada contra el esquema inspeccionado. NO ejecutar en producción sin respaldo y pruebas.
begin;

create table if not exists public.usuarios_drosalud (
  user_id uuid primary key references auth.users(id) on delete cascade,
  rol text not null check (rol in ('admin','vendedor')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table public.usuarios_drosalud enable row level security;

create or replace function public.es_usuario_drosalud()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios_drosalud u
    where u.user_id = auth.uid() and u.activo
  );
$$;

create or replace function public.es_admin_drosalud()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios_drosalud u
    where u.user_id = auth.uid() and u.activo and u.rol = 'admin'
  );
$$;

revoke all on function public.es_usuario_drosalud() from public, anon;
revoke all on function public.es_admin_drosalud() from public, anon;
grant execute on function public.es_usuario_drosalud(), public.es_admin_drosalud() to authenticated;

-- Evitar que políticas permisivas anteriores se sumen a las nuevas.
do $$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public' and tablename = any(array[
      'usuarios_drosalud','productos','clientes','recibos','recibo_items',
      'ajustes','historial_precios','compras_pendientes','proveedores',
      'cotizaciones_venta','cotizacion_venta_items','cotizaciones_proveedor'
    ])
  loop
    execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
  end loop;
end $$;

insert into public.usuarios_drosalud(user_id,rol,activo)
select id,'admin',true from auth.users
where lower(email)=lower('boterocristhiam@gmail.com')
on conflict(user_id) do update set rol='admin',activo=true;

create policy "usuario consulta su propio perfil"
on public.usuarios_drosalud for select to authenticated
using (user_id=auth.uid() or public.es_admin_drosalud());

alter table public.recibos add column if not exists creado_por uuid references auth.users(id);
alter table public.recibos alter column creado_por set default auth.uid();

-- RLS: catálogo y clientes compartidos; solo admin modifica el catálogo directamente.
create policy "personal activo consulta productos"
on public.productos for select to authenticated using (public.es_usuario_drosalud());
create policy "admin administra productos"
on public.productos for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

create policy "personal activo consulta clientes"
on public.clientes for select to authenticated using (public.es_usuario_drosalud());
create policy "personal activo crea clientes"
on public.clientes for insert to authenticated with check (public.es_usuario_drosalud());
create policy "personal activo actualiza clientes"
on public.clientes for update to authenticated
using (public.es_usuario_drosalud()) with check (public.es_usuario_drosalud());
create policy "admin elimina clientes"
on public.clientes for delete to authenticated using (public.es_admin_drosalud());

-- Recibos: cada vendedor consulta solo los suyos; histórico antiguo queda para admin.
create policy "personal consulta recibos propios"
on public.recibos for select to authenticated
using (public.es_usuario_drosalud() and (public.es_admin_drosalud() or creado_por=auth.uid()));
create policy "admin modifica recibos"
on public.recibos for update to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());
create policy "admin elimina recibos"
on public.recibos for delete to authenticated using (public.es_admin_drosalud());

create policy "personal consulta items permitidos"
on public.recibo_items for select to authenticated
using (exists(select 1 from public.recibos r where r.id=recibo_items.recibo_id
  and public.es_usuario_drosalud() and (public.es_admin_drosalud() or r.creado_por=auth.uid())));
create policy "admin administra items recibo"
on public.recibo_items for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

create policy "admin consulta ajustes"
on public.ajustes for select to authenticated using (public.es_admin_drosalud());
create policy "admin administra ajustes"
on public.ajustes for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

create policy "admin consulta historial costos"
on public.historial_precios for select to authenticated using (public.es_admin_drosalud());
create policy "admin administra historial costos"
on public.historial_precios for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

create policy "admin gestiona compras"
on public.compras_pendientes for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());
create policy "admin gestiona proveedores"
on public.proveedores for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());
create policy "admin gestiona cotizaciones proveedor"
on public.cotizaciones_proveedor for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

create policy "personal consulta sus cotizaciones"
on public.cotizaciones_venta for select to authenticated
using (public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid()));
create policy "personal crea sus cotizaciones"
on public.cotizaciones_venta for insert to authenticated
with check (public.es_usuario_drosalud() and owner_id=auth.uid());
create policy "personal actualiza sus cotizaciones"
on public.cotizaciones_venta for update to authenticated
using (public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid()))
with check (public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid()));
create policy "personal elimina sus cotizaciones"
on public.cotizaciones_venta for delete to authenticated
using (public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid()));

create policy "personal consulta items cotizacion"
on public.cotizacion_venta_items for select to authenticated
using (exists(select 1 from public.cotizaciones_venta c where c.id=cotizacion_venta_items.cotizacion_id
 and public.es_usuario_drosalud() and (public.es_admin_drosalud() or c.owner_id=auth.uid())));
create policy "admin administra items cotizacion"
on public.cotizacion_venta_items for all to authenticated
using (public.es_admin_drosalud()) with check (public.es_admin_drosalud());

-- Las vistas exponen una única interfaz: el vendedor recibe NULL en columnas sensibles.
create or replace view public.productos_app as
select id,codigo,nombre,laboratorio,
  case when public.es_admin_drosalud() then precio_compra else null end as precio_compra,
  actualizado_en,precio_venta,fraccionable,unidades_por_caja,unidades_por_venta
from public.productos
where public.es_usuario_drosalud();

create or replace view public.recibos_app as
select id,numero,cliente_id,cliente_nombre,total,
  case when public.es_admin_drosalud() then ganancia else null end as ganancia,
  creado_en,descuento,domicilio,forma_pago,cliente_cedula,cliente_telefono,
  cliente_direccion,recibido,anulado,anulado_en,motivo_anulacion,vendedor,
  costo_mensajero,creado_por
from public.recibos
where public.es_usuario_drosalud() and (public.es_admin_drosalud() or creado_por=auth.uid());

create or replace view public.recibo_items_app as
select i.id,i.recibo_id,i.producto_id,i.nombre,i.cantidad,
  case when public.es_admin_drosalud() then i.precio_compra else null end as precio_compra,
  i.precio_venta,
  case when public.es_admin_drosalud() then i.costo_real_unitario else null end as costo_real_unitario,
  i.presentacion,i.unidades_por_presentacion
from public.recibo_items i
join public.recibos r on r.id=i.recibo_id
where public.es_usuario_drosalud() and (public.es_admin_drosalud() or r.creado_por=auth.uid());

create or replace view public.cotizaciones_venta_app as
select id,numero,owner_id,cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,
 cliente_direccion,vendedor,descuento,domicilio,subtotal,total,estado,valida_hasta,
 recibo_id,creado_en
from public.cotizaciones_venta
where public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid());

create or replace view public.cotizacion_venta_items_app as
select id,cotizacion_id,producto_id,nombre,cantidad,
 case when public.es_admin_drosalud() then precio_compra else null end as precio_compra,
 precio_venta,presentacion,unidades_por_presentacion
from public.cotizacion_venta_items i
where exists(select 1 from public.cotizaciones_venta c where c.id=i.cotizacion_id
 and public.es_usuario_drosalud() and (public.es_admin_drosalud() or c.owner_id=auth.uid()));

revoke all on public.usuarios_drosalud,public.productos,public.recibos,public.recibo_items,
 public.cotizacion_venta_items,public.ajustes,public.historial_precios,
 public.compras_pendientes,public.proveedores,public.cotizaciones_proveedor
from anon;
revoke all on public.productos,public.recibos,public.recibo_items,public.cotizacion_venta_items from authenticated;
grant select on public.usuarios_drosalud,public.productos_app,public.recibos_app,
 public.recibo_items_app,public.cotizaciones_venta_app,public.cotizacion_venta_items_app to authenticated;
grant select,insert,update on public.clientes to authenticated;
grant usage on schema public to authenticated;

-- El admin conserva operaciones de mantenimiento en tablas no expuestas al vendedor.
grant insert,update,delete on public.productos,public.recibos,public.recibo_items,
 public.cotizacion_venta_items,public.ajustes,public.historial_precios,
 public.compras_pendientes,public.proveedores,public.cotizaciones_proveedor to authenticated;

-- RPC de venta: el navegador nunca envía ni decide costos/ganancia.
create or replace function public.registrar_venta_drosalud(p_venta jsonb,p_items jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_admin boolean := public.es_admin_drosalud();
  v_rec public.recibos%rowtype;
  v_item jsonb;
  v_producto public.productos%rowtype;
  v_costo numeric;
  v_subtotal numeric := 0;
  v_ganancia numeric := 0;
  v_desc numeric := greatest(coalesce((p_venta->>'descuento')::numeric,0),0);
  v_dom numeric := greatest(coalesce((p_venta->>'domicilio')::numeric,0),0);
  v_mens numeric := greatest(coalesce((p_venta->>'costo_mensajero')::numeric,0),0);
  v_total numeric;
begin
  if not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La venta no tiene productos'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if coalesce((v_item->>'cantidad')::numeric,0)<=0 or coalesce((v_item->>'precio_venta')::numeric,-1)<0 then
      raise exception 'Cantidad o precio de venta inválido';
    end if;
    v_costo:=0;
    if nullif(v_item->>'producto_id','') is not null then
      select * into v_producto from public.productos where id=(v_item->>'producto_id')::uuid;
      if not found then raise exception 'Producto inexistente'; end if;
      v_costo:=case when coalesce(v_producto.fraccionable,false)
        then v_producto.precio_compra/greatest(v_producto.unidades_por_caja,1)
        else v_producto.precio_compra end;
    end if;
    v_subtotal:=v_subtotal+(v_item->>'precio_venta')::numeric*(v_item->>'cantidad')::numeric;
    v_ganancia:=v_ganancia+(((v_item->>'precio_venta')::numeric-v_costo)*(v_item->>'cantidad')::numeric);
  end loop;
  v_total:=greatest(0,v_subtotal-v_desc+v_dom);
  v_ganancia:=v_ganancia-v_desc+v_dom-v_mens;

  insert into public.recibos(cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,cliente_direccion,
    descuento,domicilio,costo_mensajero,forma_pago,recibido,vendedor,total,ganancia,creado_por)
  values(
    nullif(p_venta->>'cliente_id','')::uuid,
    nullif(p_venta->>'cliente_nombre',''),nullif(p_venta->>'cliente_cedula',''),
    nullif(p_venta->>'cliente_telefono',''),nullif(p_venta->>'cliente_direccion',''),
    v_desc,v_dom,v_mens,nullif(p_venta->>'forma_pago',''),
    nullif(p_venta->>'recibido','')::numeric,nullif(p_venta->>'vendedor',''),
    v_total,v_ganancia,v_user
  ) returning * into v_rec;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_costo:=0;
    if nullif(v_item->>'producto_id','') is not null then
      select * into v_producto from public.productos where id=(v_item->>'producto_id')::uuid;
      v_costo:=case when coalesce(v_producto.fraccionable,false)
        then v_producto.precio_compra/greatest(v_producto.unidades_por_caja,1)
        else v_producto.precio_compra end;
    end if;
    insert into public.recibo_items(recibo_id,producto_id,nombre,cantidad,precio_compra,precio_venta,
      presentacion,unidades_por_presentacion)
    values(v_rec.id,nullif(v_item->>'producto_id','')::uuid,v_item->>'nombre',
      (v_item->>'cantidad')::integer,v_costo,(v_item->>'precio_venta')::numeric,
      coalesce(nullif(v_item->>'presentacion',''),'Unidad'),
      greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1)));
  end loop;
  if v_admin then return to_jsonb(v_rec); end if;
  return to_jsonb(v_rec)-'ganancia';
end;
$$;

-- RPC para cotizaciones: el costo snapshot también lo calcula la base.
create or replace function public.crear_cotizacion_venta_drosalud(p_cotizacion jsonb,p_items jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid:=auth.uid(); v_co public.cotizaciones_venta%rowtype;
  v_item jsonb; v_producto public.productos%rowtype; v_costo numeric;
begin
  if not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La cotización no tiene productos'; end if;
  insert into public.cotizaciones_venta(owner_id,cliente_id,cliente_nombre,cliente_cedula,
    cliente_telefono,vendedor,descuento,domicilio,subtotal,total,estado,valida_hasta)
  values(v_user,nullif(p_cotizacion->>'cliente_id','')::uuid,
    nullif(p_cotizacion->>'cliente_nombre',''),nullif(p_cotizacion->>'cliente_cedula',''),
    nullif(p_cotizacion->>'cliente_telefono',''),nullif(p_cotizacion->>'vendedor',''),
    greatest(0,coalesce((p_cotizacion->>'descuento')::numeric,0)),
    greatest(0,coalesce((p_cotizacion->>'domicilio')::numeric,0)),
    greatest(0,coalesce((p_cotizacion->>'subtotal')::numeric,0)),
    greatest(0,coalesce((p_cotizacion->>'total')::numeric,0)),'pendiente',
    nullif(p_cotizacion->>'valida_hasta','')::date)
  returning * into v_co;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if coalesce((v_item->>'cantidad')::numeric,0)<=0 or coalesce((v_item->>'precio_venta')::numeric,-1)<0 then
      raise exception 'Cantidad o precio inválido';
    end if;
    v_costo:=0;
    if nullif(v_item->>'producto_id','') is not null then
      select * into v_producto from public.productos where id=(v_item->>'producto_id')::uuid;
      if not found then raise exception 'Producto inexistente'; end if;
      v_costo:=case when coalesce(v_producto.fraccionable,false)
        then v_producto.precio_compra/greatest(v_producto.unidades_por_caja,1)
        else v_producto.precio_compra end;
    end if;
    insert into public.cotizacion_venta_items(cotizacion_id,producto_id,nombre,cantidad,
      precio_compra,precio_venta,presentacion,unidades_por_presentacion)
    values(v_co.id,nullif(v_item->>'producto_id','')::uuid,v_item->>'nombre',
      (v_item->>'cantidad')::integer,v_costo,(v_item->>'precio_venta')::numeric,
      coalesce(nullif(v_item->>'presentacion',''),'Unidad'),
      greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1)));
  end loop;
  return to_jsonb(v_co);
end;
$$;

-- Precio de venta editable por vendedor; jamás recibe precio de compra.
create or replace function public.actualizar_precio_venta_drosalud(p_producto_id uuid,p_precio numeric)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_usuario_drosalud() or p_precio<0 then raise exception 'Operación no autorizada o precio inválido'; end if;
  update public.productos set precio_venta=p_precio,actualizado_en=now()
  where id=p_producto_id;
  if not found then raise exception 'Producto no encontrado'; end if;
end;
$$;

revoke all on function public.registrar_venta_drosalud(jsonb,jsonb) from public,anon;
revoke all on function public.crear_cotizacion_venta_drosalud(jsonb,jsonb) from public,anon;
revoke all on function public.actualizar_precio_venta_drosalud(uuid,numeric) from public,anon;
grant execute on function public.registrar_venta_drosalud(jsonb,jsonb),
 public.crear_cotizacion_venta_drosalud(jsonb,jsonb),
 public.actualizar_precio_venta_drosalud(uuid,numeric) to authenticated;

revoke all on function public.mas_vendidos(integer) from public,anon;
grant execute on function public.mas_vendidos(integer) to authenticated;

-- El trigger existente trg_log_precio se conserva sin cambios.
commit;

-- Después de aplicar en una base de pruebas:
-- 1. Asignar vendedor en usuarios_drosalud con el UUID de auth.users.
-- 2. Probar RPC venta/cotización con admin y vendedor.
-- 3. Confirmar que productos_app.precio_compra, recibos_app.ganancia,
--    recibo_items_app.precio_compra/costo_real_unitario y
--    cotizacion_venta_items_app.precio_compra son NULL para vendedor.
-- 4. Probar SELECT directo a tablas sensibles: debe ser denegado.
-- 5. Probar que admin conserva lectura de costos a través de las vistas.
