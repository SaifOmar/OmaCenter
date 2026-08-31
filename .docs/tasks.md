# Implementation Tasks

## Phase 1: Project Setup
- [x] Create .gitignore
- [x] Create .docs/ with all documentation files
- [ ] Verify current Panel.qml works (baseline)

## Phase 2: Python Layout Manager
- [ ] Create layout_manager.py — schema validation
- [ ] Create layout_manager.py — constraint validation
- [ ] Create layout_manager.py — config merge + auto-discovery
- [ ] Create layout_manager.py — render plan output
- [ ] Test with valid configs
- [ ] Test with invalid configs (error handling)

## Phase 3: QML Integration
- [ ] Panel.qml — call layout_manager.py via Process + StdioCollector
- [ ] Panel.qml — parse render plan JSON
- [ ] Panel.qml — FileView for config.json watching
- [ ] Create shared/ErrorTile.qml
- [ ] Panel.qml — render ErrorTile for failed modules

## Phase 4: Extract Shared Components
- [ ] Create shared/ directory
- [ ] Extract shared/Tile.qml
- [ ] Extract shared/CircleToggle.qml
- [ ] Extract shared/IconTile.qml
- [ ] Extract shared/SliderTile.qml
- [ ] Extract shared/MiniButton.qml
- [ ] Verify identical visual output

## Phase 5: Module Interface
- [ ] Create base/ directory
- [ ] Create base/ModuleHost.qml (collapsed + expanded modes + back button)
- [ ] Define module.json schema (finalize fields)
- [ ] Create module.json for each built-in module (so.omacenter.* namespace)

## Phase 6: Split Monolith into Modules
- [ ] Create modules/ directory structure
- [ ] Extract modules/wifi/ (WifiToggle.qml + WifiPanel.qml)
- [ ] Extract modules/bluetooth/ (BluetoothToggle.qml + BluetoothPanel.qml)
- [ ] Extract modules/tailscale/ (TailscaleToggle.qml)
- [ ] Extract modules/mic/ (MicToggle.qml)
- [ ] Extract modules/dnd/ (DndTile.qml)
- [ ] Extract modules/nightlight/ (NightLightTile.qml)
- [ ] Extract modules/volume/ (VolumeSlider.qml)
- [ ] Extract modules/brightness/ (BrightnessSlider.qml)
- [ ] Extract modules/media/ (MediaTile.qml)
- [ ] Extract modules/theme/ (ThemeTile.qml)
- [ ] Extract modules/power/ (PowerRow.qml)
- [ ] Panel.qml becomes layout engine (~350 lines)
- [ ] Verify all controls work identically

## Phase 7: Config System
- [ ] Create default config.json
- [ ] Implement auto-discovery of new modules
- [ ] Test add/remove/reorder modules via config

## Phase 8: Expansion System
- [ ] ModuleHost expanded mode rendering
- [ ] Standard back button injection
- [ ] Header actions slot for modules
- [ ] WiFi expansion works (right-click → network list)
- [ ] Bluetooth expansion works (right-click → device list)
- [ ] Escape key collapses expanded view

## Phase 9: Third-Party Extensions
- [ ] Create extensions/ directory
- [ ] Create extensions/README.md (authoring guide)
- [ ] Create example extension (e.g., calculator)
- [ ] Test auto-discovery of extensions
- [ ] Test error handling for broken extensions

## Phase 10: Polish
- [ ] Module add/remove animations
- [ ] Config validation error messages in UI
- [ ] Fallback for missing/broken modules
- [ ] Keyboard navigation across expanded views
- [ ] Panel height adapts to expanded content
