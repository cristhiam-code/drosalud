/* API del módulo de conteo físico. Toda escritura se realiza mediante RPC. */
(() => {
  'use strict';
  const KEY_PREFIX = 'drosalud:conteo:request:';
  const uuid = () => crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 3 | 8)).toString(16);
  });
  function requestId(scope, legacyKey=null) {
    const key = KEY_PREFIX + scope;
    const existing = localStorage.getItem(key);
    const legacy = legacyKey ? localStorage.getItem(legacyKey) : null;
    if (existing && legacy && existing !== legacy) {
      throw new Error('Hay dos solicitudes de conteo pendientes para los mismos productos. Actualiza la pantalla antes de continuar.');
    }
    if (existing) return { key, id: existing, legacyKey };
    const id = legacy || uuid();
    localStorage.setItem(key, id);
    return { key, id, legacyKey: legacy ? legacyKey : null };
  }
  async function operation(scope, rpcName, params, requestField='p_solicitud_id', legacyKeyForUser=null) {
    const { data: authData, error: authError } = await sb.auth.getUser();
    if(authError)throw authError;
    if(!authData?.user?.id)throw new Error('Inicia sesión para continuar.');
    const legacyKey = legacyKeyForUser?.(authData.user.id) || null;
    const request = requestId(authData.user.id + ':' + scope, legacyKey);
    try {
      const { data, error } = await sb.rpc(rpcName, { ...params, [requestField]: request.id });
      if (error) throw error;
      localStorage.removeItem(request.key);
      if (request.legacyKey) localStorage.removeItem(request.legacyKey);
      return data;
    } catch (error) {
      // Keep this request UUID so the user can retry safely after a lost response.
      throw error;
    }
  }
  function legacyCreateRequestKey(userId, ids, reason) {
    const prefix = KEY_PREFIX + userId + ':crear:';
    const suffix = ':' + [...ids].sort().join(',') + ':' + reason.trim();
    const candidates = [];
    for (let index = 0; index < localStorage.length; index++) {
      const key = localStorage.key(index);
      if (!key?.startsWith(prefix) || !key.endsWith(suffix)) continue;
      const legacyLocationId = key.slice(prefix.length, key.length - suffix.length);
      if (/^[0-9a-f-]{36}$/i.test(legacyLocationId)) candidates.push(key);
    }
    if (candidates.length > 1) {
      throw new Error('Hay varias solicitudes de conteo pendientes para los mismos productos. Actualiza la pantalla antes de continuar.');
    }
    return candidates[0] || null;
  }
  window.DrosaludConteoApi = Object.freeze({
    capabilities: () => sb.rpc('consultar_capacidades_conteo'),
    list: () => sb.rpc('listar_conteos_inventario'),
    items: id => sb.rpc('consultar_conteo_contador', { p_conteo_id: id }),
    review: id => sb.rpc('consultar_conteo_revision', { p_conteo_id: id }),
    products: async () => {
      const rows=[];
      for(let from=0; ; from+=1000){
        const { data, error } = await sb.from('productos_app')
          .select('id,codigo,nombre,laboratorio,fraccionable,unidades_por_caja,unidades_por_venta')
          .order('nombre').range(from,from+999);
        if(error)throw error;
        rows.push(...(data||[]));
        if(!data||data.length<1000)break;
      }
      return rows;
    },
    create: (ids, reason) => operation('crear:' + [...ids].sort().join(',') + ':' + reason.trim(),
      'crear_conteo_inventario', { p_productos: ids, p_motivo: reason.trim() }, 'p_solicitud_id',
      userId => legacyCreateRequestKey(userId, ids, reason)),
    start: itemId => operation('inicio:' + itemId, 'iniciar_linea_conteo', { p_item_id: itemId }),
    save: (itemId, quantity) => operation('captura:' + itemId, 'guardar_conteo_fisico',
      { p_item_id: itemId, p_cantidad_base: quantity }),
    submit: itemId => operation('envio:' + itemId, 'enviar_linea_conteo_a_revision', { p_item_id: itemId }),
    recount: (itemId, quantity, reason) => operation('reconteo:' + itemId, 'registrar_reconteo_fisico',
      { p_item_id: itemId, p_cantidad_base: quantity, p_motivo: reason || null }),
    approve: (itemId, reason) => operation('aprobacion:' + itemId, 'aprobar_linea_conteo',
      { p_item_id: itemId, p_motivo: reason.trim() }),
    cancel: (sessionId, reason) => operation('cancelacion:' + sessionId, 'cancelar_conteo_inventario',
      { p_conteo_id: sessionId, p_motivo: reason.trim() }),
    setPermission: async (userId, canCount, canApprove) => {
      const { error } = await sb.rpc('gestionar_permiso_conteo', {
        p_usuario: userId, p_puede_contar: canCount, p_puede_aprobar: canApprove
      });
      if (error) throw error;
    }
  });
})();
