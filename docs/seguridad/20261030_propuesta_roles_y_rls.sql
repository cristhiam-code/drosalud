-- Drosalud: primera propuesta de aislamiento y roles.
-- IMPORTANTE: archivo de revisión. NO ejecutar en producción hasta validar
-- el flujo completo y respaldar la base de datos.
--
-- Modelo: una droguería compartida, usuarios individuales.
-- Administrador: boterocristhiam@gmail.com
-- Vendedor: puede consultar catálogo/clientes y registrar sus ventas/cotizaciones.
-- Vendedor NO puede editar catálogo, modificar costos/precios, anular/eliminar recibos
-- ni modificar ajustes o compras.

begin;

-- 1) Roles internos vinculados a cuentas reales de Supabase Auth.
create table if not exists public.usuarios_drosalud (
  user_id uuid primary key references auth.users(id) on delete cascade,
  rol text not null check (rol in ('admin', 'vendedor')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

alter table public.usuarios_drosalud enable row level security;

-- Comprueba que la cuenta está autorizada para usar Drosalud.
create or replace function public.es_usuario_drosalud()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1
    from public.usuarios_drosalud u
    where u.user_id = (select auth.uid())
      and u.activo = true
  );
$;

revoke all on function public.es_usuario_drosalud() from public;
grant execute on function public.es_usuario_drosalud() to authenticated;

-- Función pequeña para consultar el rol sin exponer la tabla de roles.
create or replace function public.es_admin_drosalud()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios_drosalud u
    where u.user_id = (select auth.uid())
      and u.rol = 'admin'
      and u.activo = true
  );
$$;

revoke all on function public.es_admin_drosalud() from public;
grant execute on function public.es_admin_drosalud() to authenticated;

drop policy if exists "usuario ve su propio rol" on public.usuarios_drosalud;
create policy "usuario ve su propio rol"
on public.usuarios_drosalud for select
to authenticated
using (user_id = (select auth.uid()) or public.es_admin_drosalud());

-- Solo el administrador podrá gestionar roles desde una interfaz administrativa
-- futura. No se concede INSERT/UPDATE/DELETE a vendedores.

-- 2) Registrar la cuenta administradora existente. No crea cuentas ni contraseñas.
insert into public.usuarios_drosalud (user_id, rol, activo)
select id, 'admin', true
from auth.users
where lower(email) = lower('boterocristhiam@gmail.com')
on conflict (user_id) do update
set rol = 'admin', activo = true;

-- 3) Productos: lectura compartida; escritura exclusiva del administrador.
drop policy if exists "solo con sesion" on public.productos;
create policy "usuarios autenticados consultan productos"
on public.productos for select to authenticated using (public.es_usuario_drosalud());
create policy "admin gestiona productos"
on public.productos for all to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());

-- 4) Clientes: lectura compartida y alta desde ventas; cambios estructurales admin.
drop policy if exists "solo con sesion" on public.clientes;
create policy "usuarios autenticados consultan clientes"
on public.clientes for select to authenticated using (public.es_usuario_drosalud());
create policy "usuarios autenticados crean clientes"
on public.clientes for insert to authenticated with check (public.es_usuario_drosalud());
create policy "admin modifica clientes"
on public.clientes for update to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());
create policy "admin elimina clientes"
on public.clientes for delete to authenticated
using (public.es_admin_drosalud());

-- 5) Recibos: guardar quién registró cada venta.
alter table public.recibos
  add column if not exists creado_por uuid references auth.users(id);

alter table public.recibos
  alter column creado_por set default auth.uid();

-- Los recibos históricos quedan con creado_por NULL y siguen visibles al admin.
drop policy if exists "solo con sesion" on public.recibos;
create policy "admin ve todos los recibos y vendedor los propios"
on public.recibos for select to authenticated
using (public.es_usuario_drosalud() and (public.es_admin_drosalud() or creado_por = (select auth.uid())));
create policy "usuario registra su recibo"
on public.recibos for insert to authenticated
with check (public.es_usuario_drosalud() and creado_por = (select auth.uid()));
create policy "solo admin modifica recibos"
on public.recibos for update to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());
create policy "solo admin elimina recibos"
on public.recibos for delete to authenticated
using (public.es_admin_drosalud());

-- 6) Detalles de recibo: heredan permisos del recibo padre.
drop policy if exists "solo con sesion" on public.recibo_items;
create policy "usuario consulta items de recibos permitidos"
on public.recibo_items for select to authenticated
using (
  exists (
    select 1 from public.recibos r
    where r.id = recibo_items.recibo_id
      and public.es_usuario_drosalud() and (public.es_admin_drosalud() or r.creado_por = (select auth.uid()))
  )
);
create policy "usuario agrega items a su recibo"
on public.recibo_items for insert to authenticated
with check (
  exists (
    select 1 from public.recibos r
    where r.id = recibo_items.recibo_id
      and (public.es_admin_drosalud() or r.creado_por = (select auth.uid()))
  )
);
create policy "solo admin modifica items"
on public.recibo_items for update to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());
create policy "solo admin elimina items"
on public.recibo_items for delete to authenticated
using (public.es_admin_drosalud());

-- 7) Ajustes e historial de costos: solo administrador.
drop policy if exists "solo con sesion" on public.ajustes;
create policy "solo admin gestiona ajustes"
on public.ajustes for all to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());

drop policy if exists "solo con sesion" on public.historial_precios;
create policy "solo admin consulta historial de precios"
on public.historial_precios for select to authenticated
using (public.es_admin_drosalud());
create policy "solo admin administra historial de precios"
on public.historial_precios for all to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());

-- 8) Compras y proveedores: solo administrador (contienen costos/proveedores).
drop policy if exists "propietario gestiona compras" on public.compras_pendientes;
create policy "solo admin gestiona compras"
on public.compras_pendientes for all to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());

drop policy if exists "propietario gestiona proveedores" on public.proveedores;
create policy "solo admin gestiona proveedores"
on public.proveedores for all to authenticated
using (public.es_admin_drosalud())
with check (public.es_admin_drosalud());

-- 9) Las cotizaciones también requieren una cuenta activa.
drop policy if exists "solo con sesion" on public.cotizaciones_venta;
drop policy if exists "propietario gestiona cotizaciones" on public.cotizaciones_venta;
create policy "usuario activo gestiona sus cotizaciones"
on public.cotizaciones_venta for all to authenticated
using (public.es_usuario_drosalud() and owner_id = (select auth.uid()))
with check (public.es_usuario_drosalud() and owner_id = (select auth.uid()));

drop policy if exists "solo con sesion" on public.cotizacion_venta_items;
drop policy if exists "usuario activo gestiona items de sus cotizaciones" on public.cotizacion_venta_items;
create policy "usuario activo gestiona items de sus cotizaciones"
on public.cotizacion_venta_items for all to authenticated
using (
  public.es_usuario_drosalud() and exists (
    select 1 from public.cotizaciones_venta c
    where c.id = cotizacion_venta_items.cotizacion_id
      and c.owner_id = (select auth.uid())
  )
)
with check (
  public.es_usuario_drosalud() and exists (
    select 1 from public.cotizaciones_venta c
    where c.id = cotizacion_venta_items.cotizacion_id
      and c.owner_id = (select auth.uid())
  )
);

-- 10) El RPC de más vendidos solo se usa con sesión; RLS limita sus filas
-- según el usuario y el rol. La versión SECURITY INVOKER no eleva privilegios.
revoke all on function public.mas_vendidos(integer) from public, anon;
grant execute on function public.mas_vendidos(integer) to authenticated;

-- 11) La función de costo real es SECURITY INVOKER. Sus UPDATE quedan
-- protegidos por las políticas admin-only de recibos e items; además,
-- solo cuentas autenticadas pueden invocarla.
revoke all on function public.guardar_compra_con_costo_real(uuid,text,numeric,uuid,numeric,text,text,uuid,uuid,numeric) from public, anon;
grant execute on function public.guardar_compra_con_costo_real(uuid,text,numeric,uuid,numeric,text,text,uuid,uuid,numeric) to authenticated;

-- La función de guardar costo real requiere un control de rol dentro de su cuerpo.
-- No se modifica aquí: debe reemplazarse conservando exactamente su implementación
-- y agregando al inicio:
--   if not public.es_admin_drosalud() then
--     raise exception 'Solo el administrador puede registrar costos reales.';
--   end if;
-- Después de reemplazarla, revocar EXECUTE a anon/public y concederlo solo a authenticated.

commit;

-- VALIDACIONES POSTERIORES (ejecutar después de aplicar en entorno de prueba):
-- 1) Comprobar que existe exactamente un admin activo y que cada vendedor está activo.
-- 2) Crear vendedor desde Supabase Auth y asignarle rol vendedor manualmente.
-- 3) Probar: vendedor puede insertar recibo y sus items, no puede cambiar productos,
--    actualizar/eliminar recibos, consultar recibos ajenos ni acceder a ajustes.
-- 4) Probar que el administrador conserva acceso a todo el histórico.
