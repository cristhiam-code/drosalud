-- Estructura base para Pedidos de Sucursales.
-- Se aplica primero en QA. No modifica el módulo de compras a proveedores.
create table public.sucursales (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  activa boolean not null default true,
  es_central boolean not null default false,
  creado_en timestamptz not null default now(),
  creado_por uuid references auth.users(id)
);
create unique index sucursales_unica_central on public.sucursales(es_central) where es_central = true;

create table public.bodegas (
  id uuid primary key default gen_random_uuid(),
  sucursal_id uuid not null references public.sucursales(id),
  codigo text not null unique,
  nombre text not null,
  activa boolean not null default true,
  es_central boolean not null default false,
  creado_en timestamptz not null default now(),
  unique (id, sucursal_id)
);
create unique index bodegas_unica_central on public.bodegas(es_central) where es_central = true;
create unique index bodegas_una_activa_por_sucursal on public.bodegas(sucursal_id) where activa = true;

create table public.usuarios_sucursales (
  user_id uuid primary key references public.usuarios_drosalud(user_id) on delete cascade,
  sucursal_id uuid not null references public.sucursales(id),
  activo boolean not null default true,
  asignado_en timestamptz not null default now(),
  asignado_por uuid references auth.users(id)
);

create table public.sucursal_dias_pedido (
  sucursal_id uuid not null references public.sucursales(id) on delete cascade,
  dia_semana smallint not null check (dia_semana between 0 and 6),
  habilitado boolean not null default true,
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  primary key (sucursal_id, dia_semana)
);

create table public.inventario_sucursal_movimientos (
  id uuid primary key default gen_random_uuid(),
  bodega_id uuid not null references public.bodegas(id),
  producto_id uuid not null references public.productos(id),
  tipo text not null check (tipo in ('saldo_inicial','venta','anulacion','recepcion_proveedor','ajuste','despacho_salida','recepcion_traslado')),
  unidades_delta integer not null check (unidades_delta <> 0),
  referencia_id uuid,
  operacion_id uuid,
  movimiento_origen_id uuid unique references public.inventario_movimientos(id),
  notas text,
  creado_por uuid references auth.users(id),
  creado_en timestamptz not null default now()
);
create index inventario_sucursal_mov_bodega_producto on public.inventario_sucursal_movimientos(bodega_id, producto_id, creado_en);
create index inventario_sucursal_mov_producto_fecha on public.inventario_sucursal_movimientos(producto_id, creado_en);

create view public.inventario_sucursal_saldos
with (security_invoker = true) as
select bodega_id, producto_id, sum(unidades_delta)::integer as saldo_unidades
from public.inventario_sucursal_movimientos group by bodega_id, producto_id;

create table public.pedidos_sucursal (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity unique,
  sucursal_id uuid not null references public.sucursales(id),
  bodega_destino_id uuid not null references public.bodegas(id),
  tipo text not null check (tipo in ('sugerido','urgente')),
  estado text not null default 'pendiente_autorizacion'
    check (estado in ('pendiente_autorizacion','aprobado','rechazado','en_preparacion','despachado','parcial','recibido','cancelado')),
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  enviado_en timestamptz not null default now(),
  autorizado_por uuid references auth.users(id),
  autorizado_en timestamptz,
  rechazado_por uuid references auth.users(id),
  rechazado_en timestamptz,
  motivo_rechazo text,
  notas text
);
create index pedidos_sucursal_sucursal_fecha on public.pedidos_sucursal(sucursal_id, creado_en desc);
create index pedidos_sucursal_estado_fecha on public.pedidos_sucursal(estado, creado_en desc);

create table public.pedidos_sucursal_items (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references public.pedidos_sucursal(id) on delete cascade,
  producto_id uuid not null references public.productos(id),
  producto_nombre text not null,
  cantidad_solicitada integer not null check (cantidad_solicitada > 0),
  cantidad_autorizada integer check (cantidad_autorizada is null or cantidad_autorizada >= 0),
  cantidad_despachada integer not null default 0 check (cantidad_despachada >= 0),
  cantidad_recibida integer not null default 0 check (cantidad_recibida >= 0),
  ventas_7_dias integer not null default 0,
  saldo_al_solicitar integer not null default 0,
  pendientes_al_solicitar integer not null default 0,
  creado_en timestamptz not null default now(),
  unique (pedido_id, producto_id)
);
create index pedidos_sucursal_items_pedido on public.pedidos_sucursal_items(pedido_id);

create table public.despachos_sucursal (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity unique,
  pedido_id uuid not null references public.pedidos_sucursal(id),
  estado text not null default 'despachado' check (estado in ('despachado','parcial','recibido')),
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  recibido_por uuid references auth.users(id),
  recibido_en timestamptz,
  notas text
);
create index despachos_sucursal_pedido on public.despachos_sucursal(pedido_id, creado_en);

create table public.despachos_sucursal_items (
  id uuid primary key default gen_random_uuid(),
  despacho_id uuid not null references public.despachos_sucursal(id) on delete cascade,
  pedido_item_id uuid not null references public.pedidos_sucursal_items(id),
  producto_id uuid not null references public.productos(id),
  producto_nombre text not null,
  unidades_enviadas integer not null check (unidades_enviadas > 0),
  unidades_recibidas integer check (unidades_recibidas is null or unidades_recibidas between 0 and unidades_enviadas),
  creado_en timestamptz not null default now(),
  unique (despacho_id, pedido_item_id)
);

insert into public.sucursales(codigo,nombre,es_central)
values ('CENTRAL','Bodega Central',true) on conflict (codigo) do nothing;
insert into public.bodegas(sucursal_id,codigo,nombre,es_central)
select s.id,'BOD-CENTRAL','Bodega Central',true from public.sucursales s where s.codigo='CENTRAL'
on conflict (codigo) do nothing;
insert into public.usuarios_sucursales(user_id,sucursal_id,activo)
select u.user_id,s.id,true from public.usuarios_drosalud u cross join public.sucursales s
where u.activo=true and s.codigo='CENTRAL' on conflict (user_id) do nothing;
insert into public.inventario_sucursal_movimientos(bodega_id,producto_id,tipo,unidades_delta,notas)
select b.id,i.producto_id,'saldo_inicial',i.saldo_unidades,
'Saldo inicial migrado desde inventario general al crear la estructura multi-sucursal'
from public.inventario_saldos i cross join public.bodegas b join public.sucursales s on s.id=b.sucursal_id
where s.codigo='CENTRAL' and i.saldo_unidades<>0 on conflict do nothing;

create or replace function public.ps_sync_movimiento_inventario()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare v_bodega uuid; v_tipo text;
begin
  if new.tipo='anulacion' then
    select sm.bodega_id into v_bodega
    from public.inventario_sucursal_movimientos sm
    join public.inventario_movimientos original on original.id=sm.movimiento_origen_id
    where original.tipo='venta' and original.referencia_id=new.referencia_id
      and original.producto_id=new.producto_id order by sm.creado_en desc limit 1;
  end if;
  if v_bodega is null and new.tipo='recepcion' then
    select id into v_bodega from public.bodegas where es_central=true and activa=true limit 1;
  end if;
  if v_bodega is null then
    select b.id into v_bodega from public.usuarios_sucursales us
    join public.bodegas b on b.sucursal_id=us.sucursal_id and b.activa=true
    where us.user_id=new.creado_por and us.activo=true limit 1;
  end if;
  if v_bodega is null then select id into v_bodega from public.bodegas where es_central=true and activa=true limit 1; end if;
  if v_bodega is null then return new; end if;
  v_tipo:=case new.tipo when 'venta' then 'venta' when 'anulacion' then 'anulacion'
    when 'recepcion' then 'recepcion_proveedor' when 'ajuste' then 'ajuste'
    when 'saldo_inicial' then 'saldo_inicial' else null end;
  if v_tipo is not null then
    insert into public.inventario_sucursal_movimientos
      (bodega_id,producto_id,tipo,unidades_delta,referencia_id,movimiento_origen_id,notas,creado_por,creado_en)
    values(v_bodega,new.producto_id,v_tipo,new.unidades_delta,new.referencia_id,new.id,new.notas,new.creado_por,new.creado_en)
    on conflict(movimiento_origen_id) do nothing;
  end if;
  return new;
end;$function$;
create trigger trg_ps_sync_inventario_movimiento after insert on public.inventario_movimientos
for each row execute function public.ps_sync_movimiento_inventario();

alter table public.sucursales enable row level security;
alter table public.bodegas enable row level security;
alter table public.usuarios_sucursales enable row level security;
alter table public.sucursal_dias_pedido enable row level security;
alter table public.inventario_sucursal_movimientos enable row level security;
alter table public.pedidos_sucursal enable row level security;
alter table public.pedidos_sucursal_items enable row level security;
alter table public.despachos_sucursal enable row level security;
alter table public.despachos_sucursal_items enable row level security;

create policy ps_sucursales_select on public.sucursales for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.usuarios_sucursales us where us.user_id=(select auth.uid()) and us.sucursal_id=sucursales.id and us.activo));
create policy ps_bodegas_select on public.bodegas for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.usuarios_sucursales us where us.user_id=(select auth.uid()) and us.sucursal_id=bodegas.sucursal_id and us.activo));
create policy ps_usuarios_sucursales_select on public.usuarios_sucursales for select to authenticated
using(public.es_admin_drosalud() or user_id=(select auth.uid()));
create policy ps_dias_pedido_select on public.sucursal_dias_pedido for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.usuarios_sucursales us where us.user_id=(select auth.uid()) and us.sucursal_id=sucursal_dias_pedido.sucursal_id and us.activo));
create policy ps_inv_mov_select on public.inventario_sucursal_movimientos for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.bodegas b join public.usuarios_sucursales us on us.sucursal_id=b.sucursal_id where b.id=inventario_sucursal_movimientos.bodega_id and us.user_id=(select auth.uid()) and us.activo));
create policy ps_pedidos_select on public.pedidos_sucursal for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.usuarios_sucursales us where us.user_id=(select auth.uid()) and us.sucursal_id=pedidos_sucursal.sucursal_id and us.activo));
create policy ps_pedido_items_select on public.pedidos_sucursal_items for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.pedidos_sucursal p join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id where p.id=pedidos_sucursal_items.pedido_id and us.user_id=(select auth.uid()) and us.activo));
create policy ps_despachos_select on public.despachos_sucursal for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.pedidos_sucursal p join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id where p.id=despachos_sucursal.pedido_id and us.user_id=(select auth.uid()) and us.activo));
create policy ps_despacho_items_select on public.despachos_sucursal_items for select to authenticated
using(public.es_admin_drosalud() or exists(select 1 from public.despachos_sucursal d join public.pedidos_sucursal p on p.id=d.pedido_id join public.usuarios_sucursales us on us.sucursal_id=p.sucursal_id where d.id=despachos_sucursal_items.despacho_id and us.user_id=(select auth.uid()) and us.activo));

revoke all on public.sucursales,public.bodegas,public.usuarios_sucursales,public.sucursal_dias_pedido,public.inventario_sucursal_movimientos,
public.pedidos_sucursal,public.pedidos_sucursal_items,public.despachos_sucursal,public.despachos_sucursal_items from anon;
grant select on public.sucursales,public.bodegas,public.usuarios_sucursales,public.sucursal_dias_pedido,public.inventario_sucursal_movimientos,
public.inventario_sucursal_saldos,public.pedidos_sucursal,public.pedidos_sucursal_items,public.despachos_sucursal,public.despachos_sucursal_items to authenticated;

create or replace function public.ps_admin_crear_sucursal(p_codigo text,p_nombre text)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_sucursal uuid; v_codigo text;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede crear sucursales'; end if;
 v_codigo:=upper(regexp_replace(trim(coalesce(p_codigo,'')),'[^A-Za-z0-9_-]','','g'));
 if v_codigo='' or nullif(trim(p_nombre),'') is null then raise exception 'Código y nombre son obligatorios'; end if;
 insert into public.sucursales(codigo,nombre,es_central,creado_por) values(v_codigo,trim(p_nombre),false,auth.uid()) returning id into v_sucursal;
 insert into public.bodegas(sucursal_id,codigo,nombre,es_central) values(v_sucursal,'BOD-'||v_codigo,'Bodega '||trim(p_nombre),false);
 return v_sucursal;
end;$function$;

create or replace function public.ps_admin_asignar_usuario(p_user_id uuid,p_sucursal_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede asignar usuarios'; end if;
 if not exists(select 1 from public.usuarios_drosalud where user_id=p_user_id and activo=true) then raise exception 'El usuario no existe o está inactivo'; end if;
 if not exists(select 1 from public.sucursales where id=p_sucursal_id and activa=true and es_central=false) then raise exception 'Selecciona una sucursal activa distinta de la bodega central'; end if;
 insert into public.usuarios_sucursales(user_id,sucursal_id,activo,asignado_por) values(p_user_id,p_sucursal_id,true,auth.uid())
 on conflict(user_id) do update set sucursal_id=excluded.sucursal_id,activo=true,asignado_en=now(),asignado_por=auth.uid();
end;$function$;

create or replace function public.ps_admin_configurar_dias(p_sucursal_id uuid,p_dias smallint[])
returns void language plpgsql security definer set search_path = '' as $function$
declare v_dia smallint;
begin
 if auth.uid() is null or not public.es_admin_drosalud() then raise exception 'Solo administración puede configurar los días de pedido'; end if;
 if not exists(select 1 from public.sucursales where id=p_sucursal_id and activa=true and es_central=false) then raise exception 'Sucursal no válida'; end if;
 if p_dias is null or exists(select 1 from unnest(p_dias) d where d<0 or d>6) then raise exception 'Los días deben estar entre 0 y 6 (domingo a sábado)'; end if;
 delete from public.sucursal_dias_pedido where sucursal_id=p_sucursal_id;
 foreach v_dia in array p_dias loop insert into public.sucursal_dias_pedido(sucursal_id,dia_semana,habilitado,actualizado_por) values(p_sucursal_id,v_dia,true,auth.uid()); end loop;
end;$function$;

create or replace function public.ps_obtener_contexto()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_result jsonb;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Inicia sesión con un usuario activo de Drosalud'; end if;
 select jsonb_build_object('sucursal_id',s.id,'sucursal_nombre',s.nombre,'es_central',s.es_central,'es_admin',public.es_admin_drosalud(),'rol',u.rol)
 into v_result from public.usuarios_sucursales us join public.sucursales s on s.id=us.sucursal_id and s.activa
 join public.usuarios_drosalud u on u.user_id=us.user_id and u.activo
 where us.user_id=auth.uid() and us.activo;
 if v_result is null then raise exception 'Este usuario todavía no tiene una sucursal asignada. La administración debe configurarla antes de crear pedidos.'; end if;
 return v_result;
end;$function$;

create or replace function public.ps_obtener_pedido_sugerido()
returns table(producto_id uuid,codigo text,producto_nombre text,laboratorio text,ventas_7_dias integer,saldo_unidades integer,pendientes_unidades integer,cantidad_sugerida integer)
language plpgsql stable security definer set search_path = '' as $function$
declare v_sucursal uuid; v_bodega uuid;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 select us.sucursal_id,b.id into v_sucursal,v_bodega from public.usuarios_sucursales us join public.bodegas b on b.sucursal_id=us.sucursal_id and b.activa where us.user_id=auth.uid() and us.activo limit 1;
 if v_bodega is null then raise exception 'No hay bodega asignada a esta sucursal'; end if;
 return query
 with ventas as (select m.producto_id,sum(-m.unidades_delta)::integer as unidades from public.inventario_sucursal_movimientos m where m.bodega_id=v_bodega and m.tipo='venta' and m.unidades_delta<0 and m.creado_en>=now()-interval '7 days' group by m.producto_id),
 pendientes as (select i.producto_id,sum(greatest(0,coalesce(i.cantidad_autorizada,i.cantidad_solicitada)-i.cantidad_recibida))::integer as unidades from public.pedidos_sucursal_items i join public.pedidos_sucursal p on p.id=i.pedido_id where p.sucursal_id=v_sucursal and p.estado not in ('rechazado','cancelado','recibido') group by i.producto_id),
 saldos as (select producto_id,saldo_unidades from public.inventario_sucursal_saldos where bodega_id=v_bodega)
 select pr.id,pr.codigo,pr.nombre,pr.laboratorio,coalesce(v.unidades,0),coalesce(s.saldo_unidades,0),coalesce(pe.unidades,0),
 greatest(0,ceil(coalesce(v.unidades,0)-coalesce(s.saldo_unidades,0)-coalesce(pe.unidades,0)))::integer
 from public.productos pr left join ventas v on v.producto_id=pr.id left join saldos s on s.producto_id=pr.id left join pendientes pe on pe.producto_id=pr.id
 where coalesce(v.unidades,0)>0 order by pr.laboratorio nulls last,pr.nombre;
end;$function$;

create or replace function public.ps_obtener_productos_negativos()
returns table(producto_id uuid,codigo text,nombre text,laboratorio text,saldo_unidades integer)
language plpgsql stable security definer set search_path = '' as $function$
declare v_bodega uuid;
begin
 if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
 select b.id into v_bodega from public.usuarios_sucursales us join public.bodegas b on b.sucursal_id=us.sucursal_id and b.activa where us.user_id=auth.uid() and us.activo limit 1;
 if v_bodega is null then raise exception 'No hay bodega asignada a esta sucursal'; end if;
 return query select p.id,p.codigo,p.nombre,p.laboratorio,s.saldo_unidades from public.inventario_sucursal_saldos s join public.productos p on p.id=s.producto_id where s.bodega_id=v_bodega and s.saldo_unidades<0 order by s.saldo_unidades,p.nombre;
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
 where (v_admin or p.sucursal_id=v_sucursal) and (coalesce(p_filtro,'historial')<>'autorizados' or (v_admin and p.estado in ('pendiente_autorizacion','aprobado','en_preparacion')) or (not v_admin and p.estado in ('aprobado','en_preparacion','despachado','parcial')));
 return v_result;
end;$function$;

revoke all on function public.ps_sync_movimiento_inventario() from public,anon,authenticated;
revoke all on function public.ps_admin_crear_sucursal(text,text),public.ps_admin_asignar_usuario(uuid,uuid),public.ps_admin_configurar_dias(uuid,smallint[]),
 public.ps_obtener_contexto(),public.ps_obtener_pedido_sugerido(),public.ps_obtener_productos_negativos(),public.ps_listar_pedidos_sucursal(text) from public,anon;
grant execute on function public.ps_admin_crear_sucursal(text,text),public.ps_admin_asignar_usuario(uuid,uuid),public.ps_admin_configurar_dias(uuid,smallint[]),
 public.ps_obtener_contexto(),public.ps_obtener_pedido_sugerido(),public.ps_obtener_productos_negativos(),public.ps_listar_pedidos_sucursal(text) to authenticated;
