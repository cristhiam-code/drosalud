-- Drosalud · Verificaciones de solo lectura para inventario
-- Ejecutar únicamente después de instalar las migraciones en un entorno de pruebas.
-- No crea ni modifica registros.
--
-- IMPORTANTE: ajustar inicio_control a la fecha/hora local de instalación
-- de la migración de inventario en el entorno que se está auditando.
-- El inventario comienza en cero; ventas y anulaciones anteriores a esa fecha
-- no tienen movimientos y NO deben reportarse como errores.

-- 1. Saldo por producto (los productos sin movimientos deben dar cero).
select p.id, p.nombre, p.laboratorio,
       coalesce(sum(m.unidades_delta),0)::integer as saldo_unidades
from public.productos p
left join public.inventario_movimientos m on m.producto_id=p.id
group by p.id,p.nombre,p.laboratorio
order by p.laboratorio nulls first,p.nombre;

-- 2. Ventas posteriores al inicio del Kardex: cada línea con producto debe
-- tener un movimiento negativo por la cantidad individual vendida.
with control as (
  select timestamptz '2026-11-09 14:00:00-05' as inicio_control
)
select ri.id as recibo_item_id, ri.producto_id, ri.cantidad,
       im.id as movimiento_id, im.unidades_delta
from public.recibo_items ri
join public.recibos r on r.id=ri.recibo_id
cross join control c
left join public.inventario_movimientos im
  on im.tipo='venta' and im.referencia_id=ri.id
where r.creado_en >= c.inicio_control
  and ri.producto_id is not null
  and (im.id is null or im.unidades_delta <> -ri.cantidad);

-- 3. Anulaciones posteriores al inicio del Kardex: cada línea anulada debe
-- tener una reversión positiva exacta.
with control as (
  select timestamptz '2026-11-09 14:00:00-05' as inicio_control
)
select ri.id as recibo_item_id, ri.cantidad,
       im.id as movimiento_id, im.unidades_delta
from public.recibo_items ri
join public.recibos r on r.id=ri.recibo_id and r.anulado=true
cross join control c
left join public.inventario_movimientos im
  on im.tipo='anulacion' and im.referencia_id=ri.id
where r.creado_en >= c.inicio_control
  and ri.producto_id is not null
  and (im.id is null or im.unidades_delta <> ri.cantidad);

-- 4. No debe haber más de un movimiento de recepción por clave de operación.
select operacion_id, count(*) as cantidad
from public.inventario_movimientos
where tipo='recepcion' and operacion_id is not null
group by operacion_id
having count(*) > 1;

-- 5. Recepciones antiguas sin clave (revisión informativa; no son duplicados por sí solas).
select id, producto_id, unidades_delta, creado_en
from public.inventario_movimientos
where tipo='recepcion' and operacion_id is null;

-- 6. No debe existir una reversión sin su descuento original ni con valor distinto.
select anulacion.id as movimiento_anulacion_id, anulacion.referencia_id
from public.inventario_movimientos anulacion
left join public.inventario_movimientos venta
  on venta.tipo='venta'
 and venta.referencia_id=anulacion.referencia_id
where anulacion.tipo='anulacion'
  and (venta.id is null or anulacion.unidades_delta <> -venta.unidades_delta);
