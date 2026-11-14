
-- La sucursal central hereda el Kardex histórico completo, no solo un saldo de apertura.
-- Así el pedido sugerido puede medir la rotación de los últimos siete días desde el día uno.
delete from public.inventario_sucursal_movimientos
where tipo='saldo_inicial' and movimiento_origen_id is null
  and notas='Saldo inicial migrado desde inventario general al crear la estructura multi-sucursal';

insert into public.inventario_sucursal_movimientos
  (bodega_id,producto_id,tipo,unidades_delta,referencia_id,movimiento_origen_id,notas,creado_por,creado_en)
select b.id,m.producto_id,
  case m.tipo when 'venta' then 'venta' when 'anulacion' then 'anulacion'
    when 'recepcion' then 'recepcion_proveedor' when 'ajuste' then 'ajuste'
    when 'saldo_inicial' then 'saldo_inicial' else null end,
  m.unidades_delta,m.referencia_id,m.id,m.notas,m.creado_por,m.creado_en
from public.inventario_movimientos m
cross join public.bodegas b
where b.es_central=true and b.activa=true
  and m.tipo in ('venta','anulacion','recepcion','ajuste','saldo_inicial')
on conflict (movimiento_origen_id) do nothing;
