import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261124120000_autorizar_diferencia_costo_recepcion.sql").read_text()


class PurchaseReceiptContractTests(unittest.TestCase):
    def test_document_line_must_match_ordered_product_before_receiving(self):
        body = MIGRATION.lower()
        product_match = "v_doc_item.producto_id is distinct from v_orden_item.producto_id"
        rejection = "el producto del documento no coincide con el producto de la orden"
        base_reception = "public.registrar_recepcion_compra("

        self.assertIn(product_match, body)
        self.assertIn(rejection, body)
        self.assertLess(body.index(product_match), body.index(base_reception))
        self.assertLess(body.index(rejection), body.index(base_reception))

    def test_same_operation_is_serialized_before_idempotency_lookup(self):
        body = MIGRATION.lower()
        lock = "pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacion_id::text,0))"
        lookup = "where operacion_id=p_operacion_id"
        self.assertIn(lock, body)
        self.assertLess(body.index(lock), body.index(lookup))

    def test_cost_difference_requires_admin_and_reason_before_receiving(self):
        body = MIGRATION.lower()
        cost_check = "pg_catalog.abs(v_doc_item.costo_unitario_base - v_orden_item.costo_unitario_base) > 0.01"
        admin_check = "if not public.es_admin_drosalud() then"
        reason_check = "if nullif(pg_catalog.btrim(p_notas),'') is null then"
        base_reception = "public.registrar_recepcion_compra("
        self.assertIn(cost_check, body)
        self.assertIn(admin_check, body)
        self.assertIn(reason_check, body)
        self.assertLess(body.index(cost_check), body.index(base_reception))
        self.assertLess(body.index(admin_check), body.index(base_reception))
        self.assertLess(body.index(reason_check), body.index(base_reception))

    def test_existing_supplier_quantity_cost_and_presentation_checks_remain(self):
        body = MIGRATION.lower()
        self.assertIn("v_doc_proveedor <> v_proveedor", body)
        self.assertIn("v_ya_recibido + (v_item->>'unidades')::integer > v_doc_item.unidades_documentadas", body)
        self.assertIn("v_factor <> v_doc_item.unidades_por_presentacion", body)
        self.assertIn("v_doc_item.costo_unitario_base", body)

    def test_retry_idempotency_contract_remains(self):
        body = MIGRATION.lower()
        self.assertIn("where operacion_id=p_operacion_id", body)
        self.assertIn("v_hash_existente is distinct from v_hash_solicitado", body)
        self.assertIn("return v_recepcion", body)


if __name__ == "__main__":
    unittest.main()
