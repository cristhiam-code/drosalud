-- Drosalud · Pruebas propuestas para inventario
-- Ejecutar solo en una base de pruebas con usuarios/productos de prueba.
-- No contiene escrituras automáticas ni debe correrse en producción.
-- 1) Verificar que todos los productos parten de saldo cero:
select count(*) as productos,
       count(*) filter (where coalesce(m.saldo,0) <> 0) as productos_con_saldo_no_cero
from public.productos p
left join (
  select producto_id, sum(unidades_delta)::integer saldo
  from public.inventario_movimientos group by producto_id
) m on m.producto_id=p.id;

-- 2) Verificar movimientos de ventas: debe existir un movimiento negativo
-- por cada línea con producto_id y mismo valor absoluto que recibo_items.cantidad.
select ri.id, ri.producto_id, ri.cantidad,
       im.unidades_delta, im.tipo
from public.recibo_items ri
left join public.inventario_movimientos im
  on im.referencia_id=ri.id and im.tipo='venta'
where ri.producto_id is not null
order by ri.id;

-- 3) Verificar anulaciones: el movimiento de reversión debe ser positivo
-- y corresponder a la cantidad original, una sola vez por línea.
select ri.id, ri.cantidad, im.unidades_delta, im.tipo
from public.recibo_items ri
join public.recibos r on r.id=ri.recibo_id and r.anulado=true
left join public.inventario_movimientos im
  on im.referencia_id=ri.id and im.tipo='anulacion'
where ri.producto_id is not null
order by ri.id;

-- 4) Verificar saldo agregado, incluidos productos sin movimientos (saldo 0).
select p.id,p.nombre,p.laboratorio,
       coalesce(sum(m.unidades_delta),0)::integer as unidades_disponibles
from public.productos p
left join public.inventario_movimientos m on m.producto_id=p.id
group by p.id,p.nombre,p.laboratorio
order by p.laboratorio nulls first,p.nombre;
