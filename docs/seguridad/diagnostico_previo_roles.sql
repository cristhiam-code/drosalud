-- Drosalud: diagnóstico previo para terminar la migración de roles.
-- SOLO CONSULTAS: se puede ejecutar en SQL Editor en un proyecto de PRUEBAS.
-- No crea, modifica ni elimina objetos ni datos.

-- 1) Políticas actuales de todas las tablas implicadas.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = any (array[
    'ajustes','clientes','compras_pendientes','cotizacion_venta_items',
    'cotizaciones_proveedor','cotizaciones_venta','historial_precios',
    'productos','proveedores','recibo_items','recibos','usuarios_drosalud'
  ])
order by tablename, policyname;

-- 2) Columnas reales: no asumir nombres/tipos que no estén en la base.
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = any (array[
    'ajustes','clientes','compras_pendientes','cotizacion_venta_items',
    'cotizaciones_proveedor','cotizaciones_venta','historial_precios',
    'productos','proveedores','recibo_items','recibos'
  ])
order by table_name, ordinal_position;

-- 3) Firmas, modo de seguridad y definiciones de RPC relevantes.
select
  p.oid::regprocedure as firma,
  p.prosecdef as security_definer,
  p.proconfig as configuracion,
  pg_get_functiondef(p.oid) as definicion
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = any (array[
    'guardar_compra_con_costo_real','mas_vendidos',
    'es_usuario_drosalud','es_admin_drosalud'
  ])
order by p.proname, p.oid;

-- 4) Privilegios de tabla y columna concedidos a roles API.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = any (array[
    'ajustes','clientes','compras_pendientes','cotizacion_venta_items',
    'cotizaciones_proveedor','cotizaciones_venta','historial_precios',
    'productos','proveedores','recibo_items','recibos'
  ])
  and grantee in ('anon','authenticated','service_role')
order by table_name, grantee, privilege_type;

-- 5) Verificar existencia de usuario administrador en Auth (solo email/ID).
select id, email, created_at
from auth.users
where lower(email) = lower('boterocristhiam@gmail.com');
