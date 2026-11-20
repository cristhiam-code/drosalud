-- Retirar la selección y exposición de ubicaciones del contrato de lectura.
-- La referencia técnica permanece únicamente en las relaciones internas de QA.
begin;

drop function public.listar_conteos_inventario();
create function public.listar_conteos_inventario()
returns table(
  conteo_id uuid,
  estado text,
  motivo text,
  creado_en timestamptz,
  creador uuid,
  total_items bigint,
  pendientes bigint,
  aprobados bigint
)
language plpgsql
stable
security definer
set search_path=''
as $function$
begin
  if auth.uid() is null or not public.es_usuario_drosalud()
     or not (public.inventario_conteo_tiene_permiso(false)
       or public.inventario_conteo_tiene_permiso(true)) then
    raise exception 'No tienes permiso para consultar conteos';
  end if;

  return query
  select s.id,s.estado,s.motivo,s.creado_en,s.creado_por,
    count(i.id),
    count(i.id) filter(where i.estado in
      ('seleccionado','contando','pendiente_reconteo','pendiente_aprobacion')),
    count(i.id) filter(where i.estado='aprobado')
  from public.inventario_conteos s
  left join public.inventario_conteos_items i on i.conteo_id=s.id
  group by s.id
  order by s.creado_en desc
  limit 100;
end;
$function$;

revoke all on function public.listar_conteos_inventario() from public,anon,authenticated;
grant execute on function public.listar_conteos_inventario() to authenticated;

-- Esta RPC ya no forma parte del flujo de un único punto de venta.
revoke all on function public.listar_bodegas_conteo() from public,anon,authenticated;

notify pgrst, 'reload schema';
commit;