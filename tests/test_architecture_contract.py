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
        self.assertGreater(scripts.index("domain/precios.js"), scripts.index("domain/presentaciones.js"))
        self.assertGreater(scripts.index("domain/presentaciones.js"), scripts.index("domain/formatters.js"))
        self.assertGreater(scripts.index("domain/formatters.js"), scripts.index("base.js"))
        inline_start = INDEX.index('<script>\n// Selección de entorno')
        for name in scripts:
            if name.startswith("domain/"):
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

    def test_architecture_and_operating_guides_are_versioned(self):
        self.assertTrue((ROOT / "docs/ARQUITECTURA_Y_DEPENDENCIAS.md").is_file())
        self.assertTrue((ROOT / "docs/GUIA_OPERATIVA.md").is_file())


if __name__ == "__main__":
    unittest.main()
