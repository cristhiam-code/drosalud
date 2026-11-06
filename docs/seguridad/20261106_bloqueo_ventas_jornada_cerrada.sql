-- DROSALUD
-- Bloqueo de ventas y detalles en jornadas cerradas.
-- Aplicar una sola vez. No reemplaza el SQL original de cierre.

-- 1. Función central: bloquea la fecha durante la transacción
--    y rechaza operaciones si la jornada está cerrada.
CREATE OR REPLACE FUNCTION public.validar_jornada_abierta_drosalud(
  p_fecha date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NOT public.es_usuario_drosalud() THEN
    RAISE EXCEPTION 'Usuario no autorizado';
  END IF;

  IF p_fecha IS NULL THEN
    RAISE EXCEPTION 'No se pudo determinar la fecha de la venta';
  END IF;

  -- El mismo bloqueo se usa al cerrar la caja.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    20261106,
    (p_fecha - DATE '2000-01-01')::integer
  );

  IF EXISTS (
    SELECT 1
    FROM public.cierres_caja c
    WHERE c.fecha = p_fecha
      AND c.estado = 'cerrada'
  ) THEN
    RAISE EXCEPTION
      'La jornada del % está cerrada. Solicita al administrador que la reabra.',
      p_fecha;
  END IF;
END;
$$;


-- 2. Protección de recibos: INSERT, UPDATE y DELETE.
CREATE OR REPLACE FUNCTION public.trg_proteger_recibos_jornada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_fecha_old date;
  v_fecha_new date;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_fecha_old :=
      (OLD.creado_en AT TIME ZONE 'America/Bogota')::date;

    PERFORM public.validar_jornada_abierta_drosalud(v_fecha_old);
  END IF;

  IF TG_OP <> 'DELETE' THEN
    v_fecha_new :=
      (NEW.creado_en AT TIME ZONE 'America/Bogota')::date;

    IF TG_OP = 'INSERT' OR v_fecha_new IS DISTINCT FROM v_fecha_old THEN
      PERFORM public.validar_jornada_abierta_drosalud(v_fecha_new);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_recibos_jornada
ON public.recibos;

CREATE TRIGGER trg_proteger_recibos_jornada
BEFORE INSERT OR UPDATE OR DELETE
ON public.recibos
FOR EACH ROW
EXECUTE FUNCTION public.trg_proteger_recibos_jornada();


-- 3. Protección de los artículos asociados a cada recibo.
CREATE OR REPLACE FUNCTION public.trg_proteger_items_jornada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_recibo_old uuid;
  v_recibo_new uuid;
  v_fecha_old date;
  v_fecha_new date;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_recibo_old := OLD.recibo_id;

    SELECT (r.creado_en AT TIME ZONE 'America/Bogota')::date
      INTO v_fecha_old
    FROM public.recibos r
    WHERE r.id = v_recibo_old;

    IF v_fecha_old IS NULL THEN
      RAISE EXCEPTION 'No se encontró la venta original';
    END IF;

    PERFORM public.validar_jornada_abierta_drosalud(v_fecha_old);
  END IF;

  IF TG_OP <> 'DELETE' THEN
    v_recibo_new := NEW.recibo_id;

    SELECT (r.creado_en AT TIME ZONE 'America/Bogota')::date
      INTO v_fecha_new
    FROM public.recibos r
    WHERE r.id = v_recibo_new;

    IF v_fecha_new IS NULL THEN
      RAISE EXCEPTION 'No se encontró la venta asociada';
    END IF;

    IF TG_OP = 'INSERT'
       OR v_recibo_new IS DISTINCT FROM v_recibo_old THEN
      PERFORM public.validar_jornada_abierta_drosalud(v_fecha_new);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_items_jornada
ON public.recibo_items;

CREATE TRIGGER trg_proteger_items_jornada
BEFORE INSERT OR UPDATE OR DELETE
ON public.recibo_items
FOR EACH ROW
EXECUTE FUNCTION public.trg_proteger_items_jornada();


-- 4. Actualizar el cierre para usar el mismo bloqueo transaccional.
CREATE OR REPLACE FUNCTION public.cerrar_caja_drosalud(
  p_fecha date,
  p_base numeric,
  p_contado numeric,
  p_notas text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_fecha date := COALESCE(p_fecha, public.hoy_colombia_drosalud());
  r jsonb;
  v_est text;
  v_esp numeric;
BEGIN
  IF NOT public.es_usuario_drosalud() THEN
    RAISE EXCEPTION 'Sin permiso';
  END IF;

  -- Sincroniza el cierre con cualquier venta concurrente.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    20261106,
    (v_fecha - DATE '2000-01-01')::integer
  );

  IF v_fecha > public.hoy_colombia_drosalud() THEN
    RAISE EXCEPTION 'La fecha no puede ser futura';
  END IF;

  IF p_base IS NULL OR p_base < 0
     OR p_contado IS NULL OR p_contado < 0 THEN
    RAISE EXCEPTION
      'Escribe la base y el efectivo contado (no pueden ser negativos)';
  END IF;

  SELECT c.estado INTO v_est
  FROM public.cierres_caja c
  WHERE c.fecha = v_fecha;

  IF v_est = 'cerrada' THEN
    RAISE EXCEPTION 'La jornada del % ya está cerrada', v_fecha;
  END IF;

  r := public.resumen_caja_drosalud(v_fecha);

  IF (r ->> 'sin_forma_n')::int > 0 THEN
    RAISE EXCEPTION
      'Hay % venta(s) sin forma de pago. Corrígelas antes de cerrar.',
      r ->> 'sin_forma_n';
  END IF;

  IF (r ->> 'recibos')::int = 0
     AND (r ->> 'gastos_n')::int = 0 THEN
    RAISE EXCEPTION 'No hay ventas ni gastos en esa jornada';
  END IF;

  v_esp :=
    p_base
    + (r ->> 'ventas_efectivo')::numeric
    - (r ->> 'gastos_efectivo')::numeric;

  IF v_est IS NULL THEN
    INSERT INTO public.cierres_caja(
      fecha, base_inicial, ventas_efectivo, ventas_total,
      ventas_por_forma, gastos_efectivo, gastos_total,
      efectivo_esperado, efectivo_contado, diferencia, notas
    )
    VALUES (
      v_fecha, p_base,
      (r ->> 'ventas_efectivo')::numeric,
      (r ->> 'ventas_total')::numeric,
      r -> 'ventas_por_forma',
      (r ->> 'gastos_efectivo')::numeric,
      (r ->> 'gastos_total')::numeric,
      v_esp, p_contado, p_contado - v_esp,
      NULLIF(BTRIM(p_notas), '')
    );
  ELSE
    UPDATE public.cierres_caja
    SET base_inicial = p_base,
        ventas_efectivo = (r ->> 'ventas_efectivo')::numeric,
        ventas_total = (r ->> 'ventas_total')::numeric,
        ventas_por_forma = r -> 'ventas_por_forma',
        gastos_efectivo = (r ->> 'gastos_efectivo')::numeric,
        gastos_total = (r ->> 'gastos_total')::numeric,
        efectivo_esperado = v_esp,
        efectivo_contado = p_contado,
        diferencia = p_contado - v_esp,
        notas = NULLIF(BTRIM(p_notas), ''),
        estado = 'cerrada',
        cerrado_por = auth.uid(),
        cerrado_en = now()
    WHERE fecha = v_fecha;
  END IF;

  RETURN public.resumen_caja_drosalud(v_fecha);
END;
$$;


-- 5. Evitar ejecución directa de la función auxiliar.
REVOKE ALL ON FUNCTION
  public.validar_jornada_abierta_drosalud(date)
FROM PUBLIC, anon, authenticated;

-- Los triggers ejecutan las funciones de protección internamente.
REVOKE ALL ON FUNCTION
  public.trg_proteger_recibos_jornada()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION
  public.trg_proteger_items_jornada()
FROM PUBLIC, anon, authenticated;
