-- Drosalud · Cerrar ejecución anónima de funciones privilegiadas
-- Las funciones SECURITY DEFINER del esquema expuesto no deben ser invocables por anon.
-- Las llamadas legítimas de la aplicación quedan disponibles para authenticated.
begin;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', f.signature);
  end loop;
end;
$$;

-- Helpers usados por políticas RLS y por las operaciones de la aplicación.
grant execute on function public.es_usuario_drosalud() to authenticated;
grant execute on function public.es_admin_drosalud() to authenticated;
grant execute on function public.es_recibo_propio_drosalud(uuid) to authenticated;

-- RPC expuestas intencionalmente a usuarios autenticados.
grant execute on function public.actualizar_precio_venta_drosalud(uuid,numeric) to authenticated;
grant execute on function public.actualizar_precios_drosalud(uuid,numeric,numeric) to authenticated;
grant execute on function public.anonimizar_cliente_drosalud(uuid) to authenticated;
grant execute on function public.anular_gasto_drosalud(uuid,text) to authenticated;
grant execute on function public.cerrar_caja_drosalud(date,numeric,numeric,text) to authenticated;
grant execute on function public.crear_cotizacion_venta_drosalud(jsonb,jsonb) to authenticated;
grant execute on function public.guardar_compra_con_costo_real(uuid,text,integer,uuid,numeric,text,text,uuid,uuid,numeric) to authenticated;
grant execute on function public.jornadas_pendientes_drosalud() to authenticated;
grant execute on function public.reabrir_caja_drosalud(date,text) to authenticated;
grant execute on function public.registrar_gasto_drosalud(date,text,numeric,text,text) to authenticated;
grant execute on function public.registrar_venta_drosalud(jsonb,jsonb) to authenticated;
grant execute on function public.resumen_caja_drosalud(date) to authenticated;
grant execute on function public.registrar_recepcion_inventario(uuid,integer,text,uuid) to authenticated;

commit;
