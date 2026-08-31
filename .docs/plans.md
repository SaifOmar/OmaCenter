# OmaCenter — Modular Architecture Plan

## Overview

Transform the monolithic 2280-line Panel.qml into a configurable module system where each control is a self-contained module. Users enable/disable/reorder modules via a JSON config. Third-party QML extensions can be dropped into an `extensions/` directory.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  config.json │────▶│  layout_manager.py│────▶│  render_plan │
│  (user prefs)│     │  (validator)      │     │  (JSON)      │
└─────────────┘     └──────────────────┘     └──────┬──────┘
                                                     │
                                              ┌──────▼──────┐
                                              │  Panel.qml   │
                                              │  (renderer)  │
                                              └─────────────┘
```

**Flow:** QML calls `python3 layout_manager.py` via Process → script reads module descriptors + user config → validates constraints → outputs JSON render plan to stdout → QML parses and renders.

## Module Descriptor Format

Each module (built-in or third-party) declares itself via `module.json`:

```json
{
  "id": "saif.cc.wifi",
  "name": "Wi-Fi",
  "version": "1.0.0",
  "description": "Toggle Wi-Fi and manage networks",
  "author": "saif",
  "type": "toggle",
  "group": "connectivity",
  "icon": "󰤨",
  "iconInactive": "󰤭",
  "width": "half",
  "entry": "WifiToggle.qml",
  "expandable": true,
  "expandedEntry": "WifiPanel.qml"
}
```

### Fields

| Field | Values | Purpose |
|---|---|---|
| `type` | `toggle`, `tile`, `slider`, `media`, `custom` | Base component + layout behavior |
| `group` | `connectivity`, `focus`, `controls` | Layout zone |
| `width` | `half`, `full` | Grid width — `half` = 2-per-row, `full` = spans both columns |
| `entry` | QML filename | Collapsed view component |
| `expandable` | boolean | Can this module take over the full panel? |
| `expandedEntry` | QML filename | Expanded view component (optional) |

### Group Rules

- `connectivity` → rendered in a 2×2 grid (WiFi, BT, Tailscale, Mic)
- `focus` → paired in a 2-column row (DnD, NightLight)
- `controls` → full-width stacked rows (sliders, media, theme, power)

## User Config Format

`config.json` (same directory as Panel.qml):

```json
{
  "version": 1,
  "modules": [
    { "id": "so.omacenter.wifi", "enabled": true, "order": 1 },
    { "id": "so.omacenter.bluetooth", "enabled": true, "order": 2 },
    { "id": "so.omacenter.tailscale", "enabled": true, "order": 3 },
    { "id": "so.omacenter.mic", "enabled": true, "order": 4 },
    { "id": "so.omacenter.dnd", "enabled": true, "order": 11 },
    { "id": "so.omacenter.nightlight", "enabled": true, "order": 12 },
    { "id": "so.omacenter.volume", "enabled": true, "order": 21 },
    { "id": "so.omacenter.brightness", "enabled": true, "order": 22 },
    { "id": "so.omacenter.media", "enabled": true, "order": 31 },
    { "id": "so.omacenter.theme", "enabled": true, "order": 41 },
    { "id": "so.omacenter.power", "enabled": true, "order": 51 }
  ]
}
```

Modules sorted by `order` within their group. Users reorder by changing order values, disable by setting `enabled: false`.

## Layout Engine (Python)

`layout_manager.py` — called from QML via Process, outputs JSON to stdout.

### Responsibilities
1. Scan `modules/*/module.json` and `extensions/*/module.json`
2. Read `config.json`
3. Validate schema (required fields, valid types/groups)
4. Validate constraints (connectivity = half width, max 4, etc.)
5. Auto-discover new modules not in config
6. Output render plan with valid modules + errors

### Render Plan Output

```json
{
  "ok": true,
  "modules": {
    "so.omacenter.wifi": {
      "id": "so.omacenter.wifi",
      "name": "Wi-Fi",
      "type": "toggle",
      "group": "connectivity",
      "width": "half",
      "entry": "modules/wifi/WifiToggle.qml",
      "expandable": true,
      "expandedEntry": "modules/wifi/WifiPanel.qml",
      "builtin": true,
      "order": 1
    }
  },
  "layout": {
    "connectivity": ["so.omacenter.wifi", "so.omacenter.bluetooth", "so.omacenter.tailscale", "so.omacenter.mic"],
    "focus": ["so.omacenter.dnd", "so.omacenter.nightlight"],
    "controls": ["so.omacenter.volume", "so.omacenter.brightness", "so.omacenter.media", "so.omacenter.theme", "so.omacenter.power"]
  },
  "errors": [],
  "warnings": []
}
```

## Module QML Interface

### ModuleHost Contract

Every module component receives from ModuleHost:

```qml
property var    panel       // reference to root Panel (services, bar, colors)
property string moduleDir   // path to this module's directory
```

### Module must expose

```qml
readonly property string moduleId: "so.omacenter.wifi"
```

### Available imports

```qml
import qs.Commons  // Color, Style, Util, Border
import qs.Ui       // Tile, CursorSurface, PanelSlider, etc.
```

### Available via panel reference

- `panel.sink` — PipeWire default audio sink
- `panel.source` — PipeWire default audio source
- `panel.adapter` — Bluetooth adapter
- `panel.bar` — shell bar reference
- `panel.fg`, `panel.accent`, `panel.hoverFill`, `panel.selectedFill`
- `panel.onAccent(color)` — pick black/white text for accent fill
- `panel.summonPanel(pluginId)` — open another Omarchy panel

## Expandable Sub-Modules

Modules with `expandable: true` can take over the full panel when right-clicked.

### How it works

1. Module declares `expandable: true` + `expandedEntry` in module.json
2. User right-clicks the module's tile
3. Panel.qml sets `expandedModuleId = "saif.cc.wifi"`
4. Main grid hides, ModuleHost switches to expanded mode
5. ModuleHost renders: standard back button + module's expanded content
6. User clicks back or presses Escape → collapses

### Back button

**Always provided by ModuleHost.** Modules never render their own back button. This ensures consistency across all modules (built-in and third-party).

### ModuleHost expanded layout

```
┌──────────────────────────────────────┐
│ ← ModuleName           [actions]    │  ← ModuleHost provides
│                                      │
│  Module's expanded content goes      │  ← expandedEntry fills
│  here (network list, device list,    │     this area
│  mixer controls, etc.)               │
└──────────────────────────────────────┘
```

### Header actions slot

Expanded modules can inject optional header actions (power toggle, settings gear) via a `HeaderActions` component that ModuleHost places in the header row.

## Error Handling

- Per-module: one bad module doesn't break others
- Schema errors → module excluded, ErrorTile shown
- Constraint violations → module excluded, error message displayed
- Missing entry file → module renders with warning
- Config parse failure → panel uses defaults (all discovered modules enabled)
- Config.json missing → auto-generated from discovered modules

### ErrorTile

Red-tinted tile showing module name + error message. Rendered by the layout engine when a module has validation errors.

## Third-Party Extensions

### Discovery

Scans `extensions/*/module.json`. New modules auto-added to config as enabled.

### Authoring

1. Create `extensions/my-widget/`
2. Create `module.json` (id, name, type, group, width, entry)
3. Create entry QML file with `property var panel` and `readonly property string moduleId`
4. Optionally create expanded QML file
5. Use `import qs.Commons` and `import qs.Ui` for styling
6. Access services via `panel.*`
7. Restart panel or wait for auto-discovery

## Target File Structure

```
omacenter/
  manifest.json
  Panel.qml                    (~350 lines: layout engine + lifecycle)
  Model.js
  config.json                  (auto-generated if missing)
  layout_manager.py            (~250 lines)

  base/
    ModuleHost.qml             (collapsed + expanded + back button)

  shared/
    Tile.qml
    CircleToggle.qml
    IconTile.qml
    SliderTile.qml
    MiniButton.qml
    ErrorTile.qml

  modules/
    wifi/module.json + WifiToggle.qml + WifiPanel.qml
    bluetooth/module.json + BluetoothToggle.qml + BluetoothPanel.qml
    tailscale/module.json + TailscaleToggle.qml
    mic/module.json + MicToggle.qml
    dnd/module.json + DndTile.qml
    nightlight/module.json + NightLightTile.qml
    volume/module.json + VolumeSlider.qml
    brightness/module.json + BrightnessSlider.qml
    media/module.json + MediaTile.qml
    theme/module.json + ThemeTile.qml
    power/module.json + PowerRow.qml

  extensions/
    README.md
```
