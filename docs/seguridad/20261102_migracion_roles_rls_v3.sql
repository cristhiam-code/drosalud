-- Drosalud · roles y seguridad v3
-- Ejecutar SOLO en proyecto de pruebas tras respaldo. No aplicar en producción todavía.
-- Compatible con el frontend de feature/seguridad-usuarios.
begin;

create table if not exists public.usuarios_drosalud (
  user_id uuid primary key references auth.users(id) on delete cascade,
  rol text not null check (rol in ('admin','vendedor')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table public.usuarios_drosalud enable row level security;

create or replace function public.es_usuario_drosalud()
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.usuarios_drosalud u
   where u.user_id=auth.uid() and u.activo=true);
$$;
create or replace function public.es_admin_drosalud()
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.usuarios_drosalud u
   where u.user_id=auth.uid() and u.activo=true and u.rol='admin');
$$;
revoke all on function public.es_usuario_drosalud() from public,anon;
revoke all on function public.es_admin_drosalud() from public,anon;
grant execute on function public.es_usuario_drosalud(),public.es_admin_drosalud() to authenticated;

-- Elimina políticas anteriores que pudieran abrir acceso por OR.
do $$
declare p record;
begin
 for p in select schemaname,tablename,policyname from pg_policies
  where schemaname='public' and tablename=any(array[
   'usuarios_drosalud','productos','clientes','recibos','recibo_items','ajustes',
   'historial_precios','compras_pendientes','proveedores','cotizaciones_venta',
   'cotizacion_venta_items','cotizaciones_proveedor'
  ])
 loop
  execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
 end loop;
end $$;

insert into public.usuarios_drosalud(user_id,rol,activo)
select id,'admin',true from auth.users
where lower(email)=lower('boterocristhiam@gmail.com')
on conflict(user_id) do update set rol='admin',activo=true;

create policy perfil_lectura_propia on public.usuarios_drosalud
 for select to authenticated using(user_id=auth.uid() or public.es_admin_drosalud());
create policy admin_gestiona_perfiles on public.usuarios_drosalud
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());

alter table public.recibos add column if not exists creado_por uuid references auth.users(id);
alter table public.recibos alter column creado_por set default auth.uid();

-- Catálogo: acceso directo únicamente administrador. Vendedor consume productos_app.
create policy productos_solo_admin_lectura on public.productos
 for select to authenticated using(public.es_admin_drosalud());
create policy productos_solo_admin_escritura on public.productos
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());

-- Clientes compartidos entre el personal activo.
create policy clientes_lectura_personal on public.clientes
 for select to authenticated using(public.es_usuario_drosalud());
create policy clientes_alta_personal on public.clientes
 for insert to authenticated with check(public.es_usuario_drosalud());
create policy clientes_edicion_personal on public.clientes
 for update to authenticated using(public.es_usuario_drosalud())
 with check(public.es_usuario_drosalud());
create policy clientes_borrado_admin on public.clientes
 for delete to authenticated using(public.es_admin_drosalud());

-- Recibos y sus costos: acceso directo reservado a administrador.
create policy recibos_lectura_admin on public.recibos
 for select to authenticated using(public.es_admin_drosalud());
create policy recibos_edicion_admin on public.recibos
 for update to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());
create policy recibos_borrado_admin on public.recibos
 for delete to authenticated using(public.es_admin_drosalud());

create policy recibo_items_lectura_admin on public.recibo_items
 for select to authenticated using(public.es_admin_drosalud());
create policy recibo_items_admin_total on public.recibo_items
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());

-- Ajustes, costos históricos, compras y proveedores: solo administrador.
create policy ajustes_admin_total on public.ajustes
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());
create policy historial_costos_admin_total on public.historial_precios
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());
create policy compras_admin_total on public.compras_pendientes
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());
create policy proveedores_admin_total on public.proveedores
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());
create policy cotizaciones_proveedor_admin_total on public.cotizaciones_proveedor
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());

-- Cotizaciones de venta: cada usuario consulta y gestiona las propias.
create policy cot_lectura_propias on public.cotizaciones_venta
 for select to authenticated using(public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or owner_id=auth.uid()));
create policy cot_alta_propias on public.cotizaciones_venta
 for insert to authenticated with check(public.es_usuario_drosalud() and owner_id=auth.uid());
create policy cot_edicion_propias on public.cotizaciones_venta
 for update to authenticated using(public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or owner_id=auth.uid()))
 with check(public.es_usuario_drosalud() and (public.es_admin_drosalud() or owner_id=auth.uid()));
create policy cot_borrado_propias on public.cotizaciones_venta
 for delete to authenticated using(public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or owner_id=auth.uid()));

-- Items de cotización contienen costo: solo admin puede leerlos directamente.
create policy cot_items_lectura_admin on public.cotizacion_venta_items
 for select to authenticated using(public.es_admin_drosalud());
create policy cot_items_admin_total on public.cotizacion_venta_items
 for all to authenticated using(public.es_admin_drosalud())
 with check(public.es_admin_drosalud());

-- Vistas con columnas sensibles anonimizadas para vendedores.
create or replace view public.productos_app with (security_barrier=true) as
 select id,codigo,nombre,laboratorio,
  case when public.es_admin_drosalud() then precio_compra else null end as precio_compra,
  actualizado_en,precio_venta,fraccionable,unidades_por_caja,unidades_por_venta
 from public.productos
 where public.es_usuario_drosalud();

create or replace view public.recibos_app with (security_barrier=true) as
 select id,numero,cliente_id,cliente_nombre,total,
  case when public.es_admin_drosalud() then ganancia else null end as ganancia,
  creado_en,descuento,domicilio,forma_pago,cliente_cedula,cliente_telefono,
  cliente_direccion,recibido,anulado,anulado_en,motivo_anulacion,vendedor,
  costo_mensajero,creado_por
 from public.recibos
 where public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or creado_por=auth.uid());

create or replace view public.recibo_items_app with (security_barrier=true) as
 select i.id,i.recibo_id,i.producto_id,i.nombre,i.cantidad,
  case when public.es_admin_drosalud() then i.precio_compra else null end as precio_compra,
  i.precio_venta,
  case when public.es_admin_drosalud() then i.costo_real_unitario else null end as costo_real_unitario,
  i.presentacion,i.unidades_por_presentacion
 from public.recibo_items i join public.recibos r on r.id=i.recibo_id
 where public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or r.creado_por=auth.uid());

create or replace view public.cotizaciones_venta_app with (security_barrier=true) as
 select id,numero,owner_id,cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,
  vendedor,descuento,domicilio,subtotal,total,estado,valida_hasta,recibo_id,creado_en
 from public.cotizaciones_venta
 where public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or owner_id=auth.uid());

create or replace view public.cotizacion_venta_items_app with (security_barrier=true) as
 select i.id,i.cotizacion_id,i.producto_id,i.nombre,i.cantidad,
  case when public.es_admin_drosalud() then i.precio_compra else null end as precio_compra,
  i.precio_venta,i.presentacion,i.unidades_por_presentacion
 from public.cotizacion_venta_items i
 join public.cotizaciones_venta c on c.id=i.cotizacion_id
 where public.es_usuario_drosalud()
  and (public.es_admin_drosalud() or c.owner_id=auth.uid());

-- Permisos de tablas: RLS determina qué rol puede acceder a filas sensibles.
revoke all on public.usuarios_drosalud,public.productos,public.recibos,public.recibo_items,
 public.cotizacion_venta_items,public.ajustes,public.historial_precios,
 public.compras_pendientes,public.proveedores,public.cotizaciones_proveedor
 from anon;
grant select,insert,update,delete on public.usuarios_drosalud,public.productos,public.recibos,
 public.recibo_items,public.cotizacion_venta_items,public.ajustes,public.historial_precios,
 public.compras_pendientes,public.proveedores,public.cotizaciones_proveedor to authenticated;
grant select,insert,update,delete on public.cotizaciones_venta,public.clientes to authenticated;
grant select on public.productos_app,public.recibos_app,public.recibo_items_app,
 public.cotizaciones_venta_app,public.cotizacion_venta_items_app to authenticated;
grant usage on schema public to authenticated;

-- RPC: costos y utilidad se calculan en PostgreSQL, no en el navegador.
create or replace function public.registrar_venta_drosalud(p_venta jsonb,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
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
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La venta no tiene productos'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if coalesce((v_item->>'cantidad')::numeric,0)<=0
   or coalesce((v_item->>'cantidad')::numeric,0)<>trunc((v_item->>'cantidad')::numeric)
   or coalesce((v_item->>'precio_venta')::numeric,-1)<0 then raise exception 'Cantidad o precio inválido'; end if;
  v_costo:=0;
  if nullif(v_item->>'producto_id','') is not null then
   select * into v_prod from public.productos where id=(v_item->>'producto_id')::uuid;
   if not found then raise exception 'Producto inexistente'; end if;
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
end $$;

create or replace function public.crear_cotizacion_venta_drosalud(p_cotizacion jsonb,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_co public.cotizaciones_venta%rowtype;
 v_item jsonb; v_prod public.productos%rowtype; v_costo numeric;
 v_subtotal numeric:=0; v_desc numeric:=greatest(coalesce((p_cotizacion->>'descuento')::numeric,0),0);
 v_dom numeric:=greatest(coalesce((p_cotizacion->>'domicilio')::numeric,0),0);
begin
 if not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La cotización no tiene productos'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if coalesce((v_item->>'cantidad')::numeric,0)<=0
   or coalesce((v_item->>'cantidad')::numeric,0)<>trunc((v_item->>'cantidad')::numeric)
   or coalesce((v_item->>'precio_venta')::numeric,-1)<0 then raise exception 'Cantidad o precio inválido'; end if;
  v_subtotal:=v_subtotal+(v_item->>'precio_venta')::numeric*(v_item->>'cantidad')::numeric;
 end loop;
 insert into public.cotizaciones_venta(owner_id,cliente_id,cliente_nombre,cliente_cedula,cliente_telefono,
  vendedor,descuento,domicilio,subtotal,total,estado,valida_hasta)
 values(v_user,nullif(p_cotizacion->>'cliente_id','')::uuid,nullif(p_cotizacion->>'cliente_nombre',''),
  nullif(p_cotizacion->>'cliente_cedula',''),nullif(p_cotizacion->>'cliente_telefono',''),
  nullif(p_cotizacion->>'vendedor',''),v_desc,v_dom,v_subtotal,
  greatest(0,v_subtotal-v_desc+v_dom),'pendiente',nullif(p_cotizacion->>'valida_hasta','')::date)
 returning * into v_co;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_costo:=0;
  if nullif(v_item->>'producto_id','') is not null then
   select * into v_prod from public.productos where id=(v_item->>'producto_id')::uuid;
   if not found then raise exception 'Producto inexistente'; end if;
   v_costo:=case when v_prod.fraccionable then v_prod.precio_compra/greatest(v_prod.unidades_por_caja,1) else v_prod.precio_compra end;
  end if;
  insert into public.cotizacion_venta_items(cotizacion_id,producto_id,nombre,cantidad,precio_compra,
   precio_venta,presentacion,unidades_por_presentacion)
  values(v_co.id,nullif(v_item->>'producto_id','')::uuid,v_item->>'nombre',
   (v_item->>'cantidad')::integer,v_costo,(v_item->>'precio_venta')::numeric,
   coalesce(nullif(v_item->>'presentacion',''),'Unidad'),
   greatest(1,coalesce((v_item->>'unidades_por_presentacion')::integer,1)));
 end loop;
 return to_jsonb(v_co);
end $$;

create or replace function public.actualizar_precio_venta_drosalud(p_producto_id uuid,p_precio numeric)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.es_usuario_drosalud() or p_precio is null or p_precio<0 then raise exception 'Operación no autorizada o precio inválido'; end if;
 update public.productos set precio_venta=p_precio,actualizado_en=now() where id=p_producto_id;
 if not found then raise exception 'Producto no encontrado'; end if;
end $$;

revoke all on function public.registrar_venta_drosalud(jsonb,jsonb) from public,anon;
revoke all on function public.crear_cotizacion_venta_drosalud(jsonb,jsonb) from public,anon;
revoke all on function public.actualizar_precio_venta_drosalud(uuid,numeric) from public,anon;
grant execute on function public.registrar_venta_drosalud(jsonb,jsonb),
 public.crear_cotizacion_venta_drosalud(jsonb,jsonb),
 public.actualizar_precio_venta_drosalud(uuid,numeric) to authenticated;

-- No exponer agregados de ventas/costos por la función antigua a vendedores.
revoke all on function public.mas_vendidos(integer) from public,anon,authenticated;

-- El trigger trg_log_precio y su función se conservan: solo admin actualiza precio_compra.

commit;

-- PRUEBAS OBLIGATORIAS EN STAGING ANTES DE PRODUCCIÓN:
-- 1) Admin: leer y modificar catálogo, costos, recibos y ajustes.
-- 2) Vendedor: ver catálogo/precios venta, crear cliente, cotizar y vender.
-- 3) Vendedor: SELECT directo a productos/recibos/recibo_items/cotizacion_venta_items debe devolver cero filas.
-- 4) Las vistas app deben devolver NULL en costos/ganancias para vendedor.
-- 5) Verificar que el usuario vendedor solo vea recibos propios y cotizaciones propias.
