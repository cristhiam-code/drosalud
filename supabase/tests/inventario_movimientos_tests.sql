-- Drosalud · Verificaciones de solo lectura para inventario
-- Ejecutar únicamente después de instalar la migración en un entorno de pruebas.
-- No crea ni modifica registros.

-- 1. Saldo por producto (los productos sin movimientos deben dar cero).
select p.id, p.nombre, p.laboratorio,
       coalesce(sum(m.unidades_delta),0)::integer as saldo_unidades
from public.productos p
left join public.inventario_movimientos m on m.producto_id=p.id
group by p.id,p.nombre,p.laboratorio
order by p.laboratorio nulls first,p.nombre;

-- 2. Ventas: cada línea de recibo con producto debe tener un movimiento negativo
-- por la cantidad individual vendida.
select ri.id as recibo_item_id, ri.producto_id, ri.cantidad,
       im.id as movimiento_id, im.unidades_delta
from public.recibo_items ri
left join public.inventario_movimientos im
  on im.tipo='venta' and im.referencia_id=ri.id
where ri.producto_id is not null
  and (im.id is null or im.unidades_delta <> -ri.cantidad);

-- 3. Anulaciones: cada línea anulada debe tener una reversión positiva exacta.
select ri.id as recibo_item_id, ri.cantidad,
       im.id as movimiento_id, im.unidades_delta
from public.recibo_items ri
join public.recibos r on r.id=ri.recibo_id and r.anulado=true
left join public.inventario_movimientos im
  on im.tipo='anulacion' and im.referencia_id=ri.id
where ri.producto_id is not null
  and (im.id is null or im.unidades_delta <> ri.cantidad);

-- 4. No debe haber más de un movimiento de recepción por clave de operación.
select operacion_id, count(*) as cantidad
from public.inventario_movimientos
where tipo='recepcion' and operacion_id is not null
group by operacion_id
having count(*) > 1;

-- 5. Recepciones antiguas sin clave (si aparecen, revisar antes de continuar).
select id, producto_id, unidades_delta, creado_en
from public.inventario_movimientos
where tipo='recepcion' and operacion_id is null;
