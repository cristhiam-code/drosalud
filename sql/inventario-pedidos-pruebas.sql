-- DROSalud · Inventario y pedidos · PRUEBAS PROPUESTAS
-- Ejecutar solo en una base de pruebas con usuario autorizado y productos de prueba.
-- 1) Verificar que todos los productos comienzan en cero:
select count(*) as productos,
       count(*) filter (where saldo_unidades=0) as saldo_cero,
       count(*) filter (where saldo_unidades<>0) as con_movimientos
from public.inventario_saldos;

-- 2) Verificar que cada venta histórica NUEVA descuenta cantidad individual:
select ri.id, ri.nombre, ri.cantidad, m.unidades, m.tipo
from public.recibo_items ri
left join public.inventario_movimientos m
  on m.origen_item_id=ri.id and m.tipo='venta'
where ri.producto_id is not null
order by ri.id desc
limit 30;

-- 3) Comprobar que una anulación crea una única compensación:
select origen_id, origen_item_id, count(*) as movimientos
from public.inventario_movimientos
where tipo='anulacion'
group by origen_id, origen_item_id
having count(*)>1;

-- 4) Comprobar que las compras pendientes no generan movimientos por sí solas:
select cp.id, cp.producto_nombre, cp.estado, count(m.id) as movimientos
from public.compras_pendientes cp
left join public.inventario_movimientos m
  on m.referencia = 'Compra pendiente ' || cp.id::text
group by cp.id, cp.producto_nombre, cp.estado;

-- 5) Saldo para presentación en Kardex. No se usa FLOOR para negativos:
select p.laboratorio, p.nombre, p.unidades_por_caja,
       s.saldo_unidades,
       case when s.saldo_unidades >= 0
            then s.saldo_unidades / greatest(p.unidades_por_caja,1)
            else 0 end as cantidad_cajas,
       case when s.saldo_unidades >= 0
            then mod(s.saldo_unidades, greatest(p.unidades_por_caja,1))
            else s.saldo_unidades end as unidades
from public.productos p
join public.inventario_saldos s on s.producto_id=p.id
order by coalesce(p.laboratorio,''), p.nombre;
