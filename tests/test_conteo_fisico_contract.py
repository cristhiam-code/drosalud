import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261119120000_conteo_fisico_inventario.sql").read_text()
UI = (ROOT / "modules/conteo-fisico.js").read_text()
API = (ROOT / "modules/conteo-fisico-api.js").read_text()


class PhysicalCountContractTests(unittest.TestCase):
    def test_kardex_types_include_existing_and_adjustment_types(self):
        self.assertRegex(MIGRATION, r"check\s*\(tipo in \('venta','anulacion','recepcion','saldo_inicial','ajuste'\)\)")
        self.assertIn("tipo in ('saldo_inicial','ajuste')", MIGRATION)

    def test_purchase_metadata_columns_and_foreign_keys_match_qa(self):
        self.assertRegex(MIGRATION, r"add column if not exists proveedor_id uuid,\s*add column if not exists recepcion_compra_id uuid,\s*add column if not exists costo_unitario_base numeric")
        self.assertIn("foreign key (proveedor_id) references public.proveedores(id)", MIGRATION)
        self.assertIn("foreign key (recepcion_compra_id) references public.recepciones_compra(id)", MIGRATION)

    def test_movement_guard_serializes_and_rejects_protected_product(self):
        self.assertRegex(MIGRATION, r"from public\.productos p where p\.id=new\.producto_id for update")
        self.assertIn("inventario_conteos_bloqueos b where b.producto_id=new.producto_id", MIGRATION)
        self.assertIn("using errcode='55P03'", MIGRATION)

    def test_exact_receipt_retry_is_permitted_for_idempotency(self):
        self.assertRegex(MIGRATION, re.compile(
            r"new\.tipo='recepcion' and new\.operacion_id is not null and exists\([\s\S]*?"
            r"m\.costo_unitario_base is not distinct from new\.costo_unitario_base\s*\) then return new",
            re.IGNORECASE,
        ))

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
