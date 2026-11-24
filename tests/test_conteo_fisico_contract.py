import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_MIGRATION = (ROOT / "supabase/migrations/20261119120000_conteo_fisico_inventario.sql").read_text()
POINT_OF_SALE_FIX = (ROOT / "supabase/migrations/20261120181528_conteo_fisico_punto_venta.sql").read_text()
READ_CONTRACT_FIX = (ROOT / "supabase/migrations/20261120181609_conteo_fisico_contrato_sin_ubicaciones.sql").read_text()
LOCK_ORDER_FIX = (ROOT / "supabase/migrations/20261120181751_conteo_fisico_bloqueo_consistente.sql").read_text()
MOVEMENT_LOCK_FIX = (ROOT / "supabase/migrations/20261120182237_conteo_fisico_serializar_movimientos.sql").read_text()
API = (ROOT / "modules/conteo-fisico-api.js").read_text()
UI = (ROOT / "modules/conteo-fisico.js").read_text()
INDEX = (ROOT / "index.html").read_text()
FRACTIONING = (ROOT / "supabase/migrations/20261117160000_habilitar_fraccionamiento_con_kardex.sql").read_text()


class PhysicalCountContractTests(unittest.TestCase):
    def test_client_creates_count_without_location_parameter(self):
        self.assertIn("'crear_conteo_inventario'", API)
        self.assertIn("{ p_productos: ids, p_motivo: reason.trim() }", API)
        self.assertNotIn("p_bodega_id", API)
        self.assertNotIn("cf-warehouse", UI)
        self.assertNotIn("bodega", UI.lower())


    def test_preview_is_visibly_marked_and_uses_qa_project(self):
        self.assertIn('id="qa-env-banner"', INDEX)
        self.assertIn("ENTORNO DE PRUEBAS", INDEX)
        self.assertIn("document.title = '[PRUEBAS] Drosalud'", INDEX)
        self.assertIn("HOSTS_QA = new Set([", INDEX)
        self.assertIn("'drosalud-git-feature-conteo-fisico-inventario-drosalud.vercel.app'", INDEX)
        self.assertIn("'drosalud.vercel.app'", INDEX)
        self.assertIn("const entornoDrosalud =", INDEX)
        self.assertIn("throw new Error('Host no autorizado", INDEX)
        self.assertIn("esPreviewKardex ? 'https://uorhpljsofnfgzblxcga.supabase.co'", INDEX)
        self.assertIn(": 'https://fwkaqxzdhqpvvjhixeod.supabase.co'", INDEX)
        self.assertIn("https://uorhpljsofnfgzblxcga.supabase.co", INDEX)
        self.assertIn("https://fwkaqxzdhqpvvjhixeod.supabase.co", INDEX)

    def test_qa_create_rpc_matches_client_signature(self):
        self.assertIn("drop function if exists public.crear_conteo_inventario(uuid[], text, uuid, uuid)", POINT_OF_SALE_FIX)
        self.assertRegex(
            POINT_OF_SALE_FIX,
            re.compile(r"create function public\.crear_conteo_inventario\s*\(\s*p_productos uuid\[\],\s*p_motivo text,\s*p_solicitud_id uuid", re.I),
        )
        self.assertIn("grant execute on function public.crear_conteo_inventario(uuid[], text, uuid)", POINT_OF_SALE_FIX)

    def test_internal_location_is_fixed_and_not_selected_by_user(self):
        self.assertIn("where activa = true and es_central = true", POINT_OF_SALE_FIX)
        self.assertIn("if v_ubicaciones <> 1", POINT_OF_SALE_FIX)
        self.assertNotIn("p_bodega_id", POINT_OF_SALE_FIX)
        self.assertNotIn("listar_bodegas_conteo", API)

    def test_count_cutoff_uses_authoritative_kardex_and_product_row_lock(self):
        start = POINT_OF_SALE_FIX.split("create or replace function public.iniciar_linea_conteo", 1)[1]
        start = start.split("$function$;", 1)[0].lower()
        self.assertRegex(start, r"from public\.productos\s+where id = v_producto\s+for update")
        self.assertIn("from public.inventario_movimientos m", start)
        self.assertIn("sum(m.unidades_delta)", start)
        self.assertNotIn("inventario_sucursal_movimientos", start)

    def test_approval_holds_product_lock_until_adjustment_and_release(self):
        approval = POINT_OF_SALE_FIX.split("create or replace function public.aprobar_linea_conteo", 1)[1]
        approval = approval.split("$function$;", 1)[0].lower()
        self.assertRegex(approval, r"from public\.productos p\s+where p\.id\s*=\s*v_producto\s+for update")
        self.assertIn("delete from public.inventario_conteos_bloqueos", approval)
        self.assertIn("insert into public.inventario_movimientos", approval)
        self.assertRegex(approval, r"update public\.inventario_conteos_items\s+set movimiento_id\s*=\s*v_movimiento")
        self.assertLess(approval.index("for update"), approval.index("delete from public.inventario_conteos_bloqueos"))

    def test_cancellation_locks_products_in_stable_order(self):
        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()
        self.assertIn("order by b.producto_id", cancel)
        self.assertRegex(cancel, r"from public\.productos p\s+where p\.id\s*=\s*v_producto\s+for update")
        self.assertRegex(cancel, r"where id\s*=\s*p_conteo_id\s+for update")

    def test_list_rpc_no_longer_exposes_location_fields(self):
        self.assertIn("drop function public.listar_conteos_inventario()", READ_CONTRACT_FIX)
        self.assertIn("total_items bigint", READ_CONTRACT_FIX)
        self.assertNotIn("bodega_id", READ_CONTRACT_FIX)
        self.assertIn("revoke all on function public.listar_bodegas_conteo()", READ_CONTRACT_FIX)

    def test_all_count_mutations_follow_product_session_item_lock_order(self):
        for name in ("guardar_conteo_fisico", "enviar_linea_conteo_a_revision", "registrar_reconteo_fisico"):
            body = LOCK_ORDER_FIX.split(f"create or replace function public.{name}", 1)[1]
            body = body.split("$function$;", 1)[0].lower()
            self.assertRegex(body, r"from public\.productos p where p\.id\s*=\s*v_producto for update")
            product_lock = re.search(r"from public\.productos p where p\.id\s*=\s*v_producto for update", body)
            session_lock = re.search(r"from public\.inventario_conteos\s+where id\s*=\s*v_item\.conteo_id\s+for update", body)
            self.assertIsNotNone(product_lock)
            self.assertIsNotNone(session_lock)
            self.assertLess(product_lock.start(), session_lock.start())
        self.assertIn("revoke all on function public.registrar_conteo_inventario", LOCK_ORDER_FIX)


    def test_sales_and_receipts_share_product_and_location_locks_with_count(self):
        central = MOVEMENT_LOCK_FIX.split("create or replace function public.proteger_movimiento_durante_conteo()", 1)[1]
        central = central.split("$function$;", 1)[0].lower()
        central_product = re.search(r"from public\.productos p\s+where p\.id\s*=\s*new\.producto_id\s+for update", central)
        self.assertIsNotNone(central_product)
        self.assertLess(central_product.start(), central.index("if new.tipo='recepcion'"))
        self.assertIn("from public.inventario_conteos_bloqueos b", central)

        mirror = MOVEMENT_LOCK_FIX.split("create or replace function public.proteger_movimiento_sucursal_durante_conteo()", 1)[1]
        mirror = mirror.split("$function$;", 1)[0].lower()
        mirror_product = re.search(r"from public\.productos p\s+where p\.id\s*=\s*new\.producto_id\s+for update", mirror)
        self.assertIsNotNone(mirror_product)
        self.assertLess(mirror_product.start(), mirror.index("pg_advisory_xact_lock_shared"))

        start = MOVEMENT_LOCK_FIX.split("create or replace function public.iniciar_linea_conteo", 1)[1]
        start = start.split("$function$;", 1)[0].lower()
        start_product = re.search(r"from public\.productos where id\s*=\s*v_producto\s+for update", start)
        self.assertIsNotNone(start_product)
        self.assertLess(start_product.start(), start.index("pg_advisory_xact_lock("))

    def test_kardex_guard_and_immutability_remain_in_base_migration(self):
        self.assertIn("from public.productos p where p.id=new.producto_id for update", BASE_MIGRATION)
        self.assertIn("public.inventario_conteos_bloqueos b where b.producto_id=new.producto_id", BASE_MIGRATION)
        self.assertIn("before update or delete on public.inventario_movimientos", BASE_MIGRATION)
        self.assertIn("before truncate on public.inventario_movimientos", BASE_MIGRATION)
        self.assertIn("using errcode='55000'", BASE_MIGRATION)

    def test_fractioning_adjustment_contract_is_not_replaced(self):
        self.assertIn("'ajuste',", FRACTIONING)
        self.assertIn("habilitar_fraccionamiento_producto", FRACTIONING)
        for migration in (POINT_OF_SALE_FIX, READ_CONTRACT_FIX, LOCK_ORDER_FIX, MOVEMENT_LOCK_FIX):
            self.assertNotIn("create or replace function public.habilitar_fraccionamiento_producto", migration)

    def test_existing_purchase_and_sales_modules_are_out_of_scope(self):
        for migration in (POINT_OF_SALE_FIX, READ_CONTRACT_FIX, LOCK_ORDER_FIX, MOVEMENT_LOCK_FIX):
            self.assertNotIn("create or replace function public.registrar_recepcion_compra", migration)
            self.assertNotIn("create or replace function public.registrar_venta_drosalud", migration)
            self.assertNotIn("create or replace function public.fn_inventario_descuenta_venta", migration)
            self.assertNotIn("create or replace function public.ps_sync_movimiento_inventario", migration)
            self.assertNotIn("alter table public.usuarios_drosalud", migration)

    def test_request_ids_are_kept_for_safe_retries(self):
        self.assertIn("localStorage.setItem(key, id)", API)
        self.assertIn("localStorage.removeItem(request.key)", API)
        self.assertIn("Keep this request UUID so the user can retry safely after a lost response", API)


    def test_approval_rpc_requires_authenticated_count_approval_permission(self):
        approval = POINT_OF_SALE_FIX.split("create or replace function public.aprobar_linea_conteo", 1)[1]
        approval = approval.split("$function$;", 1)[0].lower()
        self.assertIn("auth.uid() is null", approval)
        self.assertIn("not public.es_usuario_drosalud()", approval)
        self.assertIn("not public.inventario_conteo_tiene_permiso(true)", approval)
        self.assertIn("no tienes permiso para aprobar conteos", approval)
        self.assertIn("quien contó o recontó el producto no puede aprobarlo", approval)

    def test_permission_management_and_cancellation_are_admin_only(self):
        permission = BASE_MIGRATION.split("create or replace function public.gestionar_permiso_conteo", 1)[1]
        permission = permission.split("$function$;", 1)[0].lower()
        self.assertIn("auth.uid() is null", permission)
        self.assertIn("not public.es_usuario_drosalud()", permission)
        self.assertIn("not public.es_admin_drosalud()", permission)
        self.assertIn("solo administración puede cambiar permisos", permission)

        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()
        self.assertIn("not public.es_admin_drosalud()", cancel)
        self.assertIn("solo administración puede cancelar un conteo", cancel)

    def test_permission_helper_requires_active_user_and_explicit_capability_or_admin(self):
        helper = BASE_MIGRATION.split("create or replace function public.inventario_conteo_tiene_permiso", 1)[1]
        helper = helper.split("$function$;", 1)[0].lower()
        self.assertIn("auth.uid() is not null", helper)
        self.assertIn("public.es_usuario_drosalud()", helper)
        self.assertIn("public.es_admin_drosalud()", helper)
        self.assertIn("p.revocado_en is null", helper)
        self.assertIn("case when p_aprobar then p.puede_aprobar else p.puede_contar end", helper)


    def test_approval_permission_guard_runs_before_validation_or_data_access(self):
        approval = POINT_OF_SALE_FIX.split("create or replace function public.aprobar_linea_conteo", 1)[1]
        approval = approval.split("$function$;", 1)[0].lower()

        permission_guard = approval.index("not public.inventario_conteo_tiene_permiso(true)")
        permission_error = approval.index("no tienes permiso para aprobar conteos")
        argument_validation = approval.index("if p_solicitud_id is null")
        item_lookup = approval.index("select producto_id, conteo_id")
        first_mutation = approval.index("delete from public.inventario_conteos_bloqueos")

        self.assertLess(permission_guard, permission_error)
        self.assertLess(permission_error, argument_validation)
        self.assertLess(argument_validation, item_lookup)
        self.assertLess(item_lookup, first_mutation)
        self.assertIn("raise exception 'no tienes permiso para aprobar conteos'", approval)


    def test_cancellation_requires_active_admin_before_validation_or_data_access(self):
        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()

        auth_guard = cancel.index("not public.es_admin_drosalud()")
        auth_error = cancel.index("solo administración puede cancelar un conteo")
        argument_validation = cancel.index("if p_solicitud_id is null")
        first_product_lookup = cancel.index("from public.inventario_conteos_bloqueos")
        first_write = cancel.index("update public.inventario_conteos_items")

        self.assertLess(auth_guard, auth_error)
        self.assertLess(auth_error, argument_validation)
        self.assertLess(argument_validation, first_product_lookup)
        self.assertLess(first_product_lookup, first_write)
        self.assertIn("auth.uid() is null", cancel)
        self.assertIn("not public.es_usuario_drosalud()", cancel)

    def test_cancellation_locks_products_in_uuid_order_before_session(self):
        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()

        ordered_products = re.search(
            r"select distinct b\.producto_id.*?order by b\.producto_id",
            cancel,
            re.S,
        )
        product_lock = re.search(
            r"from public\.productos p\s+where p\.id = v_producto\s+for update",
            cancel,
        )
        session_lock = re.search(
            r"from public\.inventario_conteos\s+where id = p_conteo_id\s+for update",
            cancel,
        )
        self.assertIsNotNone(ordered_products)
        self.assertIsNotNone(product_lock)
        self.assertIsNotNone(session_lock)
        self.assertLess(ordered_products.start(), product_lock.start())
        self.assertLess(product_lock.start(), session_lock.start())

    def test_cancellation_preserves_approved_items_and_cancels_only_unapproved(self):
        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()

        self.assertRegex(
            cancel,
            r"update public\.inventario_conteos_items\s+set estado = 'cancelado'\s+where conteo_id = p_conteo_id\s+and estado <> 'aprobado'",
        )
        self.assertIn("delete from public.inventario_conteos_bloqueos", cancel)
        self.assertIn("where conteo_id = p_conteo_id", cancel)
        self.assertIn("set estado = 'cancelado'", cancel)
        self.assertIn("cancelado_por = auth.uid()", cancel)
        self.assertIn("cancelado_en = now()", cancel)
        self.assertIn("motivo_cancelacion", cancel)
        self.assertIn("solicitud_cancelacion_id", cancel)

    def test_cancellation_never_creates_kardex_adjustments_and_is_idempotent(self):
        cancel = POINT_OF_SALE_FIX.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
        cancel = cancel.split("$function$;", 1)[0].lower()

        self.assertNotIn("insert into public.inventario_movimientos", cancel)
        self.assertNotIn("tipo = 'ajuste'", cancel)
        self.assertIn("if v_sesion.estado = 'cancelado' then", cancel)
        self.assertIn("v_sesion.solicitud_cancelacion_id <> p_solicitud_id", cancel)
        self.assertIn("v_sesion.cancelado_por <> auth.uid()", cancel)
        self.assertIn("v_sesion.motivo_cancelacion <> btrim(p_motivo)", cancel)
        self.assertIn("if v_sesion.estado <> 'abierto' then", cancel)


if __name__ == "__main__":
    unittest.main()
