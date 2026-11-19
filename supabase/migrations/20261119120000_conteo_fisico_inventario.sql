-- Drosalud: conteo físico ciego con aprobación independiente.
-- Borrador local autorizado para implementación; NO ejecutar hasta revisar
-- el contrato real de registrar_recepcion_compra y validar en QA aislado.
-- No modifica RPC existentes de venta, compra, recepción o fraccionamiento.
begin;

alter table public.inventario_movimientos
  drop constraint if exists inventario_movimientos_tipo_check;
alter table public.inventario_movimientos
  add constraint inventario_movimientos_tipo_check
  check (tipo in ('venta','anulacion','recepcion','ajuste'));

create unique index if not exists inventario_movimientos_ajuste_referencia_unica_idx
  on public.inventario_movimientos(tipo, referencia_id)
  where tipo='ajuste' and referencia_id is not null;
create unique index if not exists inventario_movimientos_ajuste_operacion_unica_idx
  on public.inventario_movimientos(operacion_id)
  where tipo='ajuste' and operacion_id is not null;

create table public.inventario_conteos (
  id uuid primary key default gen_random_uuid(),
  solicitud_creacion_id uuid not null unique,
  solicitud_creacion_hash text not null,
  estado text not null default 'abierto' check (estado in ('abierto','cerrado','cancelado')),
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  cerrado_por uuid references auth.users(id),
  cerrado_en timestamptz,
  cancelado_por uuid references auth.users(id),
  cancelado_en timestamptz,
  motivo_cancelacion text,
  solicitud_cancelacion_id uuid unique,
  check ((estado='cerrado' and cerrado_por is not null and cerrado_en is not null) or estado<>'cerrado'),
  check ((estado='cancelado' and cancelado_por is not null and cancelado_en is not null
    and motivo_cancelacion is not null) or estado<>'cancelado')
);

create table public.inventario_conteos_items (
  id uuid primary key default gen_random_uuid(),
  conteo_id uuid not null references public.inventario_conteos(id) on delete restrict,
  producto_id uuid not null references public.productos(id) on delete restrict,
  estado text not null default 'seleccionado'
    check (estado in ('seleccionado','contando','pendiente_reconteo','pendiente_aprobacion','aprobado','cancelado')),
  codigo_corte text,
  nombre_corte text not null,
  laboratorio_corte text,
  fraccionable_corte boolean not null,
  unidades_por_caja_corte integer not null check (unidades_por_caja_corte>0),
  unidades_por_venta_corte integer not null check (unidades_por_venta_corte>0),
  saldo_teorico_corte bigint,
  cantidad_confirmada_base bigint check (cantidad_confirmada_base is null or cantidad_confirmada_base>=0),
  diferencia_base numeric generated always as
    (cantidad_confirmada_base::numeric-saldo_teorico_corte::numeric) stored,
  contador_asignado_a uuid references auth.users(id),
  inicio_operacion_id uuid unique,
  captura_operacion_id uuid unique,
  envio_revision_operacion_id uuid unique,
  aprobado_por uuid references auth.users(id),
  aprobado_en timestamptz,
  operacion_aprobacion_id uuid unique,
  motivo_aprobacion text,
  movimiento_id uuid unique references public.inventario_movimientos(id) on delete restrict,
  unique (conteo_id, producto_id),
  unique (id, conteo_id, producto_id),
  check (estado<>'pendiente_aprobacion' or (saldo_teorico_corte is not null and cantidad_confirmada_base is not null)),
  check (estado<>'aprobado' or (aprobado_por is not null and aprobado_en is not null
    and operacion_aprobacion_id is not null and cantidad_confirmada_base is not null))
);

create table public.inventario_conteo_capturas (
  id uuid primary key default gen_random_uuid(),
  conteo_item_id uuid not null references public.inventario_conteos_items(id) on delete restrict,
  numero integer not null check (numero>0),
  cantidad_base bigint not null check (cantidad_base>=0),
  contado_por uuid not null references auth.users(id),
  solicitud_id uuid not null unique,
  motivo text,
  contado_en timestamptz not null default now(),
  unique (conteo_item_id, numero),
  unique (conteo_item_id, contado_por)
);

create table public.inventario_conteos_bloqueos (
  producto_id uuid primary key references public.productos(id) on delete restrict,
  conteo_item_id uuid not null unique,
  conteo_id uuid not null,
  activado_por uuid not null references auth.users(id),
  activado_en timestamptz not null default now(),
  foreign key (conteo_item_id, conteo_id, producto_id)
    references public.inventario_conteos_items(id, conteo_id, producto_id) on delete restrict
);
create index inventario_conteo_bloqueos_sesion_idx
  on public.inventario_conteos_bloqueos(conteo_id,producto_id);

create table public.inventario_conteo_permisos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  puede_contar boolean not null default false,
  puede_aprobar boolean not null default false,
  otorgado_por uuid not null references auth.users(id),
  otorgado_en timestamptz not null default now(),
  revocado_por uuid references auth.users(id),
  revocado_en timestamptz,
  check (puede_contar or puede_aprobar),
  check ((revocado_por is null)=(revocado_en is null))
);
create unique index inventario_conteo_permiso_activo_idx on public.inventario_conteo_permisos(user_id)
  where revocado_en is null;
create index inventario_conteos_items_estado_idx on public.inventario_conteos_items(conteo_id,estado);
create index inventario_conteo_capturas_item_idx on public.inventario_conteo_capturas(conteo_item_id,numero);

alter table public.inventario_conteos enable row level security;
alter table public.inventario_conteos_items enable row level security;
alter table public.inventario_conteo_capturas enable row level security;
alter table public.inventario_conteos_bloqueos enable row level security;
alter table public.inventario_conteo_permisos enable row level security;
revoke all on public.inventario_conteos, public.inventario_conteos_items,
  public.inventario_conteo_capturas, public.inventario_conteos_bloqueos,
  public.inventario_conteo_permisos from public,anon,authenticated;

create or replace function public.inventario_conteo_tiene_permiso(p_aprobar boolean default false)
returns boolean language sql stable security definer set search_path=''
as $function$
  select auth.uid() is not null and public.es_usuario_drosalud() and (
    public.es_admin_drosalud() or exists (
      select 1 from public.inventario_conteo_permisos p
      where p.user_id=auth.uid() and p.revocado_en is null
        and case when p_aprobar then p.puede_aprobar else p.puede_contar end
    )
  );
$function$;
revoke all on function public.inventario_conteo_tiene_permiso(boolean) from public,anon,authenticated;

create or replace function public.proteger_movimiento_durante_conteo()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_item public.inventario_conteos_items%rowtype;
begin
  perform 1 from public.productos p where p.id=new.producto_id for update;
  if not found then raise exception 'Producto inexistente para movimiento'; end if;
  if exists(select 1 from public.inventario_conteos_bloqueos b where b.producto_id=new.producto_id) then
    raise exception 'Producto protegido por conteo físico' using errcode='55P03';
  end if;
  if new.tipo='ajuste' and new.referencia_id is not null then
    select i.* into v_item from public.inventario_conteos_items i where i.id=new.referencia_id;
    if not found or v_item.estado<>'aprobado' or v_item.producto_id<>new.producto_id
       or v_item.movimiento_id is not null
       or v_item.operacion_aprobacion_id is distinct from new.operacion_id
       or v_item.aprobado_por is distinct from new.creado_por
       or v_item.diferencia_base is distinct from new.unidades_delta
       or not public.inventario_conteo_tiene_permiso(true)
       or exists(select 1 from public.inventario_conteo_capturas c
          where c.conteo_item_id=v_item.id and c.contado_por=new.creado_por) then
      raise exception 'Ajuste físico sin aprobación válida';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.proteger_movimiento_durante_conteo() from public,anon,authenticated;
create trigger trg_bloquear_movimiento_durante_conteo
before insert on public.inventario_movimientos for each row
execute function public.proteger_movimiento_durante_conteo();

create or replace function public.proteger_presentacion_durante_conteo()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if exists(select 1 from public.inventario_conteos_bloqueos b where b.producto_id=old.id) then
    raise exception 'Producto protegido por conteo; presentación bloqueada' using errcode='55P03';
  end if;
  return new;
end;
$function$;
revoke all on function public.proteger_presentacion_durante_conteo() from public,anon,authenticated;
create trigger trg_proteger_presentacion_durante_conteo
before update of codigo,fraccionable,unidades_por_caja,unidades_por_venta on public.productos
for each row execute function public.proteger_presentacion_durante_conteo();

create or replace function public.consultar_capacidades_conteo()
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud() then raise exception 'Usuario no autorizado'; end if;
  return jsonb_build_object(
    'puede_contar',public.inventario_conteo_tiene_permiso(false),
    'puede_aprobar',public.inventario_conteo_tiene_permiso(true),
    'es_admin',public.es_admin_drosalud()
  );
end;
$function$;

create or replace function public.crear_conteo_inventario(
  p_productos uuid[],p_motivo text,p_solicitud_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_ids uuid[]; v_hash text; v_id uuid; v_existente public.inventario_conteos%rowtype;
  v_producto uuid; v_prod public.productos%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para crear conteos';
  end if;
  if p_productos is null or cardinality(p_productos)=0 or p_solicitud_id is null
     or nullif(btrim(p_motivo),'') is null or length(btrim(p_motivo))>500 then
    raise exception 'Selecciona productos, motivo y clave de solicitud';
  end if;
  select array_agg(x order by x) into v_ids from (select distinct unnest(p_productos) x) s;
  if cardinality(v_ids)<>cardinality(p_productos) or array_position(v_ids,null) is not null then
    raise exception 'La lista contiene productos repetidos o inválidos';
  end if;
  v_hash:=md5(array_to_string(v_ids,',')||'|'||btrim(p_motivo));
  insert into public.inventario_conteos(solicitud_creacion_id,solicitud_creacion_hash,motivo,creado_por)
    values(p_solicitud_id,v_hash,btrim(p_motivo),auth.uid())
    on conflict(solicitud_creacion_id) do nothing returning id into v_id;
  if v_id is null then
    select * into v_existente from public.inventario_conteos where solicitud_creacion_id=p_solicitud_id;
    if not found or v_existente.solicitud_creacion_hash<>v_hash or v_existente.creado_por<>auth.uid() then
      raise exception 'Clave de solicitud reutilizada con otros datos';
    end if;
    return v_existente.id;
  end if;
  foreach v_producto in array v_ids loop
    select * into v_prod from public.productos where id=v_producto;
    if not found then raise exception 'Producto inexistente: %',v_producto; end if;
    insert into public.inventario_conteos_items(
      conteo_id,producto_id,codigo_corte,nombre_corte,laboratorio_corte,fraccionable_corte,
      unidades_por_caja_corte,unidades_por_venta_corte
    ) values(v_id,v_prod.id,v_prod.codigo,v_prod.nombre,v_prod.laboratorio,
      coalesce(v_prod.fraccionable,false),greatest(coalesce(v_prod.unidades_por_caja,1),1),
      greatest(coalesce(v_prod.unidades_por_venta,1),1));
  end loop;
  return v_id;
end;
$function$;

create or replace function public.listar_conteos_inventario()
returns table(conteo_id uuid,estado text,motivo text,creado_en timestamptz,creador uuid,
  total_items bigint,pendientes bigint,aprobados bigint)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not (public.inventario_conteo_tiene_permiso(false) or public.inventario_conteo_tiene_permiso(true)) then
    raise exception 'No tienes permiso para consultar conteos';
  end if;
  return query
  select s.id,s.estado,s.motivo,s.creado_en,s.creado_por,count(i.id),
    count(i.id) filter(where i.estado in ('seleccionado','contando','pendiente_reconteo','pendiente_aprobacion')),
    count(i.id) filter(where i.estado='aprobado')
  from public.inventario_conteos s left join public.inventario_conteos_items i on i.conteo_id=s.id
  group by s.id order by s.creado_en desc limit 100;
end;
$function$;

create or replace function public.consultar_conteo_contador(p_conteo_id uuid)
returns table(item_id uuid,producto_id uuid,codigo text,nombre text,laboratorio text,
  fraccionable boolean,unidades_por_caja integer,unidades_por_venta integer,estado text,
  contador_asignado uuid,mi_captura bigint,capturas_realizadas integer)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not (public.inventario_conteo_tiene_permiso(false) or public.inventario_conteo_tiene_permiso(true)) then
    raise exception 'No tienes permiso para consultar conteos';
  end if;
  return query
  select i.id,i.producto_id,i.codigo_corte,i.nombre_corte,i.laboratorio_corte,i.fraccionable_corte,
    i.unidades_por_caja_corte,i.unidades_por_venta_corte,i.estado,i.contador_asignado_a,
    (select c.cantidad_base from public.inventario_conteo_capturas c
      where c.conteo_item_id=i.id and c.contado_por=auth.uid()),
    (select count(*)::integer from public.inventario_conteo_capturas c where c.conteo_item_id=i.id)
  from public.inventario_conteos_items i
  where i.conteo_id=p_conteo_id;
end;
$function$;

create or replace function public.consultar_conteo_revision(p_conteo_id uuid)
returns table(item_id uuid,producto_id uuid,codigo text,nombre text,estado text,saldo_corte bigint,
  cantidad_confirmada bigint,diferencia numeric,capturas jsonb,contador_asignado uuid)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(true) then
    raise exception 'No tienes permiso para revisar conteos';
  end if;
  return query
  select i.id,i.producto_id,i.codigo_corte,i.nombre_corte,i.estado,
    case when i.estado in ('pendiente_aprobacion','aprobado') then i.saldo_teorico_corte end,
    case when i.estado in ('pendiente_aprobacion','aprobado') then i.cantidad_confirmada_base end,
    case when i.estado in ('pendiente_aprobacion','aprobado') then i.diferencia_base end,
    case when i.estado in ('pendiente_aprobacion','aprobado') then coalesce((select jsonb_agg(jsonb_build_object('numero',c.numero,'cantidad',c.cantidad_base,
      'usuario',c.contado_por,'correo',u.email,'fecha',c.contado_en,'motivo',c.motivo) order by c.numero)
      from public.inventario_conteo_capturas c join auth.users u on u.id=c.contado_por where c.conteo_item_id=i.id),'[]'::jsonb)
      else '[]'::jsonb end,
    i.contador_asignado_a
  from public.inventario_conteos_items i where i.conteo_id=p_conteo_id
    and not exists(select 1 from public.inventario_conteo_capturas c
      where c.conteo_item_id=i.id and c.contado_por=auth.uid());
end;
$function$;

create or replace function public.iniciar_linea_conteo(p_item_id uuid,p_solicitud_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_producto uuid; v_prod public.productos%rowtype; v_item public.inventario_conteos_items%rowtype;
  v_sesion public.inventario_conteos%rowtype; v_saldo bigint;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para contar';
  end if;
  if p_solicitud_id is null then raise exception 'Falta clave de solicitud'; end if;
  select producto_id into v_producto from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea de conteo inexistente'; end if;
  select * into v_prod from public.productos where id=v_producto for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;
  if v_sesion.estado<>'abierto' then raise exception 'La sesión no está abierta'; end if;
  if v_item.inicio_operacion_id is not null then
    if v_item.inicio_operacion_id<>p_solicitud_id or v_item.contador_asignado_a<>auth.uid() then
      raise exception 'La línea ya fue iniciada por otra operación o persona';
    end if;
    return jsonb_build_object('item_id',v_item.id,'estado',v_item.estado,'codigo',v_item.codigo_corte,'nombre',v_item.nombre_corte);
  end if;
  if v_item.estado<>'seleccionado' then raise exception 'La línea no está disponible para iniciar'; end if;
  if exists(select 1 from public.inventario_conteos_bloqueos b where b.producto_id=v_producto) then
    raise exception 'El producto ya está protegido por otro conteo' using errcode='55P03';
  end if;
  select coalesce(sum(m.unidades_delta),0)::bigint into v_saldo
    from public.inventario_movimientos m where m.producto_id=v_producto;
  insert into public.inventario_conteos_bloqueos(producto_id,conteo_item_id,conteo_id,activado_por)
    values(v_producto,v_item.id,v_item.conteo_id,auth.uid());
  update public.inventario_conteos_items set estado='contando',saldo_teorico_corte=v_saldo,
    codigo_corte=v_prod.codigo,nombre_corte=v_prod.nombre,laboratorio_corte=v_prod.laboratorio,
    fraccionable_corte=coalesce(v_prod.fraccionable,false),
    unidades_por_caja_corte=greatest(coalesce(v_prod.unidades_por_caja,1),1),
    unidades_por_venta_corte=greatest(coalesce(v_prod.unidades_por_venta,1),1),
    contador_asignado_a=auth.uid(),inicio_operacion_id=p_solicitud_id
  where id=p_item_id;
  return jsonb_build_object('item_id',p_item_id,'estado','contando','codigo',v_prod.codigo,'nombre',v_prod.nombre,
    'unidades_por_caja',greatest(coalesce(v_prod.unidades_por_caja,1),1),
    'fraccionable',coalesce(v_prod.fraccionable,false));
end;
$function$;

create or replace function public.guardar_conteo_fisico(
  p_item_id uuid,p_cantidad_base bigint,p_solicitud_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_producto uuid; v_item public.inventario_conteos_items%rowtype; v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para registrar conteos';
  end if;
  if p_cantidad_base is null or p_cantidad_base<0 or p_solicitud_id is null then raise exception 'Cantidad o solicitud inválida'; end if;
  select producto_id into v_producto from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;
  perform 1 from public.productos where id=v_producto for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;
  select * into v_c from public.inventario_conteo_capturas where solicitud_id=p_solicitud_id;
  if found then
    if v_c.conteo_item_id<>p_item_id or v_c.cantidad_base<>p_cantidad_base or v_c.contado_por<>auth.uid() then
      raise exception 'Clave de captura reutilizada con otros datos';
    end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado,'guardado',true);
  end if;
  if v_sesion.estado<>'abierto' or v_item.estado<>'contando' or v_item.contador_asignado_a<>auth.uid()
     or not exists(select 1 from public.inventario_conteos_bloqueos b where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está asignada a tu usuario o dejó de estar protegida';
  end if;
  if exists(select 1 from public.inventario_conteo_capturas c where c.conteo_item_id=p_item_id) then
    raise exception 'La primera captura ya existe';
  end if;
  insert into public.inventario_conteo_capturas(conteo_item_id,numero,cantidad_base,contado_por,solicitud_id)
    values(p_item_id,1,p_cantidad_base,auth.uid(),p_solicitud_id);
  update public.inventario_conteos_items set captura_operacion_id=p_solicitud_id where id=p_item_id;
  return jsonb_build_object('item_id',p_item_id,'estado','contando','guardado',true);
end;
$function$;

create or replace function public.enviar_linea_conteo_a_revision(p_item_id uuid,p_solicitud_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_producto uuid; v_item public.inventario_conteos_items%rowtype; v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype; v_estado text;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para enviar conteos';
  end if;
  if p_solicitud_id is null then raise exception 'Falta clave de envío'; end if;
  select producto_id into v_producto from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;
  perform 1 from public.productos where id=v_producto for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;
  if v_item.envio_revision_operacion_id is not null then
    if v_item.envio_revision_operacion_id<>p_solicitud_id then raise exception 'La línea ya fue enviada'; end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado);
  end if;
  if v_sesion.estado<>'abierto' or v_item.estado<>'contando' or v_item.contador_asignado_a<>auth.uid()
     or not exists(select 1 from public.inventario_conteos_bloqueos b where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está lista o no está asignada a tu usuario';
  end if;
  select * into v_c from public.inventario_conteo_capturas where conteo_item_id=p_item_id and numero=1;
  if not found then raise exception 'Guarda la cantidad antes de enviar'; end if;
  if v_c.cantidad_base=v_item.saldo_teorico_corte then
    v_estado:='pendiente_aprobacion';
    update public.inventario_conteos_items set cantidad_confirmada_base=v_c.cantidad_base where id=p_item_id;
  else
    v_estado:='pendiente_reconteo';
  end if;
  update public.inventario_conteos_items set estado=v_estado,envio_revision_operacion_id=p_solicitud_id where id=p_item_id;
  return jsonb_build_object('item_id',p_item_id,'estado',v_estado);
end;
$function$;

create or replace function public.registrar_reconteo_fisico(
  p_item_id uuid,p_cantidad_base bigint,p_solicitud_id uuid,p_motivo text default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_producto uuid; v_item public.inventario_conteos_items%rowtype; v_sesion public.inventario_conteos%rowtype;
  v_c public.inventario_conteo_capturas%rowtype; v_consenso bigint; v_numero integer;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(false) then
    raise exception 'No tienes permiso para recontar';
  end if;
  if p_cantidad_base is null or p_cantidad_base<0 or p_solicitud_id is null then raise exception 'Cantidad o solicitud inválida'; end if;
  select producto_id into v_producto from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;
  perform 1 from public.productos where id=v_producto for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;
  select * into v_c from public.inventario_conteo_capturas where solicitud_id=p_solicitud_id;
  if found then
    if v_c.conteo_item_id<>p_item_id or v_c.cantidad_base<>p_cantidad_base or v_c.contado_por<>auth.uid()
       or v_c.motivo is distinct from nullif(left(btrim(coalesce(p_motivo,'')),500),'') then
      raise exception 'Clave de reconteo reutilizada con otros datos';
    end if;
    return jsonb_build_object('item_id',p_item_id,'estado',v_item.estado,'guardado',true);
  end if;
  if v_sesion.estado<>'abierto' or v_item.estado<>'pendiente_reconteo'
     or not exists(select 1 from public.inventario_conteos_bloqueos b where b.conteo_item_id=p_item_id) then
    raise exception 'La línea no está pendiente de reconteo o dejó de estar protegida';
  end if;
  if exists(select 1 from public.inventario_conteo_capturas c where c.conteo_item_id=p_item_id and c.contado_por=auth.uid()) then
    raise exception 'Cada reconteo debe hacerlo una persona que no haya contado este producto';
  end if;
  select coalesce(max(numero),0)+1 into v_numero from public.inventario_conteo_capturas where conteo_item_id=p_item_id;
  insert into public.inventario_conteo_capturas(conteo_item_id,numero,cantidad_base,contado_por,solicitud_id,motivo)
    values(p_item_id,v_numero,p_cantidad_base,auth.uid(),p_solicitud_id,nullif(left(btrim(coalesce(p_motivo,'')),500),''));
  select cantidad_base into v_consenso from public.inventario_conteo_capturas
    where conteo_item_id=p_item_id group by cantidad_base having count(*)>=2 order by min(numero) limit 1;
  if found then
    update public.inventario_conteos_items set cantidad_confirmada_base=v_consenso,estado='pendiente_aprobacion' where id=p_item_id;
    return jsonb_build_object('item_id',p_item_id,'estado','pendiente_aprobacion','consenso',true);
  end if;
  return jsonb_build_object('item_id',p_item_id,'estado','pendiente_reconteo','consenso',false);
end;
$function$;

create or replace function public.aprobar_linea_conteo(
  p_item_id uuid,p_solicitud_id uuid,p_motivo text
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_producto uuid; v_item public.inventario_conteos_items%rowtype; v_sesion public.inventario_conteos%rowtype;
  v_delta numeric; v_movimiento uuid; v_existing public.inventario_movimientos%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.inventario_conteo_tiene_permiso(true) then
    raise exception 'No tienes permiso para aprobar conteos';
  end if;
  if p_solicitud_id is null or nullif(btrim(p_motivo),'') is null or length(btrim(p_motivo))>500 then raise exception 'Motivo y clave de aprobación son obligatorios'; end if;
  select producto_id into v_producto from public.inventario_conteos_items where id=p_item_id;
  if not found then raise exception 'Línea inexistente'; end if;
  perform 1 from public.productos where id=v_producto for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id;
  select * into v_sesion from public.inventario_conteos where id=v_item.conteo_id for update;
  select * into v_item from public.inventario_conteos_items where id=p_item_id for update;
  if v_item.estado='aprobado' then
    if v_item.operacion_aprobacion_id<>p_solicitud_id or v_item.aprobado_por<>auth.uid()
       or v_item.motivo_aprobacion<>btrim(p_motivo) then raise exception 'La aprobación ya fue registrada con otros datos'; end if;
    return jsonb_build_object('item_id',p_item_id,'estado','aprobado','movimiento_id',v_item.movimiento_id,
      'diferencia',v_item.diferencia_base);
  end if;
  if v_sesion.estado<>'abierto' or v_item.estado<>'pendiente_aprobacion'
     or v_item.cantidad_confirmada_base is null or v_item.saldo_teorico_corte is null then
    raise exception 'La línea no está lista para aprobar';
  end if;
  if exists(select 1 from public.inventario_conteo_capturas c where c.conteo_item_id=p_item_id and c.contado_por=auth.uid()) then
    raise exception 'Quien contó o recontó el producto no puede aprobarlo';
  end if;
  if not exists(select 1 from public.inventario_conteos_bloqueos b where b.conteo_item_id=p_item_id and b.producto_id=v_producto) then
    raise exception 'El producto ya no está protegido por esta sesión';
  end if;
  v_delta:=v_item.cantidad_confirmada_base-v_item.saldo_teorico_corte;
  if v_delta < -2147483648 or v_delta > 2147483647 then raise exception 'La diferencia excede el rango admitido por Kardex'; end if;
  if v_delta<>0 then
    select * into v_existing from public.inventario_movimientos where tipo='ajuste' and referencia_id=p_item_id;
    if found then raise exception 'La línea ya tiene un ajuste Kardex'; end if;
  end if;
  delete from public.inventario_conteos_bloqueos where conteo_item_id=p_item_id;
  update public.inventario_conteos_items set estado='aprobado',aprobado_por=auth.uid(),aprobado_en=now(),
    operacion_aprobacion_id=p_solicitud_id,motivo_aprobacion=btrim(p_motivo)
  where id=p_item_id;
  if v_delta<>0 then
    insert into public.inventario_movimientos(producto_id,tipo,unidades_delta,referencia_id,operacion_id,notas,creado_por)
      values(v_producto,'ajuste',v_delta::integer,p_item_id,p_solicitud_id,
        left('Conteo físico: '||v_sesion.motivo||' | Aprobación: '||btrim(p_motivo),500),auth.uid())
      returning id into v_movimiento;
    update public.inventario_conteos_items set movimiento_id=v_movimiento where id=p_item_id;
  end if;
  if not exists(select 1 from public.inventario_conteos_items i where i.conteo_id=v_sesion.id and i.estado not in ('aprobado','cancelado')) then
    update public.inventario_conteos set estado='cerrado',cerrado_por=auth.uid(),cerrado_en=now() where id=v_sesion.id;
  end if;
  return jsonb_build_object('item_id',p_item_id,'estado','aprobado','movimiento_id',v_movimiento,'diferencia',v_delta);
end;
$function$;

create or replace function public.cancelar_conteo_inventario(
  p_conteo_id uuid,p_solicitud_id uuid,p_motivo text
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_bloqueo record; v_sesion public.inventario_conteos%rowtype;
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.es_admin_drosalud() then
    raise exception 'Solo administración puede cancelar un conteo';
  end if;
  if p_solicitud_id is null or nullif(btrim(p_motivo),'') is null or length(btrim(p_motivo))>500 then raise exception 'Motivo y clave de cancelación son obligatorios'; end if;
  for v_bloqueo in select b.producto_id from public.inventario_conteos_bloqueos b
      where b.conteo_id=p_conteo_id order by b.producto_id
  loop
    perform 1 from public.productos p where p.id=v_bloqueo.producto_id for update;
  end loop;
  select * into v_sesion from public.inventario_conteos where id=p_conteo_id for update;
  if not found then raise exception 'Conteo inexistente'; end if;
  if v_sesion.estado='cancelado' then
    if v_sesion.solicitud_cancelacion_id<>p_solicitud_id or v_sesion.cancelado_por<>auth.uid()
       or v_sesion.motivo_cancelacion<>btrim(p_motivo) then raise exception 'Cancelación ya registrada con otros datos'; end if;
    return jsonb_build_object('conteo_id',p_conteo_id,'estado','cancelado');
  end if;
  if v_sesion.estado<>'abierto' then raise exception 'La sesión ya está cerrada'; end if;
  delete from public.inventario_conteos_bloqueos where conteo_id=p_conteo_id;
  update public.inventario_conteos_items set estado='cancelado'
    where conteo_id=p_conteo_id and estado<>'aprobado';
  update public.inventario_conteos set estado='cancelado',cancelado_por=auth.uid(),cancelado_en=now(),
    motivo_cancelacion=left(btrim(p_motivo),500),solicitud_cancelacion_id=p_solicitud_id
  where id=p_conteo_id;
  return jsonb_build_object('conteo_id',p_conteo_id,'estado','cancelado');
end;
$function$;

create or replace function public.gestionar_permiso_conteo(
  p_usuario uuid,p_puede_contar boolean,p_puede_aprobar boolean
) returns void language plpgsql security definer set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud() or not public.es_admin_drosalud() then raise exception 'Solo administración puede cambiar permisos'; end if;
  if p_usuario is null or p_puede_contar is null or p_puede_aprobar is null then raise exception 'Usuario y capacidades son obligatorios'; end if;
  if not exists(select 1 from public.usuarios_drosalud where user_id=p_usuario and activo=true) then raise exception 'El usuario objetivo no está activo en Drosalud'; end if;
  if exists(select 1 from public.inventario_conteo_permisos where user_id=p_usuario and revocado_en is null
    and puede_contar=p_puede_contar and puede_aprobar=p_puede_aprobar) then return; end if;
  update public.inventario_conteo_permisos set revocado_por=auth.uid(),revocado_en=now()
    where user_id=p_usuario and revocado_en is null;
  if p_puede_contar or p_puede_aprobar then
    insert into public.inventario_conteo_permisos(user_id,puede_contar,puede_aprobar,otorgado_por)
      values(p_usuario,p_puede_contar,p_puede_aprobar,auth.uid());
  end if;
end;
$function$;

revoke all on function public.consultar_capacidades_conteo() from public,anon,authenticated;
revoke all on function public.crear_conteo_inventario(uuid[],text,uuid) from public,anon,authenticated;
revoke all on function public.listar_conteos_inventario() from public,anon,authenticated;
revoke all on function public.consultar_conteo_contador(uuid) from public,anon,authenticated;
revoke all on function public.consultar_conteo_revision(uuid) from public,anon,authenticated;
revoke all on function public.iniciar_linea_conteo(uuid,uuid) from public,anon,authenticated;
revoke all on function public.guardar_conteo_fisico(uuid,bigint,uuid) from public,anon,authenticated;
revoke all on function public.enviar_linea_conteo_a_revision(uuid,uuid) from public,anon,authenticated;
revoke all on function public.registrar_reconteo_fisico(uuid,bigint,uuid,text) from public,anon,authenticated;
revoke all on function public.aprobar_linea_conteo(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.cancelar_conteo_inventario(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.gestionar_permiso_conteo(uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.consultar_capacidades_conteo(),public.crear_conteo_inventario(uuid[],text,uuid),
  public.listar_conteos_inventario(),public.consultar_conteo_contador(uuid),public.consultar_conteo_revision(uuid),
  public.iniciar_linea_conteo(uuid,uuid),public.guardar_conteo_fisico(uuid,bigint,uuid),
  public.enviar_linea_conteo_a_revision(uuid,uuid),public.registrar_reconteo_fisico(uuid,bigint,uuid,text),
  public.aprobar_linea_conteo(uuid,uuid,text),public.cancelar_conteo_inventario(uuid,uuid,text),
  public.gestionar_permiso_conteo(uuid,boolean,boolean) to authenticated;

commit;

