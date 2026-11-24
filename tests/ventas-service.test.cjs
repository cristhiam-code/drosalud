'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/ventas.js');

const service = global.window.DrosaludSalesService;

function fakeClient(response) {
  const calls = [];
  return {
    calls,
    client: {
      async rpc(name, args) {
        calls.push({ name, args });
        if (response instanceof Error) return { data: null, error: response };
        return response;
      }
    }
  };
}

test('registra venta mediante RPC con cliente inyectado y argumentos intactos', async () => {
  const venta = { forma_pago: 'Efectivo', descuento: 0 };
  const items = [{ producto_id: 'p1', cantidad: 2, precio_venta: 1000 }];
  const recibo = { id: 'r1', numero: 10 };
  const fake = fakeClient({ data: recibo, error: null });

  const result = await service.registrarVenta(fake.client, venta, items);

  assert.deepEqual(result, recibo);
  assert.deepEqual(fake.calls, [{
    name: 'registrar_venta_drosalud',
    args: { p_venta: venta, p_items: items }
  }]);
});

test('propaga el error original del RPC de venta', async () => {
  const error = new Error('fallo controlado');
  const fake = fakeClient(error);
  await assert.rejects(service.registrarVenta(fake.client, {}, [{}]), value => value === error);
});

test('rechaza una venta si el RPC no devuelve un recibo identificable', async () => {
  const fake = fakeClient({ data: null, error: null });
  await assert.rejects(
    service.registrarVenta(fake.client, {}, [{}]),
    /no devolvió un recibo válido/
  );
});

test('crea cotización mediante RPC y devuelve la respuesta', async () => {
  const cotizacion = { total: 2000 };
  const items = [{ producto_id: 'p2', cantidad: 2 }];
  const quote = { id: 'c1', numero: 3 };
  const fake = fakeClient({ data: quote, error: null });

  const result = await service.crearCotizacion(fake.client, cotizacion, items);

  assert.deepEqual(result, quote);
  assert.deepEqual(fake.calls, [{
    name: 'crear_cotizacion_venta_drosalud',
    args: { p_cotizacion: cotizacion, p_items: items }
  }]);
});

test('rechaza servicios de venta sin un cliente Supabase inyectado', async () => {
  await assert.rejects(service.registrarVenta(null, {}, []), /cliente Supabase válido/);
  await assert.rejects(service.crearCotizacion({}, {}, []), /cliente Supabase válido/);
});
