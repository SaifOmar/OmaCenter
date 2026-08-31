#!/usr/bin/env python3
"""Unit tests for layout_manager.py"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add parent directory to path to import layout_manager
sys.path.insert(0, str(Path(__file__).parent.parent))
import layout_manager


class TestSchemaValidation(unittest.TestCase):
    """Test schema validation logic."""

    def test_valid_module(self):
        """A valid module should pass validation."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "toggle",
            "group": "connectivity",
            "width": "half",
            "entry": "Test.qml",
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNotNone(module)
        self.assertEqual(errors, [])
        self.assertEqual(module["id"], "test.module")

    def test_missing_required_field(self):
        """Module missing required fields should fail."""
        module_data = {"name": "Test"}
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNone(module)
        self.assertTrue(len(errors) > 0)
        self.assertIn("missing required field", errors[0])

    def test_invalid_type(self):
        """Module with invalid type should fail."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "invalid",
            "group": "connectivity",
            "width": "half",
            "entry": "Test.qml",
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNone(module)
        self.assertTrue(any("invalid type" in e for e in errors))

    def test_invalid_group(self):
        """Module with invalid group should fail."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "toggle",
            "group": "invalid",
            "width": "half",
            "entry": "Test.qml",
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNone(module)
        self.assertTrue(any("invalid group" in e for e in errors))

    def test_invalid_width(self):
        """Module with invalid width should fail."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "toggle",
            "group": "connectivity",
            "width": "invalid",
            "entry": "Test.qml",
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNone(module)
        self.assertTrue(any("invalid width" in e for e in errors))

    def test_expandable_requires_expanded_entry(self):
        """Expandable module without expandedEntry should fail."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "toggle",
            "group": "connectivity",
            "width": "half",
            "entry": "Test.qml",
            "expandable": True,
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNone(module)
        self.assertTrue(any("expandedEntry" in e for e in errors))

    def test_optional_fields_preserved(self):
        """Optional fields should be preserved in output."""
        module_data = {
            "id": "test.module",
            "name": "Test",
            "type": "toggle",
            "group": "connectivity",
            "width": "half",
            "entry": "Test.qml",
            "version": "1.0.0",
            "description": "A test module",
            "author": "test",
            "icon": "T",
            "iconInactive": "t",
            "expandable": True,
            "expandedEntry": "TestExpanded.qml",
        }
        module, errors = layout_manager.validate_schema(module_data, "test.json")
        self.assertIsNotNone(module)
        self.assertEqual(errors, [])
        self.assertEqual(module["version"], "1.0.0")
        self.assertEqual(module["description"], "A test module")
        self.assertEqual(module["author"], "test")
        self.assertEqual(module["icon"], "T")
        self.assertEqual(module["iconInactive"], "t")
        self.assertTrue(module["expandable"])
        self.assertEqual(module["expandedEntry"], "TestExpanded.qml")

    def test_root_not_object(self):
        """Non-object root should fail."""
        module, errors = layout_manager.validate_schema([], "test.json")
        self.assertIsNone(module)
        self.assertTrue(any("root must be a JSON object" in e for e in errors))


class TestConstraintValidation(unittest.TestCase):
    """Test constraint validation logic."""

    def test_valid_connectivity_group(self):
        """Valid connectivity group should pass."""
        modules = {
            "connectivity": [
                {"id": "mod1", "width": "half", "group": "connectivity"},
                {"id": "mod2", "width": "half", "group": "connectivity"},
            ],
            "focus": [],
            "controls": [],
        }
        valid, errors = layout_manager.validate_constraints(modules)
        self.assertEqual(len(valid["connectivity"]), 2)
        self.assertEqual(errors, {})

    def test_connectivity_wrong_width(self):
        """Connectivity module with full width should fail."""
        modules = {
            "connectivity": [
                {"id": "mod1", "width": "full", "group": "connectivity"},
            ],
            "focus": [],
            "controls": [],
        }
        valid, errors = layout_manager.validate_constraints(modules)
        self.assertEqual(len(valid["connectivity"]), 0)
        self.assertIn("mod1", errors)
        self.assertTrue(any("must have width 'half'" in e for e in errors["mod1"]))

    def test_connectivity_max_modules(self):
        """More than 4 connectivity modules should fail."""
        modules = {
            "connectivity": [
                {"id": f"mod{i}", "width": "half", "group": "connectivity"}
                for i in range(5)
            ],
            "focus": [],
            "controls": [],
        }
        valid, errors = layout_manager.validate_constraints(modules)
        self.assertEqual(len(valid["connectivity"]), 4)
        self.assertIn("mod4", errors)
        self.assertTrue(any("max 4 modules" in e for e in errors["mod4"]))

    def test_focus_wrong_width(self):
        """Focus module with full width should fail."""
        modules = {
            "connectivity": [],
            "focus": [
                {"id": "mod1", "width": "full", "group": "focus"},
            ],
            "controls": [],
        }
        valid, errors = layout_manager.validate_constraints(modules)
        self.assertEqual(len(valid["focus"]), 0)
        self.assertIn("mod1", errors)

    def test_controls_wrong_width(self):
        """Controls module with half width should fail."""
        modules = {
            "connectivity": [],
            "focus": [],
            "controls": [
                {"id": "mod1", "width": "half", "group": "controls"},
            ],
        }
        valid, errors = layout_manager.validate_constraints(modules)
        self.assertEqual(len(valid["controls"]), 0)
        self.assertIn("mod1", errors)
        self.assertTrue(any("must have width 'full'" in e for e in errors["mod1"]))


class TestConfigHandling(unittest.TestCase):
    """Test config reading and merging."""

    def test_read_valid_config(self):
        """Valid config should be read successfully."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump({"version": 1, "modules": [{"id": "test", "enabled": True, "order": 1}]}, f)
            f.flush()
            config, error = layout_manager.read_config(Path(f.name))
        os.unlink(f.name)
        self.assertIsNotNone(config)
        self.assertIsNone(error)

    def test_read_missing_config(self):
        """Missing config should return None, None."""
        config, error = layout_manager.read_config(Path("/nonexistent/config.json"))
        self.assertIsNone(config)
        self.assertIsNone(error)

    def test_read_invalid_json(self):
        """Invalid JSON should return error."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write("not valid json")
            f.flush()
            config, error = layout_manager.read_config(Path(f.name))
        os.unlink(f.name)
        self.assertIsNone(config)
        self.assertIsNotNone(error)

    def test_merge_auto_discovery(self):
        """Modules not in config should be auto-discovered."""
        discovered = {
            "mod1": ({"id": "mod1", "name": "Mod1", "type": "tile", "group": "controls", "width": "full", "entry": "a.qml"}, "/modules/mod1/module.json"),
            "mod2": ({"id": "mod2", "name": "Mod2", "type": "tile", "group": "controls", "width": "full", "entry": "b.qml"}, "/modules/mod2/module.json"),
        }
        config = {"modules": [{"id": "mod1", "enabled": True, "order": 1}]}
        merged, warnings = layout_manager.merge_config(discovered, config)
        self.assertEqual(len(merged), 2)
        self.assertTrue(any("auto-discovered" in w for w in warnings))

    def test_merge_unknown_module_in_config(self):
        """Config referencing unknown module should warn."""
        discovered = {}
        config = {"modules": [{"id": "unknown", "enabled": True, "order": 1}]}
        merged, warnings = layout_manager.merge_config(discovered, config)
        self.assertEqual(len(merged), 0)
        self.assertTrue(any("unknown module" in w for w in warnings))


class TestJsonOutput(unittest.TestCase):
    """Test JSON output formatting."""

    def test_write_json(self):
        """write_json should output valid JSON to stdout."""
        import io
        from contextlib import redirect_stdout
        f = io.StringIO()
        with redirect_stdout(f):
            layout_manager.write_json({"test": "value"})
        output = f.getvalue()
        parsed = json.loads(output)
        self.assertEqual(parsed["test"], "value")


class TestMainIntegration(unittest.TestCase):
    """Integration tests using actual fixture files."""

    def setUp(self):
        """Create a temporary directory with test fixtures."""
        self.test_dir = Path(tempfile.mkdtemp())
        self.fixtures_dir = Path(__file__).parent / "fixtures"

        # Copy fixtures to test directory
        import shutil
        shutil.copytree(self.fixtures_dir / "modules", self.test_dir / "modules")
        shutil.copytree(self.fixtures_dir / "extensions", self.test_dir / "extensions")

    def tearDown(self):
        """Clean up temporary directory."""
        import shutil
        shutil.rmtree(self.test_dir)

    def test_discover_modules(self):
        """Should discover all valid modules."""
        modules = layout_manager.discover_modules(self.test_dir)
        self.assertEqual(len(modules), 5)  # wifi, bluetooth, dnd, volume, calculator

    def test_full_render_plan(self):
        """Full render plan should include all valid modules."""
        # Copy config
        import shutil
        shutil.copy(self.fixtures_dir / "config.json", self.test_dir / "config.json")

        # Run main logic manually
        discovered = layout_manager.discover_modules(self.test_dir)
        config, _ = layout_manager.read_config(self.test_dir / "config.json")
        merged, _ = layout_manager.merge_config(discovered, config)

        modules_by_group = {"connectivity": [], "focus": [], "controls": []}
        for module in merged:
            if module.get("enabled", True):
                group = module["group"]
                if group in modules_by_group:
                    modules_by_group[group].append(module)

        valid_by_group, constraint_errors = layout_manager.validate_constraints(modules_by_group)
        valid_modules = []
        for group in ("connectivity", "focus", "controls"):
            valid_modules.extend(valid_by_group[group])

        plan = layout_manager.build_render_plan(valid_modules, constraint_errors)

        self.assertTrue(plan["ok"])
        self.assertEqual(len(plan["errors"]), 0)
        self.assertEqual(len(plan["modules"]), 5)  # wifi, bluetooth, dnd, volume, calculator

    def test_disabled_module_excluded(self):
        """Disabled module should not appear in render plan."""
        import shutil
        shutil.copy(self.fixtures_dir / "config_disable_module.json", self.test_dir / "config.json")

        discovered = layout_manager.discover_modules(self.test_dir)
        config, _ = layout_manager.read_config(self.test_dir / "config.json")
        merged, _ = layout_manager.merge_config(discovered, config)

        modules_by_group = {"connectivity": [], "focus": [], "controls": []}
        for module in merged:
            if module.get("enabled", True):
                group = module["group"]
                if group in modules_by_group:
                    modules_by_group[group].append(module)

        valid_by_group, constraint_errors = layout_manager.validate_constraints(modules_by_group)
        valid_modules = []
        for group in ("connectivity", "focus", "controls"):
            valid_modules.extend(valid_by_group[group])

        plan = layout_manager.build_render_plan(valid_modules, constraint_errors)

        self.assertNotIn("so.omacenter.wifi", plan["modules"])

    def test_unknown_config_module_warns(self):
        """Config with unknown module should produce warning."""
        import shutil
        shutil.copy(self.fixtures_dir / "config_unknown_module.json", self.test_dir / "config.json")

        discovered = layout_manager.discover_modules(self.test_dir)
        config, _ = layout_manager.read_config(self.test_dir / "config.json")
        merged, warnings = layout_manager.merge_config(discovered, config)

        self.assertTrue(any("nonexistent.module" in w for w in warnings))


if __name__ == "__main__":
    unittest.main()
