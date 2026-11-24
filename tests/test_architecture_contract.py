import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
INDEX = (ROOT / "index.html").read_text(encoding="utf-8")
MODULES = ROOT / "modules"
SERVICES = ROOT / "services"


class ArchitectureContractTests(unittest.TestCase):
    def test_shared_runtime_loads_before_feature_modules(self):
        scripts = re.findall(r'<script[^>]*src=["\']([^"\']+)["\'][^>]*>', INDEX, re.I)
        self.assertIn("supabase.js", scripts)
        self.assertIn("base.js", scripts)
        self.assertLess(scripts.index("supabase.js"), scripts.index("base.js"))
        module_positions = [i for i, name in enumerate(scripts) if name.startswith("modules/")]
        self.assertTrue(module_positions)
        self.assertEqual(len([name for name in scripts if name.startswith("modules/")]), len(set(name for name in scripts if name.startswith("modules/"))))
        self.assertGreater(min(module_positions), scripts.index("base.js"))
        self.assertIn("domain/formatters.js", scripts)
        self.assertIn("domain/presentaciones.js", scripts)
        self.assertIn("domain/precios.js", scripts)
        self.assertIn("domain/dinero.js", scripts)
        self.assertGreater(scripts.index("domain/dinero.js"), scripts.index("domain/precios.js"))
        self.assertIn("services/ventas.js", scripts)
        self.assertGreater(scripts.index("services/ventas.js"), scripts.index("domain/dinero.js"))
        self.assertIn("services/caja.js", scripts)
        self.assertGreater(scripts.index("services/caja.js"), scripts.index("services/ventas.js"))
        self.assertIn("services/informes.js", scripts)
        self.assertGreater(scripts.index("services/informes.js"), scripts.index("services/caja.js"))
        self.assertIn("services/compras.js", scripts)
        self.assertGreater(scripts.index("services/compras.js"), scripts.index("services/informes.js"))
        self.assertIn("services/pedidos.js", scripts)
        self.assertGreater(scripts.index("services/pedidos.js"), scripts.index("services/compras.js"))
        self.assertIn("services/gestion-negocio.js", scripts)
        self.assertGreater(scripts.index("services/gestion-negocio.js"), scripts.index("services/pedidos.js"))
        self.assertGreater(scripts.index("domain/precios.js"), scripts.index("domain/presentaciones.js"))
        self.assertGreater(scripts.index("domain/presentaciones.js"), scripts.index("domain/formatters.js"))
        self.assertGreater(scripts.index("domain/formatters.js"), scripts.index("base.js"))
        inline_start = INDEX.index('<script>\n// Selección de entorno')
        for name in scripts:
            if name.startswith(("domain/", "services/")):
                self.assertLess(INDEX.index(f'<script src="{name}"></script>'), inline_start)

    def test_feature_modules_do_not_create_their_own_supabase_client(self):
        for path in sorted(MODULES.glob("*.js")):
            source = path.read_text(encoding="utf-8")
            self.assertNotRegex(
                source,
                r"\bcreateClient\s*\(",
                f"{path.relative_to(ROOT)} must use the shared Supabase client",
            )

    def test_feature_modules_do_not_use_es_module_imports_yet(self):
        # The current app is served as ordered static scripts, not bundled ES modules.
        # A migration to native modules must be deliberate and update the bootstrap contract.
        for path in sorted(MODULES.glob("*.js")):
            source = path.read_text(encoding="utf-8")
            self.assertNotRegex(source, r"(?m)^\s*import\s", f"Unexpected import in {path.name}")
            self.assertNotRegex(source, r"(?m)^\s*export\s", f"Unexpected export in {path.name}")

    def test_shared_formatters_are_pure_and_have_no_runtime_dependencies(self):
        source = (ROOT / "domain/formatters.js").read_text(encoding="utf-8")
        for forbidden in ("document.", "window.sb", "fetch(", "localStorage"):
            self.assertNotIn(forbidden, source)
        self.assertIn("window.DrosaludFormatters", source)

    def test_presentation_domain_is_independent_from_ui_and_database(self):
        source = (ROOT / "domain/presentaciones.js").read_text(encoding="utf-8")
        for forbidden in ("document.", "window.sb", "fetch(", "localStorage"):
            self.assertNotIn(forbidden, source)
        self.assertIn("window.DrosaludPresentations", source)

    def test_pricing_domain_is_independent_from_ui_and_database(self):
        source = (ROOT / "domain/precios.js").read_text(encoding="utf-8")
        for forbidden in ("document.", "window.sb", "fetch(", "localStorage"):
            self.assertNotIn(forbidden, source)
        self.assertIn("window.DrosaludPricing", source)

    def test_money_domain_is_independent_from_ui_and_database(self):
        source = (ROOT / "domain/dinero.js").read_text(encoding="utf-8")
        for forbidden in ("document.", "window.sb", "fetch(", "localStorage"):
            self.assertNotIn(forbidden, source)
        self.assertIn("window.DrosaludMoney", source)

    def test_sales_service_receives_supabase_as_an_explicit_dependency(self):
        source = (SERVICES / "ventas.js").read_text(encoding="utf-8")
        self.assertIn("clienteSupabase", source)
        self.assertNotIn("window.sb", source)
        self.assertNotIn("document.", source)

    def test_cash_service_receives_client_and_shell_has_no_direct_caja_queries(self):
        source = (SERVICES / "caja.js").read_text(encoding="utf-8")
        self.assertIn("cliente", source)
        self.assertNotIn("window.sb", source)
        self.assertNotIn("document.", source)
        start = INDEX.index("/*CAJA-INICIO*/")
        end = INDEX.index("/*CAJA-FIN*/", start)
        self.assertNotRegex(INDEX[start:end], r"sb\.(rpc|from)\s*\(")

    def test_reports_module_uses_injected_data_service(self):
        service = (SERVICES / "informes.js").read_text(encoding="utf-8")
        module = (MODULES / "informes.js").read_text(encoding="utf-8")
        self.assertIn("cliente.from", service)
        self.assertNotIn("window.sb", service)
        self.assertNotIn("document.", service)
        self.assertNotRegex(module, r"sb\.(rpc|from)\s*\(")
        self.assertIn("DrosaludReportsService.loadInventory", module)

    def test_purchase_module_delegates_writes_to_injected_service(self):
        service = (SERVICES / "compras.js").read_text(encoding="utf-8")
        module = (MODULES / "recepcion-mercancia.js").read_text(encoding="utf-8")
        self.assertIn("cliente", service)
        self.assertNotIn("window.sb", service)
        self.assertNotRegex(module, r"sb\.(rpc|from)\s*\(")
        self.assertIn("listarDatos", service)
        self.assertIn("DrosaludPurchasesService.listarDatos", module)
        self.assertIn("DrosaludPurchasesService.registrarDocumentoProveedor", module)
        self.assertIn("DrosaludPurchasesService.registrarRecepcionDocumentada", module)

    def test_orders_module_delegates_writes_to_injected_service(self):
        service = (SERVICES / "pedidos.js").read_text(encoding="utf-8")
        module = (MODULES / "pedidos.js").read_text(encoding="utf-8")
        self.assertIn("cliente", service)
        self.assertNotIn("window.sb", service)
        self.assertNotRegex(module, r"sb\.(rpc|from)\s*\(")
        self.assertIn("cargarDatosModulo", service)
        self.assertIn("cargarDatosSugerencia", service)
        self.assertIn("DrosaludOrdersService.cargarDatosModulo", module)
        self.assertIn("DrosaludOrdersService.cargarDatosSugerencia", module)
        for method in ("guardarPedido", "enviarPedido", "autorizarPedido", "rechazarPedido", "generarOrdenesCompra"):
            self.assertIn("DrosaludOrdersService." + method, module)

    def test_business_management_module_delegates_database_access(self):
        service = (SERVICES / "gestion-negocio.js").read_text(encoding="utf-8")
        module = (MODULES / "gestion-negocio.js").read_text(encoding="utf-8")
        self.assertIn("cliente", service)
        self.assertNotIn("window.sb", service)
        self.assertNotRegex(module, r"sb\.(rpc|from)\s*\(")
        for method in ("cargar", "guardarProveedor", "eliminarProveedor", "guardarCompra", "listarRecibos", "listarLineasRecibo", "registrarCotizacion"):
            self.assertIn("DrosaludBusinessManagementService." + method, module)

    def test_catalog_persistence_is_delegated_to_service(self):
        service = (SERVICES / "catalogo.js").read_text(encoding="utf-8")
        self.assertNotIn("window.sb", service)
        self.assertNotIn("document.", service)
        for method in ("actualizarPrecios", "habilitarFraccionamiento", "actualizarProducto", "crearProducto", "eliminarProducto", "listarAuditoriaProducto", "contarProductos", "importarProductos"):
            self.assertIn(method, service)
        self.assertNotRegex(INDEX, r"sb\.from\(['\"]productos['\"]\)")
        self.assertNotIn("sb.rpc('actualizar_precios_drosalud_con_motivo'", INDEX)
        self.assertNotIn("sb.rpc('habilitar_fraccionamiento_producto'", INDEX)
        scripts = re.findall(r'<script[^>]*src=["\']([^"\']+)["\'][^>]*>', INDEX, re.I)
        self.assertIn("services/catalogo.js", scripts)
        self.assertGreater(scripts.index("services/catalogo.js"), scripts.index("services/gestion-negocio.js"))

    def test_customer_data_access_is_delegated_to_service(self):
        service = (SERVICES / "clientes.js").read_text(encoding="utf-8")
        self.assertNotIn("window.sb", service)
        self.assertNotIn("document.", service)
        for method in ("listarClientes", "listarConsentimientos", "registrarConsentimiento", "actualizarCliente", "crearCliente", "listarComprasCliente", "listarLineasRecibo", "cargarResumenCompras", "anonimizarCliente"):
            self.assertIn(method, service)
        for table in ("clientes", "consentimientos_clientes"):
            self.assertNotRegex(INDEX, r"sb\.from\(['\"]" + table + r"['\"]\)")
        self.assertNotIn("sb.rpc('anonimizar_cliente_drosalud'", INDEX)
        scripts = re.findall(r'<script[^>]*src=["\']([^"\']+)["\'][^>]*>', INDEX, re.I)
        self.assertIn("services/clientes.js", scripts)
        self.assertGreater(scripts.index("services/clientes.js"), scripts.index("services/catalogo.js"))

    def test_help_covers_operational_modules_without_count_references(self):
        start = INDEX.index('id="v-ayuda"')
        end = INDEX.index('id="v-aju"', start)
        help_view = INDEX[start:end]
        for topic in ("Facturación POS", "Productos", "Clientes", "Pedidos", "Compras y proveedores", "Recepción", "Generar Kardex", "Informes y reportes", "Historial", "Cotizaciones", "Caja", "Ajustes", "Usuarios y permisos", "Exportaciones y respaldo"):
            self.assertIn(topic, help_view)
        self.assertNotRegex(help_view.lower(), r"conteo\s+(físico|fisico|inicial)")
        self.assertIn("No es una copia completa de la base de datos", help_view)
        self.assertIn("No contiene órdenes de compra", help_view)
        self.assertIn("no presenta un valor físico total", help_view)

    def test_reports_card_does_not_promise_unavailable_valuation(self):
        source = (MODULES / "informes.js").read_text(encoding="utf-8")
        self.assertIn("El valor total no está disponible", source)

    def test_services_do_not_create_or_capture_a_global_supabase_client(self):
        for path in sorted(SERVICES.glob("*.js")):
            source = path.read_text(encoding="utf-8")
            self.assertNotRegex(source, r"\bcreateClient\s*\(", f"{path.name} must receive the shared client")
            self.assertNotIn("window.sb", source, f"{path.name} must not capture a global client")
            self.assertNotIn("document.", source, f"{path.name} must not depend on the UI")

    def test_architecture_and_operating_guides_are_versioned(self):
        self.assertTrue((ROOT / "docs/ARQUITECTURA_Y_DEPENDENCIAS.md").is_file())
        self.assertTrue((ROOT / "docs/GUIA_OPERATIVA.md").is_file())


if __name__ == "__main__":
    unittest.main()
