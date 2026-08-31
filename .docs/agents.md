# OmaCenter — Agent Context

## Project Summary

OmaCenter (`so.omacenter`) is a macOS-style Control Center panel widget for the Omarchy Linux desktop shell. It consolidates system controls — connectivity toggles, focus modes, audio/display sliders, media playback, theming, and power actions — into a single frosted-glass popup panel accessible from the Omarchy top bar.

**Current state:** Monolithic single-file plugin (Panel.qml ~2280 lines + Model.js ~542 lines). Being refactored into a modular, extensible system.

## Tech Stack

| Layer | Technology |
|---|---|
| Shell framework | Quickshell (Qt6-based Wayland shell) |
| UI language | QML (Qt Quick / QtQuick.Controls) |
| Logic layer | JavaScript (Model.js) |
| Layout validator | Python (layout_manager.py, planned) |
| Services | Quickshell.Networking, Quickshell.Bluetooth, Quickshell.Services.Pipewire, Quickshell.Services.Mpris |
| External tools | omarchy-brightness-display, omarchy-bluetooth-*, omarchy-audio-*, tailscale, systemctl |

## File Map

```
omacenter/
  manifest.json          — Plugin manifest (schema v1, id: so.omacenter, kind: bar-widget)
  Panel.qml              — Main UI: ~2280 lines, everything lives here
  Model.js               — Pure-JS helpers: ~542 lines (network, bluetooth, formatting)
  .docs/                 — Project documentation (this directory)
  .opencode/             — AI development workspace (gitignored)
```

### Panel.qml Structure (current monolith)

| Lines | Section |
|---|---|
| 1-12 | Imports |
| 14-18 | Root Panel declaration |
| 20-49 | Service bindings (notifications, nightlight, pipewire, bluetooth, mpris) |
| 51-131 | State properties (brightness, theme, tailscale, wifi, bluetooth, cursor) |
| 133-191 | Derived properties + helpers (luminance, onAccent) |
| 199-269 | Keyboard cursor system (targets, moveCursor, activateCursor) |
| 271-310 | Quick toggles (wifi, bluetooth, tailscale, nightlight, dnd, mic) + summonPanel |
| 312-447 | Bluetooth sub-panel helpers |
| 449-583 | WiFi sub-panel helpers |
| 585-616 | Slider helpers (volume, brightness) |
| 618-635 | Media helpers (play/pause, prev, next) |
| 637-651 | Theme + power helpers |
| 653-688 | Data refresh (brightness, theme, tailscale processes) |
| 690-756 | Panel open/close lifecycle + Connections |
| 760-777 | Bar button |
| 783-1692 | Popup (KeyboardPanel + main column + WiFi sub-panel + Bluetooth sub-panel) |
| 1694-1831 | Processes + timers |
| 1833-1967 | BluetoothDeviceRow component |
| 1974-2280 | Shared components (Tile, CircleToggle, IconTile, SliderTile, MiniButton) |

## Key Quickshell Patterns

### Calling Python from QML
```qml
Process {
  command: ["python3", scriptPath]
  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: {
      var parsed = JSON.parse(text)
      // use parsed
    }
  }
}
```
**Reference:** `/usr/share/omarchy/shell/plugins/panels/dropbox/Service.qml` line 64

### Reading/watching files
```qml
FileView {
  path: filePath
  watchChanges: true
  printErrors: false
  onLoaded: parse(text())
  onFileChanged: reload()
}
```

### Dynamic component loading
```qml
Loader {
  source: "path/to/Component.qml"
  onLoaded: item.someProperty = someValue
}
```

### Available system modules
- `qs.Commons`: Color, Style, Util, Border (singletons)
- `qs.Ui`: Panel, KeyboardPanel, PanelKeyCatcher, BarIconButton, CursorSurface, BorderSurface, PanelSlider, PanelActionButton (31 components total)

### Critical constraints
- `import` statements are compile-time/static — cannot conditionally import at runtime
- Inline `component` definitions are scoped to their parent Item
- `bar` property must be threaded through from root Panel
- `root` (Panel instance) is referenced by all inline components — dynamically loaded components need property injection
- Third-party plugins cannot use the `omarchy.*` namespace (PluginRegistry rejects it)

## Code Conventions

- `Style.space(px)` for all pixel values
- `Util.alpha(color, opacity)` for transparency
- `root.bar ? root.bar.fontFamily : Style.font.family` for font (repeated ~80 times)
- `Color.popups.text` for popup foreground
- `Color.accent` for accent color
- `Style.hoverFillFor(fg, accent)` / `Style.selectedFillFor(fg, accent)` for states
- Nerd Font glyphs for icons (e.g., "󰤨" for WiFi)
- `font.pixelSize: Style.font.caption` / `.body` / `.title` / `.heading` / `.icon`
