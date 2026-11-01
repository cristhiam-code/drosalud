-- Drosalud: diagnóstico de permisos y firmas antes de aplicar roles.
-- Solo lectura: no crea, modifica ni elimina objetos.
-- Ejecutar en SQL Editor de un entorno de pruebas y revisar los resultados.

-- 1) Políticas RLS existentes: detectar políticas antiguas permisivas.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = any (array[
    'ajustes','clientes','compras_pendientes','cotizacion_venta_items',
    'cotizaciones_proveedor','cotizaciones_venta','historial_precios',
    'productos','proveedores','recibo_items','recibos','usuarios_drosalud'
  ])
order by tablename, policyname;

-- 2) Privilegios de tabla y columna para anon/authenticated.
-- Es especialmente importante comprobar productos.precio_compra y recibo_items.
select table_name, grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and grantee in ('anon','authenticated')
  and table_name = any (array[
    'ajustes','clientes','productos','recibos','recibo_items',
    'cotizaciones_venta','cotizacion_venta_items'
  ])
order by table_name, grantee, privilege_type;

select table_name, column_name, grantee, privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and grantee in ('anon','authenticated')
  and (
    (table_name = 'productos' and column_name in ('precio_compra','precio_venta'))
    or (table_name = 'recibo_items' and column_name in ('precio_compra','costo_real_unitario'))
  )
order by table_name, column_name, grantee, privilege_type;

-- 3) Firmas y nivel de seguridad de las funciones que usa la app.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  p.prosecdef as security_definer,
  p.proconfig as function_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('guardar_compra_con_costo_real','mas_vendidos','log_precio_compra','actualizar_fecha_compras')
order by p.proname;

-- 4) Estructura de columnas relevante para diseñar lectura segura de catálogo
-- y para identificar el campo que atribuye cada venta.
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = any (array['productos','recibos','recibo_items','ajustes'])
order by table_name, ordinal_position;

-- 5) Verificar si ya existe el usuario administrador en Supabase Auth.
-- Esta consulta puede ejecutarse solo desde el SQL Editor con acceso a auth.users.
select id, email, created_at
from auth.users
where lower(email) = lower('boterocristhiam@gmail.com');
