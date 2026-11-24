import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
INDEX = (ROOT / "index.html").read_text(encoding="utf-8")
MODULES = ROOT / "modules"


class ArchitectureContractTests(unittest.TestCase):
    def test_shared_runtime_loads_before_feature_modules(self):
        scripts = re.findall(r'<script[^>]*src=["\']([^"\']+)["\'][^>]*>', INDEX, re.I)
        self.assertIn("supabase.js", scripts)
        self.assertIn("base.js", scripts)
        self.assertLess(scripts.index("supabase.js"), scripts.index("base.js"))
        module_positions = [i for i, name in enumerate(scripts) if name.startswith("modules/")]
        self.assertTrue(module_positions)
        self.assertGreater(min(module_positions), scripts.index("base.js"))

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
            self.assertNotRegex(source, r"^\s*import\s", f"Unexpected import in {path.name}")
            self.assertNotRegex(source, r"^\s*export\s", f"Unexpected export in {path.name}")

    def test_architecture_and_operating_guides_are_versioned(self):
        self.assertTrue((ROOT / "docs/ARQUITECTURA_Y_DEPENDENCIAS.md").is_file())
        self.assertTrue((ROOT / "docs/GUIA_OPERATIVA.md").is_file())


if __name__ == "__main__":
    unittest.main()
