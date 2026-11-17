-- Endurece dos funciones y los permisos de la vista de pedidos.
-- No cambia la lógica de ventas, inventario, pedidos ni los permisos operativos del equipo.

-- Esta función solo debe ejecutarse mediante sus triggers.
ALTER FUNCTION public.actualizar_fecha_compras()
  SET search_path = pg_catalog;

REVOKE ALL ON FUNCTION public.actualizar_fecha_compras()
  FROM PUBLIC, anon, authenticated, service_role;

-- La consulta de más vendidos usa objetos con esquema explícito.
-- Se fija el esquema de búsqueda y se conserva su uso por el equipo autenticado.
ALTER FUNCTION public.mas_vendidos(integer)
  SET search_path = pg_catalog;

REVOKE ALL ON FUNCTION public.mas_vendidos(integer)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.mas_vendidos(integer)
  TO authenticated, service_role;

-- La vista es de consulta; el equipo autenticado solo necesita SELECT.
-- security_invoker=true mantiene vigentes las políticas de las tablas base.
REVOKE ALL PRIVILEGES ON TABLE public.pedidos_resumen
  FROM anon, authenticated;

GRANT SELECT ON TABLE public.pedidos_resumen
  TO authenticated;
