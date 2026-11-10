-- Drosalud · Restringir alta de productos al administrador
-- La interfaz del vendedor no permite crear productos; RLS debe imponer la misma regla.
-- La política productos_solo_admin_escritura ya cubre INSERT para administradores.
begin;
drop policy if exists productos_insertar_usuario_activo on public.productos;
commit;
