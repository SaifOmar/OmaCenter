#!/usr/bin/env python3
"""OmaCenter layout manager.

Scans module descriptors, validates them against schema and constraints,
reads user config, and outputs a JSON render plan to stdout.

Called from QML via Process:
  Process {
    command: ["python3", "layout_manager.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { var plan = JSON.parse(text) }
    }
  }
"""

import json
import os
import sys
from pathlib import Path

# ── Schema constants ────────────────────────────────────────────────────────

VALID_TYPES = {"toggle", "tile", "slider", "media", "custom"}
VALID_GROUPS = {"connectivity", "focus", "controls"}
VALID_WIDTHS = {"half", "full"}

REQUIRED_FIELDS = {"id", "name", "type", "group", "width", "entry"}
OPTIONAL_FIELDS = {"version", "description", "author", "icon", "iconInactive",
                   "expandable", "expandedEntry", "gridSlot"}

# ── Group constraints ───────────────────────────────────────────────────────

GROUP_CONSTRAINTS = {
    "connectivity": {"width": "half", "max": 4},
    "focus":        {"width": "half", "max": 6},
    "controls":     {"width": "full", "max": 8},
}


# ── Helpers ─────────────────────────────────────────────────────────────────

def read_json(path):
    """Read and parse a JSON file. Returns (data, error_string)."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f), None
    except json.JSONDecodeError as e:
        return None, f"Invalid JSON: {e}"
    except OSError as e:
        return None, f"Cannot read file: {e}"


def write_json(data):
    """Write JSON to stdout."""
    print(json.dumps(data, indent=2))


# ── Schema validation ───────────────────────────────────────────────────────

def validate_schema(module_data, path):
    """Validate a module.json against the schema.

    Returns (valid_module_dict_or_None, list_of_error_strings).
    """
    errors = []

    if not isinstance(module_data, dict):
        return None, [f"{path}: root must be a JSON object"]

    # Check required fields
    for field in REQUIRED_FIELDS:
        if field not in module_data:
            errors.append(f"{path}: missing required field '{field}'")

    if errors:
        return None, errors

    # Validate types
    module_type = module_data.get("type", "")
    if module_type not in VALID_TYPES:
        errors.append(f"{path}: invalid type '{module_type}' (must be one of: {', '.join(sorted(VALID_TYPES))})")

    group = module_data.get("group", "")
    if group not in VALID_GROUPS:
        errors.append(f"{path}: invalid group '{group}' (must be one of: {', '.join(sorted(VALID_GROUPS))})")

    width = module_data.get("width", "")
    if width not in VALID_WIDTHS:
        errors.append(f"{path}: invalid width '{width}' (must be one of: {', '.join(sorted(VALID_WIDTHS))})")

    # Validate expandable fields
    expandable = module_data.get("expandable", False)
    if expandable and "expandedEntry" not in module_data:
        errors.append(f"{path}: expandable module must have 'expandedEntry' field")

    # Validate gridSlot
    grid_slot = module_data.get("gridSlot")
    if grid_slot is not None:
        if group == "connectivity":
            if not isinstance(grid_slot, int) or grid_slot not in (0, 1, 2, 3):
                errors.append(f"{path}: gridSlot must be 0-3 for connectivity group (got {grid_slot})")
        else:
            errors.append(f"{path}: gridSlot is only valid for connectivity group")

    if errors:
        return None, errors

    # Build clean module dict
    module = {
        "id": module_data["id"],
        "name": module_data["name"],
        "type": module_type,
        "group": group,
        "width": width,
        "entry": module_data["entry"],
    }

    # Add optional fields
    for field in OPTIONAL_FIELDS:
        if field in module_data:
            module[field] = module_data[field]

    return module, []


# ── Constraint validation ───────────────────────────────────────────────────

def validate_constraints(modules_by_group):
    """Validate group constraints (width matching, max count, gridSlot uniqueness).

    Returns (valid_modules_by_group, list_of_error_strings).
    """
    errors = {}
    valid = {}

    for group, constraints in GROUP_CONSTRAINTS.items():
        modules = modules_by_group.get(group, [])
        valid[group] = []
        count = 0
        used_slots = set()

        for module in modules:
            module_id = module["id"]
            expected_width = constraints["width"]

            if module["width"] != expected_width:
                errors.setdefault(module_id, []).append(
                    f"module '{module_id}' in group '{group}' must have width '{expected_width}' "
                    f"(has '{module['width']}')"
                )
                continue

            if count >= constraints["max"]:
                errors.setdefault(module_id, []).append(
                    f"group '{group}' allows max {constraints['max']} modules"
                )
                continue

            # Validate gridSlot uniqueness within group
            grid_slot = module.get("gridSlot")
            if grid_slot is not None:
                if grid_slot in used_slots:
                    errors.setdefault(module_id, []).append(
                        f"gridSlot {grid_slot} in group '{group}' is already taken"
                    )
                    continue
                used_slots.add(grid_slot)

            valid[group].append(module)
            count += 1

    return valid, errors


# ── Module discovery ────────────────────────────────────────────────────────

def discover_modules(base_dir):
    """Scan modules/ and extensions/ for module.json files.

    Returns dict of {module_id: (module_dict, path)}.
    """
    modules = {}
    for sub_dir in ("modules", "extensions"):
        dir_path = base_dir / sub_dir
        if not dir_path.is_dir():
            continue
        for entry in sorted(dir_path.iterdir()):
            if not entry.is_dir():
                continue
            module_json = entry / "module.json"
            if not module_json.is_file():
                continue
            data, error = read_json(module_json)
            if error:
                print(f"Warning: {error}", file=sys.stderr)
                continue
            module, schema_errors = validate_schema(data, str(module_json))
            if schema_errors:
                for err in schema_errors:
                    print(f"Warning: {err}", file=sys.stderr)
                continue
            module["dir"] = str(entry.relative_to(base_dir))
            modules[module["id"]] = (module, str(module_json))

    return modules


# ── Config handling ─────────────────────────────────────────────────────────

def read_config(config_path):
    """Read config.json. Returns (config_dict, error_string_or_None)."""
    if not config_path.exists():
        return None, None  # Missing config is OK, will auto-generate

    data, error = read_json(config_path)
    if error:
        return None, error

    if not isinstance(data, dict):
        return None, "config.json must be a JSON object"

    if "modules" not in data or not isinstance(data["modules"], list):
        return None, "config.json must have a 'modules' array"

    return data, None


def merge_config(discovered_modules, config):
    """Merge discovered modules with user config.

    Returns (merged_list, list_of_warnings).
    """
    warnings = []
    config_modules = {m["id"]: m for m in config.get("modules", [])} if config else {}

    merged = []
    order_counter = 1000  # Default order for auto-discovered modules

    # First, add modules from config (preserving user order)
    if config:
        for cfg_mod in config.get("modules", []):
            mod_id = cfg_mod.get("id", "")
            if mod_id in discovered_modules:
                module, path = discovered_modules[mod_id]
                enabled = cfg_mod.get("enabled", True)
                order = cfg_mod.get("order", order_counter)
                merged.append({
                    **module,
                    "enabled": enabled,
                    "order": order,
                    "builtin": "modules" in path,
                })
            else:
                warnings.append(f"config references unknown module '{mod_id}'")

    # Then, add auto-discovered modules not in config
    for mod_id, (module, path) in discovered_modules.items():
        if mod_id not in config_modules:
            order_counter += 1
            merged.append({
                **module,
                "enabled": True,
                "order": order_counter,
                "builtin": "modules" in path,
            })
            warnings.append(f"auto-discovered new module '{mod_id}'")

    # Sort by order
    merged.sort(key=lambda m: m.get("order", 9999))

    return merged, warnings


# ── Render plan ─────────────────────────────────────────────────────────────

def build_render_plan(modules, constraint_errors):
    """Build the final render plan from validated modules.

    Returns render plan dict.
    """
    plan = {
        "ok": True,
        "modules": {},
        "layout": {
            "connectivity": [],
            "focus": [],
            "controls": [],
        },
        "errors": [],
        "warnings": [],
    }

    for module in modules:
        if not module.get("enabled", True):
            continue

        mod_id = module["id"]
        group = module["group"]

        # Check for constraint errors on this module
        if mod_id in constraint_errors:
            for err in constraint_errors[mod_id]:
                plan["errors"].append(err)
            continue

        # Add to plan
        plan["modules"][mod_id] = {
            "id": mod_id,
            "name": module["name"],
            "type": module["type"],
            "group": group,
            "width": module["width"],
            "entry": module["entry"],
            "expandable": module.get("expandable", False),
            "builtin": module.get("builtin", False),
            "order": module.get("order", 9999),
        }

        if "expandedEntry" in module:
            plan["modules"][mod_id]["expandedEntry"] = module["expandedEntry"]

        if "icon" in module:
            plan["modules"][mod_id]["icon"] = module["icon"]

        if "iconInactive" in module:
            plan["modules"][mod_id]["iconInactive"] = module["iconInactive"]

        if "gridSlot" in module:
            plan["modules"][mod_id]["gridSlot"] = module["gridSlot"]

        if "dir" in module:
            plan["modules"][mod_id]["dir"] = module["dir"]

        plan["layout"][group].append(mod_id)

    return plan


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    # Determine base directory (same dir as this script)
    base_dir = Path(__file__).resolve().parent
    config_path = base_dir / "config.json"

    # 1. Discover all modules
    discovered = discover_modules(base_dir)

    if not discovered:
        write_json({
            "ok": True,
            "modules": {},
            "layout": {"connectivity": [], "focus": [], "controls": []},
            "errors": [],
            "warnings": ["no modules found"],
        })
        return

    # 2. Read user config
    config, config_error = read_config(config_path)
    if config_error:
        print(f"Warning: {config_error}", file=sys.stderr)
        config = None  # Will auto-generate from discovered modules

    # 3. Merge discovered modules with config
    merged, merge_warnings = merge_config(discovered, config)

    # 4. Group modules and validate constraints
    modules_by_group = {"connectivity": [], "focus": [], "controls": []}
    for module in merged:
        if module.get("enabled", True):
            group = module["group"]
            if group in modules_by_group:
                modules_by_group[group].append(module)

    valid_by_group, constraint_errors = validate_constraints(modules_by_group)

    # 5. Flatten valid modules back to ordered list
    valid_modules = []
    for group in ("connectivity", "focus", "controls"):
        valid_modules.extend(valid_by_group[group])

    # 6. Build render plan
    plan = build_render_plan(valid_modules, constraint_errors)
    plan["warnings"].extend(merge_warnings)

    write_json(plan)


if __name__ == "__main__":
    main()
