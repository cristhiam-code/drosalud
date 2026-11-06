-- =====================================================================
-- DROSalud · Cierre de caja por jornada (gastos + cierres)
-- Ruta sugerida en el repo: docs/seguridad/20261105_cierre_caja_jornada.sql
--
-- ESTADO: YA APLICADO en produccion (proyecto Supabase "catalogo") el 2026-11-05
--         como migracion "cierre_caja_jornada", tras 19 pruebas OK en una
--         transaccion revertida. Este archivo es el registro versionado.
--         NO ejecutar de nuevo en produccion (las tablas ya existen).
--
-- Reglas:
--  * Una jornada = un dia con ventas o gastos, con hora de Colombia.
--  * Las ventas anuladas no cuentan.
--  * No se puede cerrar si hay ventas sin forma de pago.
--  * Jornada cerrada = bloqueada. Solo el administrador con verificacion en dos
--    pasos (aal2) puede reabrirla o anular un gasto.
--  * Nadie borra gastos ni cierres. Las tablas solo se leen; se escribe por funciones.
-- =====================================================================

begin;

create or replace function public.hoy_colombia_drosalud()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Bogota')::date
$$;

create table public.gastos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  concepto text not null check (char_length(btrim(concepto)) between 1 and 120),
  categoria text check (categoria is null or char_length(categoria) <= 40),
  monto numeric(14,2) not null check (monto > 0),
  forma_pago text not null check (forma_pago in ('Efectivo','Transferencia','Nequi','Tarjeta')),
  creado_por uuid not null default auth.uid(),
  creado_en timestamptz not null default now(),
  anulado boolean not null default false,
  anulado_por uuid,
  anulado_en timestamptz,
  motivo_anulacion text
);
create index gastos_fecha_idx on public.gastos (fecha);

create table public.cierres_caja (
  id uuid primary key default gen_random_uuid(),
  fecha date not null unique,
  base_inicial numeric(14,2) not null check (base_inicial >= 0),
  ventas_efectivo numeric(14,2) not null,
  ventas_total numeric(14,2) not null,
  ventas_por_forma jsonb not null default '{}'::jsonb,
  gastos_efectivo numeric(14,2) not null,
  gastos_total numeric(14,2) not null,
  efectivo_esperado numeric(14,2) not null,
  efectivo_contado numeric(14,2) not null check (efectivo_contado >= 0),
  diferencia numeric(14,2) not null,
  notas text check (notas is null or char_length(notas) <= 500),
  estado text not null default 'cerrada' check (estado in ('cerrada','reabierta')),
  cerrado_por uuid not null default auth.uid(),
  cerrado_en timestamptz not null default now(),
  reabierto_por uuid,
  reabierto_en timestamptz,
  motivo_reapertura text
);

-- Seguridad: solo lectura directa para el personal; sin acceso anonimo.
alter table public.gastos enable row level security;
alter table public.cierres_caja enable row level security;
revoke all on public.gastos, public.cierres_caja from anon, authenticated;
grant select on public.gastos, public.cierres_caja to authenticated;
create policy gastos_lectura on public.gastos for select to authenticated using (public.es_usuario_drosalud());
create policy cierres_lectura on public.cierres_caja for select to authenticated using (public.es_usuario_drosalud());

-- Resumen de una jornada (lo que muestra la pantalla Caja). No incluye ganancias ni costos.
create or replace function public.resumen_caja_drosalud(p_fecha date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_fecha date := coalesce(p_fecha, public.hoy_colombia_drosalud());
  v_forma jsonb; v_total numeric; v_ef numeric;
  v_sin_n int; v_sin_t numeric; v_nrec int;
  v_gef numeric; v_gtot numeric; v_ng int;
  v_c public.cierres_caja;
begin
  if not public.es_usuario_drosalud() then raise exception 'Sin permiso'; end if;

  select coalesce(jsonb_object_agg(fp, t), '{}'::jsonb), coalesce(sum(t), 0)
    into v_forma, v_total
    from (select nullif(btrim(r.forma_pago), '') as fp, sum(r.total) as t
            from public.recibos r
           where not coalesce(r.anulado, false)
             and nullif(btrim(r.forma_pago), '') is not null
             and (r.creado_en at time zone 'America/Bogota')::date = v_fecha
           group by 1) x;

  select count(*), coalesce(sum(r.total), 0) into v_sin_n, v_sin_t
    from public.recibos r
   where not coalesce(r.anulado, false)
     and nullif(btrim(r.forma_pago), '') is null
     and (r.creado_en at time zone 'America/Bogota')::date = v_fecha;

  select count(*) into v_nrec
    from public.recibos r
   where not coalesce(r.anulado, false)
     and (r.creado_en at time zone 'America/Bogota')::date = v_fecha;

  v_ef := coalesce((v_forma ->> 'Efectivo')::numeric, 0);

  select count(*), coalesce(sum(g.monto) filter (where g.forma_pago = 'Efectivo'), 0), coalesce(sum(g.monto), 0)
    into v_ng, v_gef, v_gtot
    from public.gastos g where g.fecha = v_fecha and not g.anulado;

  select * into v_c from public.cierres_caja c where c.fecha = v_fecha;

  return jsonb_build_object(
    'fecha', v_fecha,
    'estado', coalesce(v_c.estado, 'abierta'),
    'recibos', v_nrec,
    'ventas_por_forma', v_forma,
    'ventas_efectivo', v_ef,
    'ventas_total', v_total + v_sin_t,
    'sin_forma_n', v_sin_n,
    'sin_forma_total', v_sin_t,
    'gastos_n', v_ng,
    'gastos_efectivo', v_gef,
    'gastos_total', v_gtot,
    'cierre', case when v_c.id is null then null else to_jsonb(v_c) end,
    'cambios_despues_del_cierre', (v_c.id is not null and v_c.estado = 'cerrada'
        and (v_c.ventas_efectivo is distinct from v_ef
          or v_c.ventas_total is distinct from (v_total + v_sin_t)
          or v_c.gastos_efectivo is distinct from v_gef))
  );
end $$;

-- Registrar un gasto (no se puede en una jornada cerrada ni en fecha futura)
create or replace function public.registrar_gasto_drosalud(p_fecha date, p_concepto text, p_monto numeric, p_forma_pago text, p_categoria text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_fecha date := coalesce(p_fecha, public.hoy_colombia_drosalud()); v_id uuid;
begin
  if not public.es_usuario_drosalud() then raise exception 'Sin permiso'; end if;
  if v_fecha > public.hoy_colombia_drosalud() then raise exception 'La fecha no puede ser futura'; end if;
  if exists (select 1 from public.cierres_caja c where c.fecha = v_fecha and c.estado = 'cerrada') then
    raise exception 'La jornada del % ya está cerrada', v_fecha;
  end if;
  insert into public.gastos(fecha, concepto, categoria, monto, forma_pago)
  values (v_fecha, btrim(p_concepto), nullif(btrim(p_categoria), ''), p_monto, p_forma_pago)
  returning id into v_id;
  return v_id;
end $$;

-- Cerrar la jornada: los totales los calcula el servidor, no la pantalla
create or replace function public.cerrar_caja_drosalud(p_fecha date, p_base numeric, p_contado numeric, p_notas text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_fecha date := coalesce(p_fecha, public.hoy_colombia_drosalud()); r jsonb; v_est text; v_esp numeric;
begin
  if not public.es_usuario_drosalud() then raise exception 'Sin permiso'; end if;
  if v_fecha > public.hoy_colombia_drosalud() then raise exception 'La fecha no puede ser futura'; end if;
  if p_base is null or p_base < 0 or p_contado is null or p_contado < 0 then
    raise exception 'Escribe la base y el efectivo contado (no pueden ser negativos)';
  end if;
  select c.estado into v_est from public.cierres_caja c where c.fecha = v_fecha;
  if v_est = 'cerrada' then raise exception 'La jornada del % ya está cerrada', v_fecha; end if;

  r := public.resumen_caja_drosalud(v_fecha);
  if (r ->> 'sin_forma_n')::int > 0 then
    raise exception 'Hay % venta(s) sin forma de pago. Corrígelas antes de cerrar.', r ->> 'sin_forma_n';
  end if;
  if (r ->> 'recibos')::int = 0 and (r ->> 'gastos_n')::int = 0 then
    raise exception 'No hay ventas ni gastos en esa jornada';
  end if;

  v_esp := p_base + (r ->> 'ventas_efectivo')::numeric - (r ->> 'gastos_efectivo')::numeric;

  if v_est is null then
    insert into public.cierres_caja(fecha, base_inicial, ventas_efectivo, ventas_total, ventas_por_forma,
                                    gastos_efectivo, gastos_total, efectivo_esperado, efectivo_contado, diferencia, notas)
    values (v_fecha, p_base, (r ->> 'ventas_efectivo')::numeric, (r ->> 'ventas_total')::numeric, r -> 'ventas_por_forma',
            (r ->> 'gastos_efectivo')::numeric, (r ->> 'gastos_total')::numeric, v_esp, p_contado, p_contado - v_esp,
            nullif(btrim(p_notas), ''));
  else
    update public.cierres_caja
       set base_inicial = p_base, ventas_efectivo = (r ->> 'ventas_efectivo')::numeric,
           ventas_total = (r ->> 'ventas_total')::numeric, ventas_por_forma = r -> 'ventas_por_forma',
           gastos_efectivo = (r ->> 'gastos_efectivo')::numeric, gastos_total = (r ->> 'gastos_total')::numeric,
           efectivo_esperado = v_esp, efectivo_contado = p_contado, diferencia = p_contado - v_esp,
           notas = nullif(btrim(p_notas), ''), estado = 'cerrada', cerrado_por = auth.uid(), cerrado_en = now()
     where fecha = v_fecha;
  end if;
  return public.resumen_caja_drosalud(v_fecha);
end $$;

-- Reabrir una jornada cerrada: solo administrador con verificacion en dos pasos
create or replace function public.reabrir_caja_drosalud(p_fecha date, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_drosalud() or coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'Solo el administrador con verificación en dos pasos puede reabrir una jornada';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo de la reapertura (mínimo 5 caracteres)';
  end if;
  update public.cierres_caja
     set estado = 'reabierta', reabierto_por = auth.uid(), reabierto_en = now(), motivo_reapertura = btrim(p_motivo)
   where fecha = p_fecha and estado = 'cerrada';
  if not found then raise exception 'No hay una jornada cerrada en esa fecha'; end if;
end $$;

-- Anular un gasto mal registrado: solo administrador con verificacion en dos pasos
create or replace function public.anular_gasto_drosalud(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_fecha date;
begin
  if not public.es_admin_drosalud() or coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'Solo el administrador con verificación en dos pasos puede anular un gasto';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Escribe el motivo de la anulación (mínimo 5 caracteres)';
  end if;
  select g.fecha into v_fecha from public.gastos g where g.id = p_id and not g.anulado;
  if v_fecha is null then raise exception 'Gasto no encontrado o ya anulado'; end if;
  if exists (select 1 from public.cierres_caja c where c.fecha = v_fecha and c.estado = 'cerrada') then
    raise exception 'La jornada del % está cerrada. Reábrela primero.', v_fecha;
  end if;
  update public.gastos set anulado = true, anulado_por = auth.uid(), anulado_en = now(), motivo_anulacion = btrim(p_motivo)
   where id = p_id;
end $$;

-- Jornadas con movimiento y sin cierre (para la etiqueta "sin cerrar" del boton Caja)
create or replace function public.jornadas_pendientes_drosalud()
returns table(fecha date, ventas integer, gastos integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_usuario_drosalud() then raise exception 'Sin permiso'; end if;
  return query
  with mov as (
    select (r.creado_en at time zone 'America/Bogota')::date as f, 1 as v, 0 as g
      from public.recibos r where not coalesce(r.anulado, false)
    union all
    select x.fecha, 0, 1 from public.gastos x where not x.anulado
  )
  select m.f, sum(m.v)::int, sum(m.g)::int
    from mov m
   where m.f <= public.hoy_colombia_drosalud()
     and not exists (select 1 from public.cierres_caja c where c.fecha = m.f and c.estado = 'cerrada')
   group by m.f order by m.f desc limit 60;
end $$;

-- Permisos de ejecucion: solo usuarios con sesion
revoke execute on function public.hoy_colombia_drosalud(), public.resumen_caja_drosalud(date),
  public.registrar_gasto_drosalud(date, text, numeric, text, text), public.cerrar_caja_drosalud(date, numeric, numeric, text),
  public.reabrir_caja_drosalud(date, text), public.anular_gasto_drosalud(uuid, text), public.jornadas_pendientes_drosalud()
  from public, anon;
grant execute on function public.hoy_colombia_drosalud(), public.resumen_caja_drosalud(date),
  public.registrar_gasto_drosalud(date, text, numeric, text, text), public.cerrar_caja_drosalud(date, numeric, numeric, text),
  public.reabrir_caja_drosalud(date, text), public.anular_gasto_drosalud(uuid, text), public.jornadas_pendientes_drosalud()
  to authenticated;

commit;

-- =====================================================================
-- ROLLBACK (solo antes de que existan cierres reales):
--   drop function if exists public.jornadas_pendientes_drosalud(), public.anular_gasto_drosalud(uuid, text),
--     public.reabrir_caja_drosalud(date, text), public.cerrar_caja_drosalud(date, numeric, numeric, text),
--     public.registrar_gasto_drosalud(date, text, numeric, text, text), public.resumen_caja_drosalud(date),
--     public.hoy_colombia_drosalud();
--   drop table if exists public.cierres_caja;
--   drop table if exists public.gastos;
-- =====================================================================
