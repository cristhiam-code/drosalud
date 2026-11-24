/* Servicio de configuración persistente del negocio. */
(() => {
  'use strict';

  function validar(cliente) {
    if (!cliente || typeof cliente.from !== 'function') {
      throw new Error('El servicio de configuración requiere un cliente Supabase válido.');
    }
  }

  function canonizar(valor) {
    if (!valor || typeof valor !== 'object') return valor;
    if (Array.isArray(valor)) return valor.map(canonizar);
    return Object.fromEntries(Object.keys(valor).sort().map(clave => [clave, canonizar(valor[clave])]));
  }

  async function cargar(cliente) {
    validar(cliente);
    const { data, error } = await cliente.from('ajustes').select('datos').eq('id', 1).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('No existe el registro principal de ajustes (id=1). No se aplicaron valores predeterminados para evitar sobrescribir la configuración del negocio.');
    return data.datos && typeof data.datos === 'object' ? data.datos : {};
  }

  async function guardar(cliente, datos) {
    validar(cliente);
    const { data, error } = await cliente.from('ajustes')
      .upsert({ id: 1, datos, actualizado_en: new Date().toISOString() })
      .select('id,datos').single();
    if (error) throw error;
    if (!data || Number(data.id) !== 1) throw new Error('Supabase no confirmó el guardado de los ajustes.');
    if (JSON.stringify(canonizar(data.datos)) !== JSON.stringify(canonizar(datos))) {
      throw new Error('Supabase devolvió valores distintos a los enviados. No se confirmó el guardado.');
    }
    return data.datos;
  }

  async function comprobar(cliente) {
    validar(cliente);
    const { data, error } = await cliente.from('ajustes').select('id').eq('id', 1).maybeSingle();
    if (error) throw error;
    return data;
  }

  window.DrosaludSettingsService = Object.freeze({ cargar, guardar, comprobar });
})();
