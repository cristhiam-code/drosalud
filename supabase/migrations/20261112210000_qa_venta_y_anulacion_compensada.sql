ALTER TABLE public.inventario_movimientos
  DROP CONSTRAINT IF EXISTS inventario_movimientos_tipo_check;

ALTER TABLE public.inventario_movimientos
  ADD CONSTRAINT inventario_movimientos_tipo_check
  CHECK (tipo = ANY (ARRAY[
    'venta'::text,
    'anulacion'::text,
    'recepcion'::text,
    'saldo_inicial'::text,
    'ajuste'::text
  ]));

CREATE OR REPLACE FUNCTION public.fn_inventario_descuenta_venta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if new.producto_id is not null then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    values
      (new.producto_id, 'venta', -new.cantidad, new.id,
       'Descuento automático por recibo (cantidad en unidades base)', auth.uid())
    on conflict (tipo, referencia_id)
      where referencia_id is not null and tipo in ('venta','anulacion')
    do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_inventario_revierte_anulacion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if coalesce(old.anulado, false) = false and new.anulado is true then
    insert into public.inventario_movimientos
      (producto_id, tipo, unidades_delta, referencia_id, notas, creado_por)
    select
      ri.producto_id,
      'anulacion',
      -(
        venta.unidades_delta
        + coalesce((
          select sum(a.unidades_delta)
          from public.inventario_movimientos a
          where a.tipo = 'ajuste'
            and a.referencia_id = venta.id
        ), 0)
      ),
      ri.id,
      'Reversión automática por anulación del recibo ' || new.numero::text,
      auth.uid()
    from public.recibo_items ri
    join public.inventario_movimientos venta
      on venta.tipo = 'venta'
     and venta.referencia_id = ri.id
     and venta.producto_id = ri.producto_id
     and venta.unidades_delta < 0
    where ri.recibo_id = new.id
      and ri.producto_id is not null
    on conflict (tipo, referencia_id)
      where referencia_id is not null and tipo in ('venta','anulacion')
    do nothing;
  end if;
  return new;
end;
$function$;

DO $verify$
DECLARE
  v_tipo_check text;
BEGIN
  SELECT pg_get_constraintdef(oid)
    INTO v_tipo_check
  FROM pg_constraint
  WHERE conrelid = 'public.inventario_movimientos'::regclass
    AND conname = 'inventario_movimientos_tipo_check';

  IF v_tipo_check IS DISTINCT FROM
    'CHECK ((tipo = ANY (ARRAY[''venta''::text, ''anulacion''::text, ''recepcion''::text, ''saldo_inicial''::text, ''ajuste''::text])))'
  THEN
    RAISE EXCEPTION 'CHECK de tipo no coincide con definición aprobada: %', v_tipo_check;
  END IF;

  IF (SELECT prosecdef FROM pg_proc WHERE oid =
      'public.fn_inventario_descuenta_venta()'::regprocedure) IS DISTINCT FROM true
     OR (SELECT prosecdef FROM pg_proc WHERE oid =
      'public.fn_inventario_revierte_anulacion()'::regprocedure) IS DISTINCT FROM true
     OR (SELECT proconfig FROM pg_proc WHERE oid =
      'public.fn_inventario_descuenta_venta()'::regprocedure) IS DISTINCT FROM ARRAY['search_path=""']
     OR (SELECT proconfig FROM pg_proc WHERE oid =
      'public.fn_inventario_revierte_anulacion()'::regprocedure) IS DISTINCT FROM ARRAY['search_path=""']
  THEN
    RAISE EXCEPTION 'Propiedades SECURITY DEFINER/search_path no verificadas';
  END IF;
END;
$verify$;