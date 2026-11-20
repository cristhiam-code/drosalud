import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_MIGRATION = (ROOT / "supabase/migrations/20261119120000_conteo_fisico_inventario.sql").read_text()
POINT_OF_SALE_FIX = (ROOT / "supabase/migrations/20261120140000_conteo_fisico_punto_venta.sql").read_text()
READ_CONTRACT_FIX = (ROOT / "supabase/migrations/20261120141500_conteo_fisico_contrato_sin_ubicaciones.sql").read_text()
LOCK_ORDER_FIX = (ROOT / "supabase/migrations/20261120143000_conteo_fisico_bloqueo_consistente.sql").read_text()
MOVEMENT_LOCK_FIX = (ROOT / "supabase/migrations/20261120144500_conteo_fisico_serializar_movimientos.sql").read_text()
API = (ROOT / "modules/conteo-fisico-api.js").read_text()
UI = (ROOT / "modules/conteo-fisico.js").read_text()
FRACTIONING = (ROOT / "supabase/migrations/20261117160000_habilitar_fraccionamiento_con_kardex.sql").read_text()


class PhysicalCountContractTests(unittest.TestCase):
    def test_client_creates_count_without_location_parameter(self):
        self.assertIn("'crear_conteo_inventario'", API)
        self.assertIn("{ p_productos: ids, p_motivo: reason.trim() }", API)
        self.assertNotIn("p_bodega_id", API)
        self.assertNotIn("cf-warehouse", UI)
        self.assertNotIn("bodega", UI.lower())

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
        self.assertIn("update public.inventario_conteos_items set movimiento_id=v_movimiento", approval)
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
        for migration in (POINT_OF_SALE_FIX, READ_CONTRACT_FIX, LOCK_ORDER_FIX):
            self.assertNotIn("create or replace function public.registrar_recepcion_compra", migration)
            self.assertNotIn("create or replace function public.registrar_venta_drosalud", migration)
            self.assertNotIn("create or replace function public.fn_inventario_descuenta_venta", migration)
            self.assertNotIn("create or replace function public.ps_sync_movimiento_inventario", migration)
            self.assertNotIn("alter table public.usuarios_drosalud", migration)

    def test_request_ids_are_kept_for_safe_retries(self):
        self.assertIn("localStorage.setItem(key, id)", API)
        self.assertIn("localStorage.removeItem(request.key)", API)
        self.assertIn("Keep this request UUID so the user can retry safely after a lost response", API)


if __name__ == "__main__":
    unittest.main()
