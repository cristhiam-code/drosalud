import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261119204618_20261119120000_conteo_fisico_inventario.sql").read_text()
BRANCH_MIGRATION = (ROOT / "supabase/migrations/20261114200154_pedidos_sucursales_estructura.sql").read_text()
QA_CORRECTION = (ROOT / "supabase/qa_migrations/20261120090000_conteo_fisico_kardex_central_corrective.sql").read_text()
PRODUCTION_INSTALL = (ROOT / "supabase/production/04_conteo_fisico_inventario_central.sql").read_text()
UI = (ROOT / "modules/conteo-fisico.js").read_text()
API = (ROOT / "modules/conteo-fisico-api.js").read_text()
FRACTIONING = (ROOT / "supabase/migrations/20261117160000_habilitar_fraccionamiento_con_kardex.sql").read_text()


class PhysicalCountContractTests(unittest.TestCase):
    def test_kardex_types_include_existing_and_adjustment_types(self):
        self.assertRegex(MIGRATION, r"check\s*\(tipo in \('venta','anulacion','recepcion','saldo_inicial','ajuste'\)\)")
        self.assertIn("tipo in ('saldo_inicial','ajuste')", MIGRATION)

    def test_purchase_metadata_columns_and_foreign_keys_match_qa(self):
        self.assertRegex(MIGRATION, r"add column if not exists proveedor_id uuid,\s*add column if not exists recepcion_compra_id uuid,\s*add column if not exists costo_unitario_base numeric")
        self.assertIn("foreign key (proveedor_id) references public.proveedores(id)", MIGRATION)
        self.assertIn("foreign key (recepcion_compra_id) references public.recepciones_compra(id)", MIGRATION)
        self.assertNotIn("add column if not exists proveedor_id", QA_CORRECTION)
        self.assertNotIn("add column if not exists proveedor_id", PRODUCTION_INSTALL)

    def test_original_branch_migration_installs_central_kardex_sync_trigger(self):
        self.assertRegex(BRANCH_MIGRATION, re.compile(
            r"create\s+trigger\s+trg_ps_sync_inventario_movimiento\s+"
            r"after\s+insert\s+on\s+public\.inventario_movimientos\s+"
            r"for\s+each\s+row\s+execute\s+function\s+"
            r"public\.ps_sync_movimiento_inventario\s*\(\s*\)\s*;",
            re.IGNORECASE,
        ))

    def test_movement_guard_shares_normal_locks_and_rejects_counted_pair(self):
        self.assertIn("proteger_movimiento_sucursal_durante_conteo", MIGRATION)
        self.assertIn("b.bodega_id=new.bodega_id and b.producto_id=new.producto_id", MIGRATION)
        self.assertIn("inventario_sucursal_movimientos m where m.bodega_id=v_bodega and m.producto_id=v_producto", MIGRATION)
        self.assertIn("pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(new.bodega_id::text,0))", MIGRATION)
        self.assertIn("using errcode='55P03'", MIGRATION)

    def test_exclusive_locks_are_limited_to_inventory_state_transitions(self):
        def function_sql(name):
            start = MIGRATION.index(f"create or replace function public.{name}")
            end = MIGRATION.index("$function$;", start) + len("$function$;")
            return MIGRATION[start:end]
        for name in ("iniciar_linea_conteo", "aprobar_linea_conteo", "cancelar_conteo_inventario"):
            self.assertIn("pg_advisory_xact_lock(", function_sql(name))
        for name in ("guardar_conteo_fisico", "enviar_linea_conteo_a_revision", "registrar_reconteo_fisico"):
            self.assertNotIn("pg_advisory_xact_lock", function_sql(name))

    def test_count_does_not_require_a_warehouse_in_the_client_or_clean_install(self):
        self.assertNotIn("p_bodega_id", API)
        self.assertNotIn('id="cf-warehouse"', UI)
        self.assertNotIn("bodega_id", PRODUCTION_INSTALL)

    def test_legacy_count_rpc_cannot_write_unapproved_adjustments(self):
        self.assertIn("Los ajustes de conteo deben pasar por aprobación del conteo físico", MIGRATION)
        self.assertIn("new.tipo in ('ajuste','saldo_inicial') and new.referencia_id is null and new.operacion_id is not null", MIGRATION)
        self.assertIn("new.tipo in ('ajuste','saldo_inicial') and new.referencia_id is null and new.operacion_id is not null", QA_CORRECTION)
        self.assertIn("'ajuste',\n        v_ajuste::integer", FRACTIONING)
        self.assertIn("(producto_id, tipo, unidades_delta, notas, creado_por)", FRACTIONING)

    def test_purchase_rpc_is_not_replaced_by_a_historical_definition(self):
        self.assertNotRegex(MIGRATION, r"create or replace function public\.registrar_recepcion_compra\s*\(")

    def test_approved_count_adjustment_stays_out_of_the_warehouse_sidecar(self):
        self.assertIn("then return new; end if;", QA_CORRECTION)
        self.assertIn("select 1 from public.inventario_conteos_items i where i.id=new.referencia_id", QA_CORRECTION)
        self.assertIn("on conflict (movimiento_origen_id) do nothing", QA_CORRECTION)

    def test_branch_rpc_signatures_and_permissions_are_preserved(self):
        self.assertRegex(MIGRATION, r"ps_registrar_despacho_sucursal\s*\(\s*p_pedido_id uuid,p_items jsonb,p_notas text,p_operacion_id uuid\s*\)")
        self.assertRegex(MIGRATION, r"ps_confirmar_recepcion_sucursal\s*\(\s*p_despacho_id uuid,p_items jsonb,p_notas text,p_operacion_id uuid\s*\)")
        for name in ("ps_registrar_despacho_sucursal", "ps_confirmar_recepcion_sucursal"):
            start = MIGRATION.index(f"create or replace function public.{name}")
            end = MIGRATION.index("$function$;", start)
            definition = MIGRATION[start:end]
            self.assertIn("security definer", definition)
            self.assertIn("set search_path=''", definition)
            self.assertIn("pg_advisory_xact_lock(hashtextextended(p_operacion_id::text,0))", definition)
            self.assertNotRegex(definition, r"\bexception\s+when\b")
        self.assertIn("public.es_admin_drosalud()", MIGRATION)
        self.assertIn("public.es_usuario_drosalud()", MIGRATION)

    def test_dispatch_retries_compare_the_persisted_lines(self):
        self.assertIn("from public.despachos_sucursal where operacion_id=p_operacion_id", MIGRATION)
        self.assertIn("v_hash_guardado is distinct from v_hash", MIGRATION)
        self.assertIn("El identificador de operación ya existe con cantidades diferentes", MIGRATION)

    def test_partial_receipts_accumulate_and_retry_from_ledger(self):
        self.assertIn("v_estado not in ('despachado','parcial')", MIGRATION)
        self.assertIn("unidades_recibidas=coalesce(unidades_recibidas,0)+v_qty", MIGRATION)
        self.assertIn("where operacion_id=p_operacion_id", MIGRATION)
        self.assertIn("v_hash_guardado is distinct from v_hash_solicitud", MIGRATION)
        self.assertIn("v_recibido+v_qty>v_enviado", MIGRATION)
        self.assertIn("recepcion_operacion_id=p_operacion_id", MIGRATION)

    def test_zero_only_receipt_is_rejected_for_durable_retry_identity(self):
        self.assertIn("La recepción debe incluir al menos una unidad positiva", MIGRATION)

    def test_no_new_transfer_tables_or_sales_functions_are_added(self):
        self.assertNotIn("create table public.despachos_sucursal_recepciones", MIGRATION)
        self.assertNotIn("create or replace function public.registrar_venta_drosalud", MIGRATION.lower())

    def test_seller_and_general_permission_grants_are_untouched(self):
        self.assertNotIn("grant execute on function public.registrar_venta_drosalud", MIGRATION.lower())
        self.assertNotIn("alter table public.usuarios_drosalud", MIGRATION.lower())

    def test_exact_receipt_retry_is_permitted_for_idempotency(self):
        self.assertRegex(MIGRATION, re.compile(
            r"new\.tipo='recepcion' and new\.operacion_id is not null and exists\([\s\S]*?"
            r"m\.costo_unitario_base is not distinct from new\.costo_unitario_base\s*\) then return new",
            re.IGNORECASE,
        ))

    def test_count_contract_uses_only_the_central_inventory(self):
        self.assertNotIn("p_bodega_id", API)
        self.assertNotIn("cf-warehouse", UI)
        self.assertNotIn("bodega_id", PRODUCTION_INSTALL)
        self.assertNotIn("inventario_sucursal_movimientos", PRODUCTION_INSTALL)
        self.assertNotIn("sucursal_id", PRODUCTION_INSTALL)

    def test_cutoff_and_inventory_lock_share_the_product_row(self):
        start = PRODUCTION_INSTALL.split("create or replace function public.iniciar_linea_conteo", 1)[1]
        start = start.split("$function$;", 1)[0]
        guard = PRODUCTION_INSTALL.split("create or replace function public.proteger_movimiento_durante_conteo", 1)[1]
        guard = guard.split("$function$;", 1)[0]
        self.assertIn("from public.productos where id=v_producto for update", start)
        self.assertIn("from public.inventario_movimientos m where m.producto_id=v_producto", start)
        self.assertIn("sum(m.unidades_delta)", start)
        self.assertIn("from public.productos p where p.id=new.producto_id for update", guard)
        self.assertIn("public.inventario_conteos_bloqueos b where b.producto_id=new.producto_id", guard)
        self.assertIn("using errcode='55P03'", guard)

    def test_approval_is_idempotent_and_writes_at_most_one_ledger_adjustment(self):
        approval = PRODUCTION_INSTALL.split("create or replace function public.aprobar_linea_conteo", 1)[1]
        approval = approval.split("$function$;", 1)[0]
        self.assertIn("if v_item.estado='aprobado' then", approval)
        self.assertIn("where tipo='ajuste' and referencia_id=p_item_id", approval)
        self.assertIn("insert into public.inventario_movimientos", approval)
        self.assertIn("update public.inventario_conteos_items set movimiento_id=v_movimiento", approval)
        self.assertIn("inventario_movimientos_ajuste_referencia_unica_idx", PRODUCTION_INSTALL)

    def test_count_locks_are_released_after_approval_or_cancellation(self):
        for source in (QA_CORRECTION, PRODUCTION_INSTALL):
            approval = source.split("create or replace function public.aprobar_linea_conteo", 1)[1]
            approval = approval.split("$function$;", 1)[0]
            cancel = source.split("create or replace function public.cancelar_conteo_inventario", 1)[1]
            cancel = cancel.split("$function$;", 1)[0]
            self.assertIn("delete from public.inventario_conteos_bloqueos where conteo_item_id=p_item_id", approval)
            self.assertIn("delete from public.inventario_conteos_bloqueos where conteo_id=p_conteo_id", cancel)

    def test_qa_correction_preserves_historical_rows_and_removes_warehouse_requirement(self):
        self.assertNotIn("create table", QA_CORRECTION.lower())
        self.assertIn("to_regclass('public.'||v_table)", QA_CORRECTION)
        self.assertIn("alter column bodega_id drop not null", QA_CORRECTION)
        self.assertIn("update public.inventario_conteos_bloqueos set bodega_id=null", QA_CORRECTION)
        self.assertIn("Hay varios bloqueos activos por producto", QA_CORRECTION)
        self.assertIn("to_regclass('public.inventario_conteos_bloqueos_central_product_uq')", QA_CORRECTION)
        schema_migration = QA_CORRECTION.split("create or replace function public.proteger_movimiento_durante_conteo", 1)[0].lower()
        for table in ("inventario_conteos", "inventario_conteos_items", "inventario_conteo_capturas", "inventario_movimientos"):
            self.assertNotRegex(schema_migration, rf"\b(?:delete\s+from|update)\s+public\.{table}\b")
        self.assertNotIn("drop table", schema_migration)
        self.assertIn("pg_get_functiondef('public.ps_sync_movimiento_inventario()'::regprocedure)", QA_CORRECTION)

    def test_count_rpc_bodies_are_independent_of_warehouse_objects(self):
        names = (
            "crear_conteo_inventario", "iniciar_linea_conteo", "guardar_conteo_fisico",
            "enviar_linea_conteo_a_revision", "registrar_reconteo_fisico",
            "aprobar_linea_conteo", "cancelar_conteo_inventario",
        )
        for name in names:
            body = QA_CORRECTION.split(f"create or replace function public.{name}", 1)[1]
            body = body.split("$function$;", 1)[0].lower()
            self.assertNotIn("bodega_id", body)
            self.assertNotIn("inventario_sucursal_movimientos", body)

    def test_production_install_does_not_change_existing_purchase_contracts(self):
        self.assertNotIn("registrar_recepcion_compra", PRODUCTION_INSTALL)
        self.assertNotIn("add column if not exists proveedor_id", PRODUCTION_INSTALL)
        self.assertNotIn("add column if not exists recepcion_compra_id", PRODUCTION_INSTALL)
        self.assertNotIn("add column if not exists costo_unitario_base", PRODUCTION_INSTALL)

    def test_kardex_rejects_update_delete_and_truncate(self):
        self.assertIn("before update or delete on public.inventario_movimientos", MIGRATION)
        self.assertIn("before truncate on public.inventario_movimientos", MIGRATION)
        self.assertIn("using errcode='55000'", MIGRATION)

    def test_failed_refresh_requires_refresh_before_further_mutations(self):
        self.assertIn("refreshStale=true", UI)
        self.assertIn("refreshStale&&!button.hasAttribute('data-cf-refresh')", UI)
        self.assertIn("if(refreshStale){e.preventDefault()", UI)
        self.assertIn("data-cf-refresh ${busy?'disabled':''}>Actualizar", UI)

    def test_rpc_retry_keeps_request_id_until_confirmed_success(self):
        self.assertIn("localStorage.setItem(key, id)", API)
        self.assertIn("localStorage.removeItem(request.key)", API)
        self.assertIn("Keep this request UUID so the user can retry safely after a lost response", API)


if __name__ == "__main__":
    unittest.main()
