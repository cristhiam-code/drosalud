-- BORRADOR DE PROPUESTA. NO EJECUTAR NI APLICAR.
-- No es una migración registrada por Supabase CLI y no se ha probado contra QA.
-- Revisar definición real del esquema, permisos y funciones antes de convertir
-- este borrador en una migración versionada.

begin;

-- La restricción inline de la migración 20261109120000 se llama normalmente
-- inventario_movimientos_tipo_check. Confirmar el nombre en el esquema QA antes
-- de usar este bloque en una migración real.
alter table public.inventario_movimientos
  drop constraint if exists inventario_movimientos_tipo_check;

alter table public.inventario_movimientos
  add constraint inventario_movimientos_tipo_check
  check (tipo in ('venta','anulacion','recepcion','ajuste'));

-- Un ajuste queda asociado a una sola línea de conteo y su operación no se
-- puede repetir. Prevalidar datos existentes antes de crear índices únicos.
create unique index if not exists inventario_movimientos_ajuste_referencia_unica_idx
  on public.inventario_movimientos(tipo, referencia_id)
  where tipo = 'ajuste' and referencia_id is not null;

create unique index if not exists inventario_movimientos_ajuste_operacion_unica_idx
  on public.inventario_movimientos(operacion_id)
  where tipo = 'ajuste' and operacion_id is not null;

create table public.inventario_conteos (
  id uuid primary key default gen_random_uuid(),
  solicitud_creacion_id uuid not null unique,
  solicitud_creacion_hash text not null,
  estado text not null default 'abierto'
    check (estado in ('abierto','cerrado','cancelado')),
  motivo text not null,
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  cerrado_por uuid references auth.users(id),
  cerrado_en timestamptz,
  cancelado_por uuid references auth.users(id),
  cancelado_en timestamptz,
  motivo_cancelacion text,
  solicitud_cancelacion_id uuid unique,
  check (
    (estado = 'cerrado' and cerrado_por is not null and cerrado_en is not null)
    or estado <> 'cerrado'
  ),
  check (
    (estado = 'cancelado' and cancelado_por is not null
      and cancelado_en is not null and motivo_cancelacion is not null)
    or estado <> 'cancelado'
  )
);

create table public.inventario_conteos_items (
  id uuid primary key default gen_random_uuid(),
  conteo_id uuid not null references public.inventario_conteos(id) on delete restrict,
  producto_id uuid not null references public.productos(id) on delete restrict,
  estado text not null default 'seleccionado'
    check (estado in ('seleccionado','contando','pendiente_reconteo',
      'pendiente_aprobacion','aprobado','cancelado')),
  codigo_corte text,
  nombre_corte text not null,
  fraccionable_corte boolean not null,
  unidades_por_caja_corte integer not null check (unidades_por_caja_corte > 0),
  unidades_por_venta_corte integer not null check (unidades_por_venta_corte > 0),
  saldo_teorico_corte bigint,
  cantidad_confirmada_base bigint,
  diferencia_base bigint generated always as
    (cantidad_confirmada_base - saldo_teorico_corte) stored,
  contador_asignado_a uuid references auth.users(id),
  inicio_operacion_id uuid unique,
  captura_operacion_id uuid unique,
  envio_revision_operacion_id uuid unique,
  aprobado_por uuid references auth.users(id),
  aprobado_en timestamptz,
  operacion_aprobacion_id uuid,
  motivo_aprobacion text,
  movimiento_id uuid references public.inventario_movimientos(id) on delete restrict,
  unique (conteo_id, producto_id),
  unique (id, conteo_id),
  unique (id, conteo_id, producto_id),
  unique (operacion_aprobacion_id),
  check (cantidad_confirmada_base is null or cantidad_confirmada_base >= 0),
  check (estado <> 'pendiente_aprobacion' or
    (saldo_teorico_corte is not null and cantidad_confirmada_base is not null)),
  check (estado <> 'aprobado' or
    (aprobado_por is not null and aprobado_en is not null)),
  check (aprobado_por is null or cantidad_confirmada_base is not null)
);

-- Cada conteo queda como evento inmutable; permite segundo, tercero y posteriores
-- sin sobrescribir la evidencia anterior. La cantidad se guarda en unidad base.
create table public.inventario_conteo_capturas (
  id uuid primary key default gen_random_uuid(),
  conteo_item_id uuid not null references public.inventario_conteos_items(id) on delete restrict,
  numero integer not null check (numero > 0),
  cantidad_base bigint not null check (cantidad_base >= 0),
  contado_por uuid not null references auth.users(id),
  solicitud_id uuid not null unique,
  motivo text,
  contado_en timestamptz not null default now(),
  unique (conteo_item_id, numero),
  unique (conteo_item_id, contado_por)
);

create table public.inventario_conteos_bloqueos (
  producto_id uuid primary key references public.productos(id) on delete restrict,
  conteo_item_id uuid not null unique,
  conteo_id uuid not null,
  activado_por uuid not null references auth.users(id),
  activado_en timestamptz not null default now(),
  foreign key (conteo_item_id, conteo_id, producto_id)
    references public.inventario_conteos_items(id, conteo_id, producto_id) on delete restrict
);

create table public.inventario_conteo_permisos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  puede_contar boolean not null default false,
  puede_aprobar boolean not null default false,
  otorgado_por uuid not null references auth.users(id),
  otorgado_en timestamptz not null default now(),
  revocado_por uuid references auth.users(id),
  revocado_en timestamptz,
  check (puede_contar or puede_aprobar),
  check ((revocado_por is null) = (revocado_en is null))
);

create unique index inventario_conteo_permisos_usuario_activo_idx
  on public.inventario_conteo_permisos(user_id)
  where revocado_en is null;

create index inventario_conteos_items_producto_estado_idx
  on public.inventario_conteos_items(producto_id, estado);
create index inventario_conteos_items_sesion_estado_idx
  on public.inventario_conteos_items(conteo_id, estado);

alter table public.inventario_conteos enable row level security;
alter table public.inventario_conteos_items enable row level security;
alter table public.inventario_conteo_capturas enable row level security;
alter table public.inventario_conteos_bloqueos enable row level security;
alter table public.inventario_conteo_permisos enable row level security;

-- Sin políticas ni DML directo desde navegador. RPC específicas deben validar
-- capacidad y devolver campos distintos a contador y aprobador.
revoke all on public.inventario_conteos,
  public.inventario_conteos_items,
  public.inventario_conteo_capturas,
  public.inventario_conteos_bloqueos,
  public.inventario_conteo_permisos
from public, anon, authenticated;

create or replace function public.inventario_conteo_tiene_permiso(p_aprobar boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and public.es_usuario_drosalud()
    and (
      public.es_admin_drosalud()
      or exists (
        select 1
        from public.inventario_conteo_permisos p
        where p.user_id = auth.uid()
          and p.revocado_en is null
          and case when p_aprobar then p.puede_aprobar else p.puede_contar end
      )
    );
$function$;

revoke all on function public.inventario_conteo_tiene_permiso(boolean)
  from public, anon, authenticated;

create or replace function public.proteger_movimiento_durante_conteo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- El inicio de línea y todos los movimientos serializan sobre la misma fila.
  perform 1 from public.productos p
  where p.id = new.producto_id
  for update;

  if not found then
    raise exception 'Producto inexistente para movimiento de inventario';
  end if;

  if exists (
    select 1 from public.inventario_conteos_bloqueos b
    where b.producto_id = new.producto_id
  ) then
    raise exception 'Producto bloqueado por conteo físico. Reintenta cuando el conteo termine.'
      using errcode = '55P03';
  end if;

  return new;
end;
$function$;

revoke all on function public.proteger_movimiento_durante_conteo()
  from public, anon, authenticated;

create trigger trg_bloquear_movimiento_durante_conteo
before insert on public.inventario_movimientos
for each row execute function public.proteger_movimiento_durante_conteo();

create or replace function public.proteger_presentacion_durante_conteo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if exists (
    select 1 from public.inventario_conteos_bloqueos b
    where b.producto_id = old.id
  ) then
    raise exception 'No se puede cambiar la presentación durante un conteo físico.'
      using errcode = '55P03';
  end if;
  return new;
end;
$function$;

revoke all on function public.proteger_presentacion_durante_conteo()
  from public, anon, authenticated;

create trigger trg_bloquear_presentacion_durante_conteo
before update of codigo, fraccionable, unidades_por_caja, unidades_por_venta
on public.productos
for each row execute function public.proteger_presentacion_durante_conteo();

-- CONTRATO TÉCNICO DE RPC PARA CONVERTIR A MIGRACIÓN (NO ES SQL EJECUTABLE).
-- Las firmas siguientes son contratos, no CREATE FUNCTION listos: faltan
-- confirmar en QA columnas/FKs de productos y usuarios, y la función real de
-- recepción que no está disponible en el repositorio.
--
-- crear_conteo_inventario(p_productos uuid[], p_motivo text,
--                         p_solicitud_id uuid) -> uuid
-- * Admin o capacidad puede_contar; requiere motivo y lista no vacía, IDs
--   existentes y únicos. Hash estable de (UUIDs ordenados, motivo normalizado)
--   permite reintento con la misma solicitud; misma clave y payload distinto
--   se rechaza. Crea cabecera/items en una transacción, sin tomar bloqueos de
--   producto hasta iniciar cada línea.
--
-- iniciar_linea_conteo(p_item_id uuid, p_solicitud_id uuid) -> jsonb
-- * Usuario activo con puede_contar. Lee el producto del item, bloquea primero
--   productos FOR UPDATE y luego item; revalida sesión/item seleccionados y
--   ausencia de otro bloqueo. En esa transacción toma snapshot y saldo como
--   SUM(inventario_movimientos.unidades_delta) bajo el bloqueo, crea el
--   marcador único, asigna contador y pasa a contando. Idempotente por solicitud
--   y item. Respuesta ciega: identidad/código/unidad, nunca saldo ni diferencia.
-- * Un saldo negativo existente se captura tal cual; no se bloquea la creación
--   del conteo por saldo negativo. Validar límite bigint y límites reales del
--   Kardex integer antes de producir un ajuste.
--
-- guardar_conteo_fisico(p_item_id uuid, p_cantidad_base bigint,
--                       p_solicitud_id uuid) -> jsonb
-- * Requiere cantidad >= 0, usuario igual a contador_asignado_a, item contando
--   y marcador vigente. Orden de bloqueo: producto, sesión y línea. Guarda la
--   captura inicial inmutable (número 1); permanece contando hasta el envío.
--   Reintento idéntico devuelve el mismo resultado; clave repetida con cantidad
--   distinta se rechaza. Nunca devuelve saldo teórico/diferencia.
--
-- enviar_linea_conteo_a_revision(p_item_id uuid, p_solicitud_id uuid) -> jsonb
-- * El contador asignado confirma la captura; estado contando, captura 1 y
--   bloqueo vigente son obligatorios. Si la cantidad es igual al saldo teórico,
--   fija cantidad_confirmada_base y pasa a pendiente_aprobacion. Si existe
--   cualquier diferencia (positiva o negativa), pasa a pendiente_reconteo y no
--   permite aprobar aún. Persiste solicitud; reintento no reevalúa datos nuevos.
--
-- registrar_reconteo_fisico(p_item_id uuid, p_cantidad_base bigint,
--                            p_solicitud_id uuid, p_motivo text default null)
-- -> jsonb
-- * Solo contador autorizado, distinto de todos los anteriores; requiere
--   pendiente_reconteo y bloqueo vigente. La pantalla de este contador no
--   muestra saldo teórico, primer conteo ni conteos anteriores. Cada llamada
--   agrega evento inmutable con número siguiente; no actualiza capturas previas.
-- * Regla operativa cerrada: toda diferencia con el teórico exige reconteo ciego
--   por persona distinta. En capturas (1..N), cuando dos personas distintas
--   registran la misma cantidad, esa cantidad se confirma y la línea pasa a
--   pendiente_aprobacion. Si los valores difieren, permanece pendiente_reconteo
--   y se solicita otro conteo ciego a otra persona. No se promedian cantidades.
--   Si no se logra concordancia, admin puede cancelar con motivo; no hay ajuste.
-- * La cantidad confirmada es un valor con al menos dos capturas independientes.
--   La aprobación valida el consenso y excluye a todos esos contadores.
--
-- consultar_conteo_contador(p_conteo_id uuid) -> set de columnas ciegas
-- * Solo creador/contador asignado/admin con permiso de conteo. No seleccionar
--   saldo_teorico_corte ni diferencia_base en esta ruta.
-- consultar_conteo_revision(p_conteo_id uuid) -> set de columnas de revisión
-- * Solo admin o puede_aprobar; devuelve snapshot, saldo, cantidad y delta.
--   La autorización se comprueba en cada llamada; no confiar en ocultar campos
--   en JavaScript.
--
-- aprobar_linea_conteo(p_item_id uuid, p_solicitud_id uuid,
--                      p_motivo text) -> jsonb
-- * Admin o puede_aprobar; requiere auth.uid() distinto de todos los usuarios
--   de inventario_conteo_capturas y estado pendiente_aprobacion. Bloquea producto,
--   sesión y luego item, valida que el marcador
--   siga apuntando al item y congela operación/actor/motivo con la solicitud.
-- * Calcula delta = cantidad_confirmada_base - saldo_teorico_corte. Si delta=0,
--   marca aprobado y libera, sin insertar movimiento. Si distinto de cero,
--   libera el marcador e inserta, dentro de la misma transacción, un solo
--   movimiento tipo ajuste, referencia_id=item.id, operacion_id=solicitud UUID,
--   unidades_delta=delta, usuario=auth.uid(), nota con motivo de sesión y
--   autorización. Guarda movimiento_id y estado aprobado. Un reintento idéntico
--   retorna el resultado persistido; cualquier payload/actor diferente se
--   rechaza. Índices únicos por item/operación son última defensa. Un error
--   revierte ajuste, estado y liberación conjuntamente.
-- * Antes del INSERT, la RPC cambia la línea a aprobado dentro de su transacción.
--   El trigger central admite ajuste con referencia no nula solo si esa línea
--   aprobada corresponde a la llamada autorizada, mismo producto/delta,
--   solicitud y aprobador distinto de todos los contadores. ajuste con referencia NULL
--   debe seguir permitido para no romper habilitar_fraccionamiento_producto,
--   que ya existe y no se modifica en esta propuesta. Las escrituras directas
--   a inventario_movimientos siguen revocadas a clientes.
-- * Al aprobar la última línea no cancelada, cerrar la sesión con actor/fecha.
--   Si se cancela la sesión, las líneas aprobadas conservan estado y movimientos;
--   solo las pendientes se marcan canceladas y se liberan.
--
-- cancelar_conteo_inventario(p_conteo_id uuid, p_solicitud_id uuid, p_motivo text) -> jsonb
-- * Solo admin en v1. Toma IDs de producto de bloqueos ordenados por UUID y
--   bloquea filas productos en ese mismo orden; luego bloquea sesión/items.
--   Libera solo marcadores de items no aprobados y los marca cancelados. Las
--   líneas aprobadas y movimientos nunca se borran. Cancelación repetida con
--   misma clave/payload devuelve resultado; motivo/clave diferentes se
--   rechazan. No hay liberación automática por timeout: una sesión abandonada
--   requiere cancelación auditada por admin.
--
-- gestionar_permiso_conteo(p_usuario uuid, p_puede_contar boolean,
--                          p_puede_aprobar boolean) -> void
-- * Solo admin; validar usuario Drosalud activo. No se actualiza historial:
--   insertar concesión o revocar la concesión activa (revocado_por/en) y crear
--   otra fila. Índice parcial permite una concesión activa por usuario. Revocar
--   permiso no cancela una línea que ya está contando.
--
-- SEGURIDAD/IMPLEMENTACIÓN: funciones privilegiadas SECURITY DEFINER con
-- search_path vacío y objetos calificados; comprobar auth.uid(), usuario activo
-- y capacidad dentro de cada RPC. REVOKE EXECUTE FROM PUBLIC, anon; GRANT solo
-- authenticated. Tablas sin DML directo y RLS activado. Las lecturas separadas
-- contador/revisión son obligatorias para no filtrar existencias.
--
-- CONCURRENCIA: no mantener transacciones abiertas durante conteo humano. Inicio,
-- captura, aprobación y cancelación son transacciones cortas. Toda ruta conocida
-- que modifique saldo inserta inventario_movimientos y queda cubierta por el
-- trigger BEFORE INSERT; el trigger toma el mismo lock de producto y falla con
-- 55P03 si hay marcador. Venta/anulación/recepción quedan revertidas por
-- atomicidad si falla el trigger. El guard de presentación cubre cambios del
-- fraccionamiento aunque delta sea cero. La recepción manual está demostrada
-- en la migración local. La recepción de compra delega a un RPC cuyo cuerpo no
-- está en el repositorio; informes locales dicen que inserta movimientos, pero
-- se debe confirmar con su artefacto auténtico antes de QA integrado. El bloqueo por fila no elimina deadlocks entre transacciones
-- mult producto; PostgreSQL abortará una completa y el cliente deberá permitir
-- reintento. Evaluar orden de locks y mensajes en QA.

-- FIRMAS CONTRATADAS (no descomentar ni ejecutar en esta propuesta):
-- crear_conteo_inventario(uuid[], text, uuid)
-- iniciar_linea_conteo(uuid, uuid)
-- guardar_conteo_fisico(uuid, bigint, uuid)
-- enviar_linea_conteo_a_revision(uuid, uuid)
-- consultar_conteo_contador(uuid)
-- consultar_conteo_revision(uuid)
-- aprobar_linea_conteo(uuid, uuid, text)
-- cancelar_conteo_inventario(uuid, uuid, text)
-- gestionar_permiso_conteo(uuid, boolean, boolean)
-- registrar_reconteo_fisico(uuid, bigint, uuid, text)

-- La aprobación libera el marcador dentro de la transacción manteniendo el
-- lock de producto hasta el commit; no usar GUC para saltar el trigger.

commit;
