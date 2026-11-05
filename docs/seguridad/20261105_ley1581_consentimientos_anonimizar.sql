-- =====================================================================
-- DROSalud · Ley 1581 de 2012: consentimientos de clientes y anonimizacion
-- Ruta sugerida en el repo: docs/seguridad/20261105_ley1581_consentimientos_anonimizar.sql
--
-- ESTADO: YA APLICADO en produccion (proyecto Supabase "catalogo") el 2026-11-05
-- como migracion "ley1581_consentimientos_y_anonimizar".
-- Este archivo es el registro versionado. Esta escrito para poder correrse
-- otra vez sin duplicar nada (por ejemplo, en un proyecto de pruebas).
-- NO ejecutar en produccion de nuevo: no hace falta.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabla de consentimientos
--    Guarda quien autorizo, cuando, con que version del texto y por que canal.
--    cliente_id queda en NULL si el cliente se borra: se conserva la prueba de
--    que hubo autorizacion, sin guardar la identidad.
-- ---------------------------------------------------------------------
create table if not exists public.consentimientos_clientes (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid references public.clientes(id) on delete set null,
  version_texto text not null,
  aceptado boolean not null default true,
  aceptado_en timestamptz not null default now(),
  canal text not null default 'mostrador',
  registrado_por uuid not null default auth.uid()
);

alter table public.consentimientos_clientes enable row level security;

-- Sin acceso anonimo; usuarios con sesion solo leen e insertan.
-- No hay politica de UPDATE ni DELETE: un consentimiento registrado no se altera.
revoke all on public.consentimientos_clientes from anon, authenticated;
grant select, insert on public.consentimientos_clientes to authenticated;

drop policy if exists consent_lectura on public.consentimientos_clientes;
create policy consent_lectura on public.consentimientos_clientes
  for select to authenticated
  using (public.es_usuario_drosalud());

drop policy if exists consent_alta on public.consentimientos_clientes;
create policy consent_alta on public.consentimientos_clientes
  for insert to authenticated
  with check (public.es_usuario_drosalud() and registrado_por = auth.uid());

-- ---------------------------------------------------------------------
-- 2. Anonimizar un cliente (solo administrador con verificacion en dos pasos)
--    Borra nombre, cedula, telefono y direccion en clientes, y la copia de esos
--    datos en recibos y cotizaciones. Los recibos se conservan (soporte contable).
--    Deja constancia de la solicitud sin guardar la identidad.
-- ---------------------------------------------------------------------
create or replace function public.anonimizar_cliente_drosalud(p_cliente_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Accion irreversible: exige administrador Y sesion verificada en dos pasos (aal2)
  if not public.es_admin_drosalud()
     or coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'Solo el administrador con verificación en dos pasos puede anonimizar clientes';
  end if;

  update public.clientes
     set nombre = 'Cliente anonimizado', telefono = null, cedula = null, direccion = null
   where id = p_cliente_id;
  if not found then raise exception 'Cliente no encontrado'; end if;

  update public.recibos
     set cliente_nombre = 'Cliente anonimizado', cliente_cedula = null,
         cliente_telefono = null, cliente_direccion = null
   where cliente_id = p_cliente_id;

  update public.cotizaciones_venta
     set cliente_nombre = 'Cliente anonimizado', cliente_cedula = null,
         cliente_telefono = null
   where cliente_id = p_cliente_id;

  insert into public.consentimientos_clientes(cliente_id, version_texto, aceptado, canal)
  values (p_cliente_id, 'anonimizado', false, 'solicitud del titular');
end
$$;

revoke execute on function public.anonimizar_cliente_drosalud(uuid) from public, anon;
grant execute on function public.anonimizar_cliente_drosalud(uuid) to authenticated;

-- =====================================================================
-- VERIFICACION (solo lectura):
--   select relname, relrowsecurity from pg_class
--    where relname = 'consentimientos_clientes';
--   select policyname, cmd from pg_policies
--    where tablename = 'consentimientos_clientes';
--
-- ROLLBACK (solo si hiciera falta, y antes de que existan consentimientos reales):
--   drop function if exists public.anonimizar_cliente_drosalud(uuid);
--   drop table if exists public.consentimientos_clientes;
-- =====================================================================
