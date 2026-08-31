# Architectural Decisions

## D1: Layout manager in Python (not QML)

**Date:** 2026-08-30

**Decision:** The layout validator/resolver is a Python script called from QML via Process.

**Rationale:** User knows Python well, it's versatile, no binary security overhead. Proven pattern in Omarchy — Dropbox panel calls `python3 status.py` from QML (see `/usr/share/omarchy/shell/plugins/panels/dropbox/Service.qml` line 64).

**Trade-off:** Adds a process call on config load, but this is infrequent (panel open or config change) and fast (< 50ms).

**Pattern:**
```qml
Process {
  command: ["python3", scriptPath]
  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: { /* JSON.parse(text) */ }
  }
}
```

---

## D2: ModuleHost always provides the back button

**Date:** 2026-08-30

**Decision:** Expanded modules never render their own back button. ModuleHost always injects it.

**Rationale:** Guarantees visual consistency across all modules (built-in and third-party). Reduces boilerplate — module authors focus on content, not navigation chrome.

**Trade-off:** Less flexibility for custom header layouts. Mitigated by the header actions slot — modules can inject optional items (power toggle, settings gear) into the header row.

**Current implementation reference:** WiFi sub-panel back button is at Panel.qml lines 1165-1187 (hardcoded `← Wi-Fi` text + MouseArea). This becomes standard in ModuleHost.

---

## D3: Fixed row grid layout (not free-form)

**Date:** 2026-08-30

**Decision:** Modules declare width as "half" or "full". Connectivity zone is 2×2, focus zone pairs half-width tiles, controls stack as full-width rows.

**Rationale:** Matches current macOS-style layout. Simple, predictable, no complex grid math. Covers all current module types.

**Trade-off:** Can't have 3-column layouts or arbitrary positioning. Not needed for this panel — the macOS Control Center uses the same two-column pattern.

**Layout zones:**
- `connectivity` → 2×2 grid, all modules must be `half` width, max 4
- `focus` → paired in a row, all modules must be `half` width, max 2
- `controls` → stacked vertically, all modules must be `full` width

---

## D4: Error handling is per-module, not global

**Date:** 2026-08-30

**Decision:** A broken module shows an ErrorTile but doesn't break the rest of the panel.

**Rationale:** Third-party modules should never crash the control center. Users see exactly what failed and can fix or disable the broken module.

**Trade-off:** More complex rendering logic (layout engine must track per-module error state). Essential for extensibility.

**ErrorTile:** Red-tinted tile with module name + error message. Rendered in place of the module's normal tile.

---

## D5: Config is JSON (not TOML)

**Date:** 2026-08-30

**Decision:** User config uses JSON format.

**Rationale:** Matches Quickshell conventions (manifest.json). Easy to parse from both Python (`json.loads`) and JavaScript (`JSON.parse`). Universal format.

**Trade-off:** Less human-friendly than TOML for hand-editing. Acceptable — most users will use the future drag-and-drop editor anyway.

---

## D6: Auto-discovery of new modules

**Date:** 2026-08-30

**Decision:** Modules in `modules/` or `extensions/` that aren't in `config.json` are auto-added as enabled with default order.

**Rationale:** Drop-in experience for third-party extensions. No manual config editing required — just drop a folder and restart.

**Trade-off:** User can't hide a module without editing config. Edge case — config editor (future) will handle this.

---

## D7: Expanded views use separate QML files

**Date:** 2026-08-30

**Decision:** Modules with `expandable: true` have a separate `expandedEntry` QML file (e.g., `WifiPanel.qml` alongside `WifiToggle.qml`).

**Rationale:** Collapsed tile and expanded panel are fundamentally different layouts. Keeps files focused and manageable.

**Trade-off:** More files per module. Acceptable — each file is smaller and easier to maintain than one monolithic component.

---

## D8: Module state lives in each module file

**Date:** 2026-08-30

**Decision:** Each module owns its own state properties, helper functions, timers, and processes. Shared services accessed via `panel` reference.

**Rationale:** True encapsulation. Module is self-contained. No global state pollution. Easy to reason about.

**Trade-off:** Some duplication (e.g., multiple modules might poll the same service). Acceptable — services are reactive (QML bindings), so polling is minimal.

**Exception:** The refresh timer and keyboard cursor system stay in Panel.qml as shared infrastructure.

---

## D9: Keyboard navigation stays centralized

**Date:** 2026-08-30

**Decision:** The keyboard cursor system (targets list, moveCursor, activateCursor) remains in Panel.qml, not distributed across modules.

**Rationale:** Centralized cursor logic is easier to maintain and debug. Modules expose target IDs; the panel maps keys to targets.

**Trade-off:** Panel needs to know about all module target IDs. Mitigated by the render plan — modules declare their targets in module.json (future enhancement).
