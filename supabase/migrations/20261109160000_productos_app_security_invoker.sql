-- La vista debe respetar las politicas RLS del usuario que consulta.
-- La tabla productos ya tiene politicas de lectura para usuarios Drosalud.
alter view public.productos_app set (security_invoker = true);
