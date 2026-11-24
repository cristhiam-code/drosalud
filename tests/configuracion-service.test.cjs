'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

global.window = {};
require('../services/configuracion.js');
const service = global.window.DrosaludSettingsService;

function makeClient(data) {
  const calls = [];
  return {
    calls,
    from(table) {
      const q = { table, filters: [], operation: 'select' };
      const chain = {
        select(...args) { q.selection = args; return this; },
        eq(...args) { q.filters.push(args); return this; },
        upsert(value) { q.operation = 'upsert'; q.value = value; return this; },
        maybeSingle() { calls.push({ ...q }); return Promise.resolve({ data, error: null }); },
        single() { calls.push({ ...q }); return Promise.resolve({ data, error: null }); }
      };
      return chain;
    }
  };
}

test('carga configuración persistida y no inventa valores si falta el registro', async () => {
  const client = makeClient({ id: 1, datos: { m: 30, colorPri: '#123456' } });
  assert.deepEqual(await service.cargar(client), { m: 30, colorPri: '#123456' });
  await assert.rejects(service.cargar(makeClient(null)), /No existe el registro principal de ajustes/);
});

test('guarda configuración y compara el objeto de forma estable', async () => {
  const settings = { z: 1, a: { y: 2, x: 3 } };
  const client = makeClient({ id: 1, datos: { a: { x: 3, y: 2 }, z: 1 } });
  assert.deepEqual(await service.guardar(client, settings), client.calls[0]?.value?.datos || settings);
  assert.equal(client.calls[0].operation, 'upsert');
  assert.equal(client.calls[0].value.id, 1);
});

test('comprueba disponibilidad del registro de configuración', async () => {
  const client = makeClient({ id: 1 });
  assert.deepEqual(await service.comprobar(client), { id: 1 });
});

test('rechaza cliente inválido y propaga errores', async () => {
  await assert.rejects(service.cargar(null), /cliente Supabase válido/);
  const error = new Error('sin permiso');
  const client = {
    from() {
      const chain = { select() { return this; }, eq() { return this; }, maybeSingle() { return Promise.resolve({ data: null, error }); } };
      return chain;
    }
  };
  await assert.rejects(service.cargar(client), value => value === error);
});
