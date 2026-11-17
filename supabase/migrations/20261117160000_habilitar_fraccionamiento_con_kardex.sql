-- Drosalud · Habilitar fraccionamiento en productos con historial
-- Convierte el saldo vigente de empaques a unidades individuales mediante un
-- movimiento de ajuste. Los movimientos históricos y recibos no se modifican.
begin;

create or replace function public.proteger_presentacion_con_movimientos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.inventario_movimientos im
    where im.producto_id = old.id
  ) then
    if new.codigo is distinct from old.codigo then
      raise exception
        'Este producto ya tiene movimientos en el Kardex. El codigo no se puede cambiar.'
        using errcode = '23514';
    end if;

    if new.unidades_por_caja is distinct from old.unidades_por_caja
       and not (
         old.fraccionable = false
         and new.fraccionable = true
         and coalesce(current_setting('drosalud.habilitar_fraccionamiento', true), '') = 'on'
       ) then
      raise exception
        'Este producto ya tiene movimientos en el Kardex. La equivalencia de la caja no se puede cambiar.'
        using errcode = '23514';
    end if;

    if new.fraccionable is distinct from old.fraccionable
       and not (
         old.fraccionable = false
         and new.fraccionable = true
         and coalesce(current_setting('drosalud.habilitar_fraccionamiento', true), '') = 'on'
       ) then
      raise exception
        'Este producto ya tiene movimientos en el Kardex. Use la activacion controlada del fraccionamiento.'
        using errcode = '23514';
    end if;
  end if;

  -- unidades_por_venta solo define el incremento mínimo de venta.
  -- Cada recibo conserva su propio factor histórico, por eso puede ajustarse.
  return new;
end;
$$;

drop trigger if exists trg_proteger_presentacion_con_movimientos on public.productos;
create trigger trg_proteger_presentacion_con_movimientos
before update of codigo, fraccionable, unidades_por_caja, unidades_por_venta
on public.productos
for each row
execute function public.proteger_presentacion_con_movimientos();

revoke all on function public.proteger_presentacion_con_movimientos() from public, anon, authenticated;

create or replace function public.habilitar_fraccionamiento_producto(
  p_producto_id uuid,
  p_unidades_por_caja integer,
  p_unidades_por_venta integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_producto public.productos%rowtype;
  v_saldo bigint;
  v_ajuste bigint;
begin
  if auth.uid() is null or not public.es_admin_drosalud() then
    raise exception 'Solo el administrador puede habilitar el fraccionamiento de un producto.';
  end if;

  if p_producto_id is null
     or p_unidades_por_caja is null
     or p_unidades_por_caja <= 1
     or p_unidades_por_venta is null
     or p_unidades_por_venta < 1
     or p_unidades_por_venta > p_unidades_por_caja then
    raise exception 'Revisa las unidades de la caja y las unidades por venta.';
  end if;

  select *
    into v_producto
  from public.productos
  where id = p_producto_id
  for update;

  if not found then
    raise exception 'No se encontró el producto.';
  end if;

  if v_producto.fraccionable then
    if v_producto.unidades_por_caja = p_unidades_por_caja
       and v_producto.unidades_por_venta = p_unidades_por_venta then
      return jsonb_build_object(
        'ok', true, 'changed', false,
        'saldo_anterior', null, 'ajuste', 0, 'saldo_nuevo', null
      );
    end if;
    raise exception 'Este producto ya tiene una presentación fraccionable. Para cambiar la equivalencia, registre otro código.';
  end if;

  if v_producto.unidades_por_caja <> 1
     or v_producto.unidades_por_venta <> 1 then
    raise exception 'La presentación actual no tiene una equivalencia inicial de una unidad. Requiere revisión antes de fraccionarse.';
  end if;

  select coalesce(sum(im.unidades_delta), 0)::bigint
    into v_saldo
  from public.inventario_movimientos im
  where im.producto_id = p_producto_id;

  -- Hasta ahora cada movimiento representaba un empaque completo.
  -- Al habilitar el fraccionamiento, el saldo pasa a expresarse en unidades.
  v_ajuste := v_saldo * (p_unidades_por_caja - 1);

  if v_ajuste < -2147483648 or v_ajuste > 2147483647 then
    raise exception 'El saldo es demasiado grande para convertirlo automáticamente. Solicita revisión.';
  end if;

  if v_ajuste <> 0 then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, notas, creado_por)
    values
      (
        p_producto_id,
        'ajuste',
        v_ajuste::integer,
        format(
          'Conversión controlada de presentación: %s empaques × %s unidades por empaque. Ajuste de %s unidades; el historial anterior se conserva.',
          v_saldo, p_unidades_por_caja, v_ajuste
        ),
        auth.uid()
      );
  end if;

  perform set_config('drosalud.habilitar_fraccionamiento', 'on', true);

  update public.productos
  set fraccionable = true,
      unidades_por_caja = p_unidades_por_caja,
      unidades_por_venta = p_unidades_por_venta,
      actualizado_en = now()
  where id = p_producto_id;

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'saldo_anterior', v_saldo,
    'factor', p_unidades_por_caja,
    'ajuste', v_ajuste,
    'saldo_nuevo', v_saldo + v_ajuste
  );
end;
$$;

revoke all on function public.habilitar_fraccionamiento_producto(uuid, integer, integer) from public, anon;
grant execute on function public.habilitar_fraccionamiento_producto(uuid, integer, integer) to authenticated;

commit;
