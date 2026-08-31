# Module Authoring API

Reference for creating built-in or third-party modules for OmaCenter.

## Quick Start

1. Create a directory: `modules/my-widget/` or `extensions/my-widget/`
2. Create `module.json`
3. Create the entry QML file
4. Optionally create an expanded QML file
5. Restart the panel (or wait for auto-discovery)

## module.json Schema

```json
{
  "id": "my-widget.greeter",
  "name": "Greeter",
  "version": "1.0.0",
  "description": "A friendly greeting tile",
  "author": "you",
  "type": "tile",
  "group": "controls",
  "width": "full",
  "entry": "GreeterTile.qml",
  "expandable": false
}
```

### Required Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier. Built-in: `so.omacenter.*`. Third-party: use your namespace. |
| `name` | string | Display name shown in the panel and config. |
| `type` | string | One of: `toggle`, `tile`, `slider`, `media`, `custom` |
| `group` | string | One of: `connectivity`, `focus`, `controls` |
| `width` | string | One of: `half`, `full` |
| `entry` | string | QML filename for the collapsed view |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `version` | string | Semver version string |
| `description` | string | Short description |
| `author` | string | Author name |
| `icon` | string | Icon glyph (Nerd Font) |
| `iconInactive` | string | Icon glyph when inactive |
| `expandable` | boolean | Can this module take over the full panel? |
| `expandedEntry` | string | QML filename for the expanded view |

### Type Reference

| Type | Layout | Use case |
|---|---|---|
| `toggle` | Circle in 2×2 grid | On/off controls (WiFi, Bluetooth) |
| `tile` | Icon + text tile | Status displays (DnD, Night Light) |
| `slider` | Full-width slider | Adjustable values (Volume, Brightness) |
| `media` | Album art + controls | Media playback |
| `custom` | Full-width, any content | Custom layouts |

### Group Reference

| Group | Grid | Width constraint | Max modules |
|---|---|---|---|
| `connectivity` | 2×2 | Must be `half` | 4 |
| `focus` | Paired row | Must be `half` | 2 |
| `controls` | Stacked rows | Must be `full` | ~8 |

## Module QML Interface

### Minimal Module

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  // Required: panel reference (injected by ModuleHost)
  property var panel: null

  // Required: module ID
  readonly property string moduleId: "my-widget.greeter"

  // Visual content
  Text {
    anchors.centerIn: parent
    text: "Hello from " + root.moduleId
    color: root.panel.fg
  }
}
```

### Properties Injected by ModuleHost

| Property | Type | Description |
|---|---|---|
| `panel` | var | Reference to root Panel instance |

### Properties Module Must Expose

| Property | Type | Description |
|---|---|---|
| `moduleId` | string (readonly) | Unique module identifier |

### Available Imports

```qml
import qs.Commons   // Color, Style, Util, Border
import qs.Ui        // Tile, CursorSurface, PanelSlider, etc.
```

### Accessing Services via Panel

| Access | Type | Description |
|---|---|---|
| `panel.sink` | PipeWire node | Default audio sink |
| `panel.source` | PipeWire node | Default audio source |
| `panel.adapter` | Bluetooth adapter | Default BT adapter |
| `panel.bar` | QtObject | Shell bar reference |
| `panel.fg` | color | Popup foreground color |
| `panel.accent` | color | Accent color |
| `panel.hoverFill` | color | Hover state fill |
| `panel.selectedFill` | color | Selected state fill |
| `panel.onAccent(c)` | function | Returns black or white for contrast on accent |
| `panel.summonPanel(id)` | function | Open another Omarchy panel |

### Styling Conventions

```qml
// Spacing
width: Style.space(34)
anchors.margins: Style.space(8)

// Colors
color: Util.alpha(root.panel.fg, 0.13)
color: Util.alpha(root.panel.fg, 0.62)

// Typography
font.family: root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
font.pixelSize: Style.font.caption   // small
font.pixelSize: Style.font.body      // normal
font.pixelSize: Style.font.title     // large
font.pixelSize: Style.font.icon      // icon size

// Corners
radius: Style.space(14)             // tile corners
radius: width / 2                   // circle corners
```

## Expanded View

Modules with `expandable: true` can provide an expanded view.

### Expanded QML Interface

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  readonly property string moduleId: "my-widget.greeter"

  // Optional: header actions (placed in ModuleHost's header row)
  component HeaderActions: Rectangle {
    width: Style.space(34)
    height: width
    radius: width / 2
    color: Util.alpha(root.panel.fg, 0.13)
    // ... your header action (power toggle, settings, etc.)
  }

  // Content fills below the standard back button
  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    // Your expanded content here
  }
}
```

### What ModuleHost Provides (Expanded Mode)

- Standard back button: `← ModuleName`
- Consistent styling and spacing
- Collapse on back button click or Escape key

### What Module Provides (Expanded Mode)

- Content below the header
- Optional `HeaderActions` component for header row items
- All state, helpers, timers, processes

## Error Handling

If a module's QML file has errors or missing required properties, the layout engine catches it and shows an ErrorTile instead. The rest of the panel keeps working.

Common errors that trigger ErrorTile:
- Missing `moduleId` property
- Missing `panel` property
- QML syntax errors
- Missing required imports
