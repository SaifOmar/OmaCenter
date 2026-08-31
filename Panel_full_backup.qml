import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "so.omacenter"
  ipcTarget: "so.omacenter"

  // ----------------------------------------------------------------------
  // Services
  // ----------------------------------------------------------------------

  readonly property var notificationService: bar?.shell?.firstPartyServiceFor("omarchy.notifications")
  readonly property var nightlightService: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var adapter: Bluetooth.defaultAdapter

  // MPRIS players, bound directly so media works regardless of whether the
  // omarchy.media plugin is enabled. Prefer a playing player with metadata,
  // then any player with metadata.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    var withMetadata = []
    for (var i = 0; i < root.mprisPlayers.length; i++) {
      var p = root.mprisPlayers[i]
      if (!p) continue
      if (p.trackTitle || p.trackArtist) {
        if (p.isPlaying) return p
        withMetadata.push(p)
      }
    }
    return withMetadata.length > 0 ? withMetadata[0] : null
  }
  readonly property bool hasMedia: root.player !== null
  readonly property string mediaTitle: player ? (player.trackTitle || "") : ""
  readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
  readonly property bool mediaPlaying: player ? player.isPlaying : false

  // ----------------------------------------------------------------------
  // State
  // ----------------------------------------------------------------------

  property int brightnessPercent: 0
  property bool brightnessAvailable: false
  property string themeName: ""
  property string tailscaleState: "Off"
  property string tailscaleHost: ""
  property int connectedBluetoothCount: 0

  property bool cursorActive: false
  property int cursorIndex: 0

  // WiFi sub-panel state
  property bool wifiExpanded: false
  property bool bluetoothExpanded: false
  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== DeviceType.Wifi) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  property var wifiNetworks: []
  property bool wifiScanning: false
  property bool wifiStationAvailable: false
  property var wifiScannerDevice: null

  // Bluetooth sub-panel state (mirrors omarchy.bluetooth)
  property var bluetoothPendingActions: ({})
  property bool bluetoothOwesDiscoveryStop: false
  readonly property var bluetoothDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var bluetoothPipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  property var bluetoothPendingAudioDevice: null
  property int bluetoothPendingAudioAttempts: 0
  readonly property var bluetoothDeviceGroups: Model.deviceLists(bluetoothDevices)
  readonly property var bluetoothConnectedDevices: bluetoothDeviceGroups.connected || []
  readonly property var bluetoothKnownDevices: bluetoothDeviceGroups.known || []
  readonly property var bluetoothDiscoveredDevices: bluetoothDeviceGroups.discovered || []
  readonly property var bluetoothConnectedRows: {
    var rows = []
    for (var i = 0; i < bluetoothConnectedDevices.length; i++) rows.push(Model.deviceRow(bluetoothConnectedDevices[i]))
    return rows
  }
  readonly property var bluetoothScrollRows: {
    var rows = []
    for (var k = 0; k < bluetoothKnownDevices.length; k++) rows.push({ dev: Model.deviceRow(bluetoothKnownDevices[k]), section: "known", indexInSection: k })
    if (bluetoothSectionVisible("discovered")) for (var d = 0; d < bluetoothDiscoveredDevices.length; d++) rows.push({ dev: Model.deviceRow(bluetoothDiscoveredDevices[d]), section: "discovered", indexInSection: d })
    return rows
  }
  readonly property int bluetoothScrollRowIndex: {
    if (bluetoothFocusSection !== "known" && bluetoothFocusSection !== "discovered") return -1
    for (var i = 0; i < bluetoothScrollRows.length; i++) if (bluetoothScrollRows[i].section === bluetoothFocusSection && bluetoothScrollRows[i].indexInSection === bluetoothSelectedIndex) return i
    return -1
  }
  property string bluetoothFocusSection: "connected"
  property int bluetoothSelectedIndex: 0
  property bool bluetoothActionFocused: false
  property bool bluetoothCursorActive: false
  property string bluetoothFocusedAddress: ""
  readonly property bool bluetoothHeaderHasCursor: bluetoothCursorActive && bluetoothFocusSection === "header"
  readonly property var bluetoothVisibleSections: Model.visibleSections(bluetoothDeviceGroups, adapter ? adapter.discovering : false)
  readonly property string bluetoothHeroStatus: {
    if (!adapter) return "No adapter"
    if (!adapter.enabled) return "Turned Off"
    return "Scanning…"
  }
  property string wifiPasswordSsid: ""
  property string wifiPasswordText: ""
  property string wifiActionSsid: ""
  property string wifiActionKind: ""
  property string wifiFailureSsid: ""
  property string wifiFailureReason: ""

  readonly property int panelWidth: root.setting("width", 400)

  // Panel content sits on the popup surface, so use its themed text token
  // (falls back to the foundational foreground inside Color).
  readonly property color fg: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color hoverFill: Style.hoverFillFor(fg, accent)
  readonly property color selectedFill: Style.selectedFillFor(fg, accent)
  readonly property bool busy: wifiActionKind !== ""

  // ----------------------------------------------------------------------
  // Read-only helpers
  // ----------------------------------------------------------------------

  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool micMuted: source && source.audio ? source.audio.muted : true

  readonly property bool wifiEnabled: Networking.wifiEnabled
  readonly property bool bluetoothEnabled: adapter ? adapter.enabled : false
  readonly property bool nightlightEnabled: nightlightService ? nightlightService.enabled : false
  readonly property bool dndEnabled: notificationService ? notificationService.doNotDisturb : false

  // Connected Wi-Fi network name, same source Omarchy's network panel uses.
  readonly property var wifiDevices: Networking.devices ? Networking.devices.values : []
  readonly property string wifiSsid: {
    for (var i = 0; i < root.wifiDevices.length; i++) {
      var device = root.wifiDevices[i]
      if (!device || device.type !== DeviceType.Wifi) continue
      var networks = device.networks ? device.networks.values : []
      for (var j = 0; j < networks.length; j++) {
        if (networks[j] && networks[j].connected) return networks[j].ssid || ""
      }
    }
    return ""
  }

  readonly property string wifiStatus: !root.wifiEnabled
    ? "Off"
    : (root.wifiSsid !== "" ? root.wifiSsid : "On")
  readonly property string bluetoothStatus: root.bluetoothEnabled
    ? (root.connectedBluetoothCount > 0 ? "On · " + root.connectedBluetoothCount : "On")
    : "Off"
  readonly property string tailscaleStatus: {
    if (root.tailscaleState === "On") return root.tailscaleHost !== "" ? root.tailscaleHost : "On"
    if (root.tailscaleState === "Login") return "Login"
    return "Off"
  }
  readonly property string micStatus: root.micMuted ? "Muted" : "Live"
  readonly property string nightlightStatus: root.nightlightEnabled ? "On" : "Off"
  readonly property string dndStatus: root.dndEnabled ? "On" : "Off"

  // Contrast: pick black or white text/icons depending on the fill's luminance,
  // so active (accent-filled) states stay readable on light and dark themes.
  function luminance(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  }

  function onAccent(c) {
    return root.luminance(c) > 0.45 ? "#000000" : "#ffffff"
  }

  // ----------------------------------------------------------------------
  // Keyboard cursor: a flat list of focusable targets following the visual
  // order of the grid. j/k walk the list, h/l adjust sliders or move along
  // horizontal runs (connectivity, media, power).
  // ----------------------------------------------------------------------

  readonly property var targets: {
    var t = ["wifi", "bluetooth", "tailscale", "mic", "dnd", "nightlight", "volume", "brightness"]
    if (root.hasMedia) t = t.concat(["mprev", "mplay", "mnext"])
    t = t.concat(["theme", "lock", "sleep"])
    return t
  }

  function currentTarget() {
    if (!root.cursorActive || root.cursorIndex < 0 || root.cursorIndex >= root.targets.length) return ""
    return root.targets[root.cursorIndex]
  }

  function setCursor(target) {
    var idx = root.targets.indexOf(target)
    if (idx < 0) return
    root.cursorActive = true
    root.cursorIndex = idx
  }

  function hasCursor(target) {
    return root.cursorActive && root.currentTarget() === target
  }

  function moveCursor(dx, dy) {
    root.cursorActive = true

    if (dy !== 0) {
      root.cursorIndex = Math.max(0, Math.min(root.targets.length - 1, root.cursorIndex + dy))
      return
    }
    if (dx === 0) return

    var target = root.currentTarget()
    if (target === "volume") {
      adjustVolume(dx > 0 ? 1 : -1)
    } else if (target === "brightness") {
      adjustBrightness(dx > 0 ? 1 : -1)
    } else if (target === "wifi" || target === "bluetooth" || target === "tailscale" || target === "mic") {
      var cIdx = root.targets.indexOf("wifi")
      root.cursorIndex = cIdx + Math.max(0, Math.min(3, root.cursorIndex - cIdx + dx))
    } else if (target === "mprev" || target === "mplay" || target === "mnext") {
      var mIdx = root.targets.indexOf("mprev")
      if (mIdx >= 0) {
        var mCount = 3
        var mCursor = Math.max(0, Math.min(mCount - 1, root.cursorIndex - mIdx + dx))
        root.cursorIndex = mIdx + mCursor
      }
    } else if (target === "lock" || target === "sleep") {
      var pIdx = root.targets.indexOf("lock")
      if (pIdx >= 0) {
        var pCursor = Math.max(0, Math.min(1, root.cursorIndex - pIdx + dx))
        root.cursorIndex = pIdx + pCursor
      }
    }
  }

  function activateCursor() {
    var target = root.currentTarget()
    if (target === "wifi") toggleWifi()
    else if (target === "bluetooth") toggleBluetooth()
    else if (target === "tailscale") toggleTailscale()
    else if (target === "mic") toggleMic()
    else if (target === "dnd") toggleDnd()
    else if (target === "nightlight") toggleNightlight()
    else if (target === "mprev") mediaPrevious()
    else if (target === "mplay") togglePlayPause()
    else if (target === "mnext") mediaNext()
    else if (target === "theme") openThemeSwitcher()
    else if (target === "lock") doLock()
    else if (target === "sleep") doSleep()
  }

  // ----------------------------------------------------------------------
  // Quick toggles
  // ----------------------------------------------------------------------

  function toggleWifi() {
    if (Networking.backend !== NetworkBackendType.NetworkManager) return
    Networking.wifiEnabled = !Networking.wifiEnabled
  }

  function toggleBluetooth() {
    if (!root.adapter) return
    Quickshell.execDetached(["omarchy-bluetooth-power", root.adapter.enabled ? "off" : "on"])
  }

  function toggleTailscale() {
    if (root.tailscaleState === "On") Quickshell.execDetached(["tailscale", "down"])
    else Quickshell.execDetached(["tailscale", "up"])
  }

  function toggleNightlight() {
    if (root.nightlightService) root.nightlightService.setNightlight(!root.nightlightEnabled)
  }

  function toggleDnd() {
    if (root.notificationService) root.notificationService.setDoNotDisturb(!root.dndEnabled)
  }

  function toggleMic() {
    if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
  }

  // ----------------------------------------------------------------------
  // Sub-panels: right-click hands off to the matching Omarchy bar widget's
  // panel. Falls back silently when the target plugin is not enabled.
  // ----------------------------------------------------------------------

  function summonPanel(pluginId) {
    if (!bar || !bar.shell || typeof bar.shell.summon !== "function") return
    bar.shell.summon(pluginId)
  }

  // ----------------------------------------------------------------------
  // Bluetooth sub-panel helpers (copied from omarchy.bluetooth, adapted to control-center)
  // ----------------------------------------------------------------------

  function bluetoothDeviceLabel(device) { return Model.deviceLabel(device) }
  function bluetoothSectionCount(section) {
    if (section === "connected") return bluetoothConnectedDevices.length
    if (section === "known") return bluetoothKnownDevices.length
    if (section === "discovered") return bluetoothDiscoveredDevices.length
    return 0
  }
  function bluetoothSectionVisible(section) {
    if (section === "connected") return bluetoothConnectedDevices.length > 0
    if (section === "known") return bluetoothKnownDevices.length > 0
    if (section === "discovered") return adapter && adapter.discovering && bluetoothDiscoveredDevices.length > 0
    return false
  }
  function bluetoothDevicesForSection(section) { return Model.sectionDevices(bluetoothDeviceGroups, section) }
  function bluetoothScrollSectionTitle(index) {
    var rows = bluetoothScrollRows
    if (index < 0 || index >= rows.length) return ""
    if (index > 0 && rows[index-1].section === rows[index].section) return ""
    return rows[index].section === "known" ? "PAIRED" : "AVAILABLE"
  }
  function bluetoothDeviceFor(row) {
    if (!row || !row.dev) return null
    var addr = row.dev.address || ""
    var devs = bluetoothDevices || []
    for (var i = 0; i < devs.length; i++) if ((devs[i].address || "") === addr) return devs[i]
    return null
  }
  function bluetoothPendingAction(address) { return Model.pendingAction(bluetoothPendingActions, address) }
  function bluetoothSetPendingAction(address, action) {
    if (!address) return
    bluetoothPendingActions = Model.withPendingAction(bluetoothPendingActions, address, action)
    if (action) bluetoothPendingTimeout.restart()
  }
  function bluetoothDeviceCommand(action, address) { return ["omarchy-bluetooth-device", action, address] }
  function bluetoothRunDeviceAction(device, action, pending) {
    if (!device || !device.address) return
    bluetoothSetPendingAction(device.address, pending)
    Quickshell.execDetached(bluetoothDeviceCommand(action, device.address))
  }
  function bluetoothConnectDevice(device) {
    if (!device || device.connected) return
    if (device.paired || device.bonded || device.trusted) bluetoothRunDeviceAction(device, "connect", "connecting")
    else bluetoothRunDeviceAction(device, "pair", "connecting")
  }
  function bluetoothDisconnectDevice(device) {
    if (!device || !device.address || !device.connected) return
    bluetoothSetPendingAction(device.address, "disconnecting")
    if (device.disconnect) device.disconnect()
    Quickshell.execDetached(bluetoothDeviceCommand("disconnect", device.address))
  }
  function bluetoothForgetDevice(device) {
    if (!device || !device.address) return
    bluetoothRunDeviceAction(device, "forget", "forgetting")
  }
  function bluetoothSyncPendingActions() {
    var next = Model.cloneMap(bluetoothPendingActions)
    var changed = false
    for (var address in next) {
      var action = next[address]
      var found = null
      for (var i = 0; i < bluetoothDevices.length; i++) { var d = bluetoothDevices[i]; if (d && d.address === address) { found = d; break } }
      var finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting || (action === "disconnecting" && found && !found.connected) || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        if (finishedConnecting) bluetoothScheduleAudioSwitch(found)
        delete next[address]; changed = true
      }
    }
    if (changed) bluetoothPendingActions = next
  }
  function bluetoothAudioSinks() {
    var sinks = []
    for (var i = 0; i < bluetoothPipewireNodes.length; i++) { var node = bluetoothPipewireNodes[i]; if (node && node.isSink && !node.isStream) sinks.push(node) }
    return sinks
  }
  function bluetoothAudioSink(device) {
    var sinks = bluetoothAudioSinks()
    for (var i = 0; i < sinks.length; i++) if (Model.bluetoothSinkMatchesDevice(sinks[i], device)) return sinks[i]
    return null
  }
  function bluetoothSetDefaultSink(sink) {
    if (!sink) return
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id !== undefined && sink.name) Quickshell.execDetached(["omarchy-audio-output-set-default", String(sink.id), String(sink.name)])
  }
  function bluetoothScheduleAudioSwitch(device) {
    bluetoothPendingAudioDevice = { address: device && device.address ? device.address : "", name: device && device.name ? device.name : "", deviceName: device && device.deviceName ? device.deviceName : "" }
    bluetoothPendingAudioAttempts = 0
    bluetoothAudioSwitchTimer.restart()
  }
  function bluetoothSwitchPendingAudio() {
    if (!bluetoothPendingAudioDevice) return
    var sink = bluetoothAudioSink(bluetoothPendingAudioDevice)
    if (sink) { bluetoothSetDefaultSink(sink); bluetoothPendingAudioDevice = null; bluetoothAudioSwitchTimer.stop(); return }
    bluetoothPendingAudioAttempts += 1
    if (bluetoothPendingAudioAttempts >= 8) { bluetoothPendingAudioDevice = null; return }
    bluetoothAudioSwitchTimer.restart()
  }
  function bluetoothDeviceAt(section, index) {
    var list = bluetoothDevicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }
  function bluetoothOpenSibling() {
    if (!bar || typeof bar.moduleWidgets !== "function") return null
    var items = bar.moduleWidgets(moduleName)
    for (var i = 0; i < items.length; i++) if (items[i] && items[i] !== root && items[i].bluetoothExpanded === true) return items[i]
    return null
  }
  function bluetoothUpdateFocusedAddress() {
    var d = bluetoothDeviceAt(bluetoothFocusSection, bluetoothSelectedIndex)
    bluetoothFocusedAddress = d ? (d.address || "") : ""
  }
  function bluetoothReselectFocusedDevice() {
    if (bluetoothFocusedAddress === "") { bluetoothClampCursor(); return }
    var sections = ["connected","known","discovered"]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      if (!bluetoothSectionVisible(section)) continue
      var list = bluetoothDevicesForSection(section)
      for (var i = 0; i < list.length; i++) if (list[i] && list[i].address === bluetoothFocusedAddress) { bluetoothFocusSection = section; bluetoothSelectedIndex = i; bluetoothClampCursor(); return }
    }
    bluetoothClampCursor()
  }
  function bluetoothClampCursor() {
    var sections = bluetoothVisibleSections
    if (bluetoothFocusSection === "header") return
    if (!sections || !sections.length) { bluetoothSelectedIndex = 0; return }
    if (sections.indexOf(bluetoothFocusSection) < 0) { bluetoothFocusSection = sections[0]; bluetoothSelectedIndex = 0; return }
    var count = bluetoothSectionCount(bluetoothFocusSection)
    if (count === 0) { var sIdx = sections.indexOf(bluetoothFocusSection); bluetoothFocusSection = sIdx > 0 ? sections[sIdx-1] : sections[0]; bluetoothSelectedIndex = Math.max(0, bluetoothSectionCount(bluetoothFocusSection)-1); return }
    if (bluetoothSelectedIndex > count-1) bluetoothSelectedIndex = count-1
    if (bluetoothSelectedIndex < 0) bluetoothSelectedIndex = 0
  }

  // ----------------------------------------------------------------------
  // WiFi sub-panel
  // ----------------------------------------------------------------------

  function setWifiScannerEnabled(enabled) {
    var nextDevice = root.wifiExpanded ? root.wifiDevice : null
    if (root.wifiScannerDevice && root.wifiScannerDevice !== nextDevice)
      root.wifiScannerDevice.scannerEnabled = false
    root.wifiScannerDevice = nextDevice
    if (root.wifiScannerDevice)
      root.wifiScannerDevice.scannerEnabled = enabled
  }

  function syncWifiNetworks() {
    var nets = []
    var networks = root.wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      root.checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    root.wifiNetworks = Model.sortWifiRows(nets)
    root.wifiStationAvailable = !!root.wifiDevice
    root.wifiScanning = false
  }

  function wifiIconFor(strength) {
    return Model.wifiIconFor(strength)
  }

  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  function networkForSsid(ssid) {
    var networks = root.wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function openPasswordPrompt(ssid) {
    root.wifiPasswordText = ""
    root.wifiPasswordSsid = ssid
  }

  function cancelPasswordPrompt() {
    root.wifiPasswordSsid = ""
    root.wifiPasswordText = ""
  }

  function connectDirectly(ssid) {
    var network = root.networkForSsid(ssid)
    if (!network || root.wifiActionKind !== "") return
    root.runNetworkAction("connect", network, function(n) { n.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    var network = root.networkForSsid(ssid)
    if (!network || root.wifiActionKind !== "" || passphrase.length === 0) return
    root.runNetworkAction("connect", network, function(n) { n.connectWithPsk(passphrase) })
  }

  function disconnectRow(ssid) {
    var network = root.networkForSsid(ssid)
    if (!network || root.wifiActionKind !== "") return
    root.runNetworkAction("disconnect", network, function(n) { n.disconnect() })
  }

  function forgetNetwork(net) {
    if (!net || !net.known || net.connected || root.wifiActionKind !== "") return
    var network = root.networkForSsid(net.ssid)
    if (!network) return
    root.runNetworkAction("forget", network, function(n) { n.forget() })
  }

  function runNetworkAction(kind, network, callback) {
    if (root.wifiActionKind !== "" || !network) return
    var ssid = network.name || ""
    root.wifiActionSsid = ssid
    root.wifiActionKind = kind
    root.wifiFailureSsid = ""
    root.wifiFailureReason = ""
    callback(network)
    wifiActionTimeout.restart()
  }

  function checkActionCompletion(network) {
    if (root.wifiActionKind === "" || !network) return
    if (root.wifiActionSsid !== (network.name || "")) return
    var done = false
    if (root.wifiActionKind === "connect") done = network.connected
    else if (root.wifiActionKind === "disconnect") done = !network.connected && !network.stateChanging
    else if (root.wifiActionKind === "forget") done = !network.known
    if (done) root.clearNetworkAction()
  }

  function clearNetworkAction() {
    wifiActionTimeout.stop()
    root.wifiFailureSsid = ""
    root.wifiFailureReason = ""
    root.wifiActionSsid = ""
    root.wifiActionKind = ""
    root.cancelPasswordPrompt()
    root.startWifiScan()
  }

  function failNetworkAction(network, reason) {
    if (!network || root.wifiActionKind === "" || root.wifiActionSsid !== (network.name || "")) return
    wifiActionTimeout.stop()
    root.wifiFailureSsid = root.wifiActionSsid
    root.wifiFailureReason = Model.networkFailureReason(reason, root.requiresCredentials(network.security), ConnectionFailReason)
    root.wifiActionSsid = ""
    root.wifiActionKind = ""
    root.startWifiScan()
  }

  function shouldRepromptPassphrase(reason, needsCredentials) {
    return Model.shouldRepromptPassphrase(reason, needsCredentials, ConnectionFailReason)
  }

  function startWifiScan() {
    if (!root.wifiDevice) {
      root.wifiStationAvailable = false
      root.wifiNetworks = []
      root.wifiScanning = false
      return
    }
    root.wifiScanning = true
    root.setWifiScannerEnabled(false)
    scanRestart.restart()
  }

  // ----------------------------------------------------------------------
  // Sliders
  // ----------------------------------------------------------------------

  function setOutputVolume(v) {
    if (!root.sink || !root.sink.audio) return
    root.sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
  }

  function adjustVolume(delta) {
    if (!root.sink || !root.sink.audio) return
    var next = Math.max(0, Math.min(1, root.outputVolume + delta * 0.05))
    root.sink.audio.volume = next
  }

  function setBrightness(percent) {
    root.brightnessPercent = Math.max(0, Math.min(100, Math.round(percent)))
    brightnessDebounce.restart()
  }

  function adjustBrightness(delta) {
    root.setBrightness(root.brightnessPercent + delta * 5)
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({ icon: "brightness", value: percent }))
  }

  // ----------------------------------------------------------------------
  // Media
  // ----------------------------------------------------------------------

  function togglePlayPause() {
    if (!root.player) return
    if (root.player.canTogglePlaying) root.player.togglePlaying()
    else if (root.mediaPlaying && root.player.canPause) root.player.pause()
    else if (!root.mediaPlaying && root.player.canPlay) root.player.play()
  }

  function mediaPrevious() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  function mediaNext() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  // ----------------------------------------------------------------------
  // Theme + power
  // ----------------------------------------------------------------------

  function openThemeSwitcher() {
    Quickshell.execDetached(["omarchy", "theme", "switcher"])
  }

  function doLock() {
    Quickshell.execDetached(["omarchy", "system", "lock"])
  }

  function doSleep() {
    Quickshell.execDetached(["systemctl", "suspend"])
  }

  // ----------------------------------------------------------------------
  // Data refresh
  // ----------------------------------------------------------------------

  function refresh() {
    if (!brightnessProc.running) brightnessProc.running = true
    if (!themeProc.running) themeProc.running = true
    if (!tailscaleProc.running) tailscaleProc.running = true
    root.connectedBluetoothCount = Bluetooth.devices ? Bluetooth.devices.values.filter(function(d) { return d.connected }).length : 0
  }

  function updateBrightness(raw) {
    var n = parseInt(String(raw || "").trim(), 10)
    if (isFinite(n)) {
      root.brightnessPercent = Math.max(0, Math.min(100, n))
      root.brightnessAvailable = true
    }
  }

  function updateTheme(raw) {
    var name = String(raw || "").trim()
    if (name !== "") root.themeName = name
  }

  function updateTailscale(raw) {
    try {
      var d = JSON.parse(raw)
      var state = String(d.BackendState || "")
      root.tailscaleState = state === "Running" ? "On" : (state === "Starting" ? "Starting" : (state === "NeedsLogin" ? "Login" : "Off"))
      var self = d.Self
      root.tailscaleHost = self && self.DNSName ? String(self.DNSName).split(".")[0] : ""
    } catch (e) {
      root.tailscaleState = "Off"
      root.tailscaleHost = ""
    }
  }

  onOpenedChanged: {
    if (opened) {
      root.cursorActive = false
      root.cursorIndex = 0
      root.wifiExpanded = false
      root.bluetoothExpanded = false
      root.cancelPasswordPrompt()
      if (root.adapter !== null && root.adapter.discovering) root.bluetoothOwesDiscoveryStop = true
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.wifiExpanded = false
      root.bluetoothExpanded = false
      root.cancelPasswordPrompt()
    }
  }

  Connections {
    target: root
    function onWifiExpandedChanged() {
      if (root.wifiExpanded) {
        root.bluetoothExpanded = false
        root.syncWifiNetworks()
        root.startWifiScan()
      } else {
        scanRestart.stop()
        scanDone.stop()
        // Defer scanner teardown to next event loop so contentHeight switch
        // (wifiColumn -> column) paints first frame without D-Bus round-trip.
        Qt.callLater(function() { root.setWifiScannerEnabled(false) })
      }
    }
    function onBluetoothExpandedChanged() {
      if (root.bluetoothExpanded) {
        root.wifiExpanded = false
        if (root.adapter !== null && root.adapter.discovering) root.bluetoothOwesDiscoveryStop = true
        // start discovery right away if BT is on (Timer triggeredOnStart does it, but force if needed)
        if (root.adapter && root.adapter.enabled && !root.adapter.discovering) {
          root.bluetoothOwesDiscoveryStop = true
          root.adapter.discovering = true
        }
        // init cursor like upstream
        if (root.bluetoothConnectedDevices.length > 0) { root.bluetoothFocusSection = "connected"; root.bluetoothSelectedIndex = 0 }
        else if (root.bluetoothKnownDevices.length > 0) { root.bluetoothFocusSection = "known"; root.bluetoothSelectedIndex = 0 }
        else if (root.bluetoothDiscoveredDevices.length > 0) { root.bluetoothFocusSection = "discovered"; root.bluetoothSelectedIndex = 0 }
        else { root.bluetoothFocusSection = "header" }
        root.bluetoothActionFocused = false
        root.bluetoothCursorActive = false
      }
    }
    function onWifiDeviceChanged() {
      if (root.wifiExpanded) root.setWifiScannerEnabled(true)
      root.syncWifiNetworks()
      if (root.wifiExpanded) root.startWifiScan()
    }
    function onWifiNetworkObjectsChanged() {
      if (root.wifiExpanded) root.syncWifiNetworks()
    }
    function onBluetoothDevicesChanged() { root.bluetoothReselectFocusedDevice(); root.bluetoothSyncPendingActions() }
    function onBluetoothDeviceGroupsChanged() { root.bluetoothReselectFocusedDevice(); root.bluetoothSyncPendingActions() }
    function onBluetoothVisibleSectionsChanged() { root.bluetoothClampCursor() }
    function onBluetoothSelectedIndexChanged() { root.bluetoothUpdateFocusedAddress() }
    function onBluetoothFocusSectionChanged() { root.bluetoothUpdateFocusedAddress() }
    function onBluetoothConnectedDevicesChanged() { root.bluetoothReselectFocusedDevice(); root.bluetoothSyncPendingActions() }
    function onBluetoothKnownDevicesChanged() { root.bluetoothReselectFocusedDevice(); root.bluetoothSyncPendingActions() }
    function onBluetoothDiscoveredDevicesChanged() { root.bluetoothReselectFocusedDevice(); root.bluetoothSyncPendingActions() }
  }



  // ----------------------------------------------------------------------
  // Bar button
  // ----------------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒳"
    tooltipText: "Control Center"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.close()
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------------
  // Popup
  // ----------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(root.wifiExpanded ? wifiColumn.implicitHeight : root.bluetoothExpanded ? bluetoothColumn.implicitHeight : column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.wifiExpanded) { root.wifiExpanded = false; root.cancelPasswordPrompt() }
        else if (root.bluetoothExpanded) { root.bluetoothExpanded = false }
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        visible: !root.wifiExpanded && !root.bluetoothExpanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Header ----------
        Item {
          width: parent.width
          height: escHint.implicitHeight

          Text {
            id: escHint
            anchors.right: parent.right
            text: "esc"
            color: Util.alpha(root.fg, 0.62)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
        }

        // ---------- Top grid: connectivity module + focus/night light ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          readonly property real halfWidth: (width - spacing) / 2
          readonly property int moduleHeight: Style.space(138)

          // Connectivity: 2x2 module of circular toggles, macOS style.
          Tile {
            width: parent.halfWidth
            height: parent.moduleHeight
            hoverable: false

            Grid {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              columns: 2
              rows: 2
              spacing: Style.space(4)

              readonly property real cellWidth: (width - spacing) / 2
              readonly property real cellHeight: (height - spacing) / 2

              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: root.wifiEnabled ? "󰤨" : "󰤭"
                label: root.wifiStatus
                active: root.wifiEnabled
                hasCursor: root.hasCursor("wifi")
                onClicked: root.toggleWifi()
                onRightClicked: root.wifiExpanded = true
                onHoverSignal: function(h) { if (h) root.setCursor("wifi") }
              }
              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: root.bluetoothEnabled ? "󰂯" : "󰂲"
                label: root.bluetoothStatus
                active: root.bluetoothEnabled
                hasCursor: root.hasCursor("bluetooth")
                onClicked: root.bluetoothExpanded = true
                onRightClicked: root.toggleBluetooth()
                onHoverSignal: function(h) { if (h) root.setCursor("bluetooth") }
              }
              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: "󰖂"
                label: root.tailscaleStatus
                active: root.tailscaleState === "On"
                hasCursor: root.hasCursor("tailscale")
                onClicked: root.toggleTailscale()
                onRightClicked: root.summonPanel("omarchy.tailscale")
                onHoverSignal: function(h) { if (h) root.setCursor("tailscale") }
              }
              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: root.micMuted ? "󰍭" : "󰍬"
                label: root.micStatus
                active: !root.micMuted
                hasCursor: root.hasCursor("mic")
                onClicked: root.toggleMic()
                onRightClicked: root.summonPanel("omarchy.microphone")
                onHoverSignal: function(h) { if (h) root.setCursor("mic") }
              }
            }
          }

          Column {
            width: parent.halfWidth
            height: parent.moduleHeight
            spacing: Style.space(8)

            IconTile {
              width: parent.width
              height: (parent.height - parent.spacing) / 2
              glyph: "󰂚"
              title: "Do Not Disturb"
              subtitle: root.dndStatus
              active: root.dndEnabled
              hasCursor: root.hasCursor("dnd")
              onClicked: root.toggleDnd()
              onRightClicked: root.summonPanel("shavanced.notification-center")
              onHoverSignal: function(h) { if (h) root.setCursor("dnd") }
            }

            IconTile {
              width: parent.width
              height: (parent.height - parent.spacing) / 2
              glyph: "󰖔"
              title: "Night Light"
              subtitle: root.nightlightStatus
              active: root.nightlightEnabled
              hasCursor: root.hasCursor("nightlight")
              onClicked: root.toggleNightlight()
              onHoverSignal: function(h) { if (h) root.setCursor("nightlight") }
            }
          }
        }

        // ---------- Sliders ----------
        SliderTile {
          width: parent.width
          height: Style.space(58)
          glyph: root.outputMuted ? "󰝟" : "󰕾"
          label: "Sound"
          valueText: root.outputMuted ? "Muted" : Math.round(root.outputVolume * 100) + "%"
          value: root.outputVolume
          dimmed: root.outputMuted
          hasCursor: root.hasCursor("volume")
          onMoved: root.setOutputVolume(v)
          onReleased: root.setOutputVolume(v)
          onIconClicked: root.toggleMute()
          onRightClicked: root.summonPanel("omarchy.audio")
          onHoverSignal: function(h) { if (h) root.setCursor("volume") }
        }

        SliderTile {
          width: parent.width
          height: Style.space(58)
          glyph: "󰃟"
          label: "Display"
          valueText: root.brightnessPercent + "%"
          value: root.brightnessAvailable ? root.brightnessPercent / 100 : 0
          hasCursor: root.hasCursor("brightness")
          onMoved: root.setBrightness(v * 100)
          onReleased: function(v) {
            root.setBrightness(v * 100)
            root.showBrightnessOsd(Math.round(v * 100))
          }
          onRightClicked: root.summonPanel("omarchy.monitor")
          onHoverSignal: function(h) { if (h) root.setCursor("brightness") }
        }

        // ---------- Now playing ----------
        Tile {
          width: parent.width
          height: Style.space(66)
          onRightClicked: root.summonPanel("famas.media-plus")

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)

            Item {
              id: mediaArt
              width: Style.space(46)
              height: parent.height

              // Album art, rounded via a MultiEffect mask (the same pattern
              // famas.media-plus uses). Falls back to a note tile when there
              // is no artwork or it fails to load.
              Item {
                id: artSource
                anchors.centerIn: parent
                width: Style.space(42)
                height: width
                visible: false
                layer.enabled: true
                layer.smooth: true

                Image {
                  id: artImage
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                }

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(10)
                  color: Util.alpha(root.fg, 0.12)
                  visible: artImage.status !== Image.Ready

                  Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    color: root.fg
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.icon
                  }
                }
              }

              Item {
                id: artMask
                anchors.fill: artSource
                visible: false
                layer.enabled: true
                layer.smooth: true

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(10)
                  color: "white"
                }
              }

              MultiEffect {
                anchors.fill: artSource
                source: artSource
                maskEnabled: true
                maskSource: artMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }
            }

            Column {
              width: parent.width - mediaArt.width - mediaButtons.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.hasMedia ? root.mediaTitle : "Nothing Playing"
                color: root.fg
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.hasMedia ? root.mediaArtist : "—"
                color: Util.alpha(root.fg, 0.62)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Row {
              id: mediaButtons
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              MiniButton {
                visible: root.player ? root.player.canGoPrevious : false
                glyph: "󰒮"
                hasCursor: root.hasCursor("mprev")
                onClicked: root.mediaPrevious()
                onHoverSignal: function(h) { if (h) root.setCursor("mprev") }
              }
              MiniButton {
                glyph: root.mediaPlaying ? "󰏤" : "󰐊"
                hasCursor: root.hasCursor("mplay")
                onClicked: root.togglePlayPause()
                onHoverSignal: function(h) { if (h) root.setCursor("mplay") }
              }
              MiniButton {
                visible: root.player ? root.player.canGoNext : false
                glyph: "󰒭"
                hasCursor: root.hasCursor("mnext")
                onClicked: root.mediaNext()
                onHoverSignal: function(h) { if (h) root.setCursor("mnext") }
              }
            }
          }
        }

        // ---------- Theme ----------
        IconTile {
          width: parent.width
          height: Style.space(56)
          glyph: "󰏘"
          title: root.themeName !== "" ? "Theme — " + root.themeName : "Theme"
          subtitle: "Switch appearance"
          hasCursor: root.hasCursor("theme")
          onClicked: root.openThemeSwitcher()
          onHoverSignal: function(h) { if (h) root.setCursor("theme") }
        }

        // ---------- Power ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          readonly property real cellWidth: (width - spacing) / 2

          Repeater {
            model: [
              { target: "lock", label: "Lock" },
              { target: "sleep", label: "Sleep" }
            ]

            delegate: Tile {
              required property var modelData
              width: parent.cellWidth
              height: Style.space(42)

              Text {
                anchors.centerIn: parent
                text: parent.modelData.label.toUpperCase()
                color: parent.hot || parent.hasCursor ? root.fg : Util.alpha(root.fg, 0.62)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 0.5
              }

              hasCursor: root.hasCursor(modelData.target)
              onClicked: {
                if (modelData.target === "lock") root.doLock()
                else root.doSleep()
              }
              onRightClicked: root.summonPanel("omarchy.power")
              onHoverSignal: function(h) { if (h) root.setCursor(modelData.target) }
            }
          }
        }
      }

      // WiFi sub-panel
      Column {
        id: wifiColumn
        visible: root.wifiExpanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header with back button and power toggle — always on top
        Row {
          width: parent.width
          spacing: Style.space(8)
          z: 5

          Text {
            id: wifiBackBtn
            text: "← Wi-Fi"
            color: root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            z: 10

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              enabled: true
              propagateComposedEvents: false
              z: 10
              onClicked: {
                // Immediate, never blocked by scan
                root.wifiExpanded = false
              }
            }
          }

          Item { width: parent.width - wifiBackBtn.implicitWidth - wifiPowerToggle.implicitWidth - parent.spacing; height: 1 }

          Rectangle {
            id: wifiPowerToggle
            width: Style.space(34)
            implicitWidth: width
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.wifiEnabled
              ? root.accent
              : Util.alpha(root.fg, 0.13)

            Text {
              anchors.centerIn: parent
              text: root.wifiEnabled ? "󰤨" : "󰤭"
              color: root.wifiEnabled ? root.onAccent(root.accent) : root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleWifi()
            }
          }
        }

        // Scanning indicator — subtle, doesn't block header
        Text {
          visible: root.wifiScanning
          text: "SCANNING WI-FI…"
          color: Util.alpha(root.fg, 0.52)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        // Network list
        ListView {
          id: wifiList
          visible: root.wifiStationAvailable
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.wifiNetworks
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: Model.wifiSectionTitle(wifiList.model, index)
            width: ListView.view.width
            height: delegateCol.implicitHeight

            Column {
              id: delegateCol
              width: parent.width
              spacing: Style.space(4)

              Text {
                visible: sectionTitle !== ""
                text: sectionTitle
                color: Util.alpha(root.fg, 0.52)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                height: visible ? implicitHeight : 0
              }

              // Network row — CursorSurface-based to match native Omarchy styling
              CursorSurface {
                id: row
                width: parent.width

                readonly property var net: modelData
                readonly property bool isConnected: net && net.connected
                readonly property bool isKnown: !!(net && net.known)
                readonly property bool requiresCredentials: net ? root.requiresCredentials(net.security) : false
                readonly property bool canForget: net && net.known && !net.connected
                readonly property bool isBusy: root.wifiActionKind !== "" && root.wifiActionSsid === (net ? net.ssid : "")
                readonly property bool isFailed: root.wifiFailureSsid === (net ? net.ssid : "")
                readonly property bool isPasswordOpen: root.wifiPasswordSsid === (net ? net.ssid : "")

                hasCursor: false
                current: isConnected
                foreground: root.fg
                fill: root.hoverFill
                currentFill: root.selectedFill

                implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + Style.spacing.md : 0)

                MouseArea {
                  id: rowMouse
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: rowBody.implicitHeight
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  enabled: !root.busy

                  onContainsMouseChanged: row.hasCursor = containsMouse
                  onExited: row.hasCursor = false

                  onClicked: {
                    if (!row.net) return
                    row.hasCursor = containsMouse
                    if (row.isConnected) { root.disconnectRow(row.net.ssid); return }
                    if (row.requiresCredentials && !row.isKnown) { root.openPasswordPrompt(row.net.ssid); return }
                    root.connectDirectly(row.net.ssid)
                  }
                }

                Connections {
                  target: row.net ? root.networkForSsid(row.net.ssid) : null
                  function onConnectionFailed(reason) {
                    var ours = root.wifiActionKind === "connect" && root.wifiActionSsid === (row.net ? row.net.ssid : "")
                    root.failNetworkAction(root.networkForSsid(row.net ? row.net.ssid : ""), reason)
                    if (ours && root.shouldRepromptPassphrase(reason, row.requiresCredentials)) root.openPasswordPrompt(row.net.ssid)
                  }
                  function onConnectedChanged() {
                    if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
                  }
                  function onKnownChanged() {
                    if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
                  }
                  function onStateChangingChanged() {
                    if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
                  }
                }

                readonly property string statusText: {
                  if (!net) return ""
                  if (isPasswordOpen) return ""
                  if (isBusy && root.wifiActionKind === "connect") return "Connecting…"
                  if (isBusy && root.wifiActionKind === "disconnect") return "Disconnecting…"
                  if (isFailed) return root.wifiFailureReason || "Failed"
                  if (isConnected) return "Connected"
                  return ""
                }

                readonly property color statusColor: {
                  if (isFailed) return Color.urgent
                  if (isBusy || isConnected) return root.fg
                  return Util.alpha(root.fg, 0.62)
                }

                Item {
                  id: rowBody
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightAction.implicitHeight) + Style.spacing.rowPaddingX

                  Text {
                    id: networkIcon
                    text: row.net ? root.wifiIconFor(row.net.signal) : ""
                    color: row.statusColor
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Item {
                    id: rightAction
                    visible: row.requiresCredentials || row.canForget
                    width: Style.space(22)
                    implicitHeight: lockIndicator.implicitHeight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: lockIndicator
                      visible: row.requiresCredentials
                      width: parent.width
                      anchors.verticalCenter: parent.verticalCenter
                      horizontalAlignment: Text.AlignHCenter
                      text: "󰌾"
                      color: Util.alpha(root.fg, 0.5)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.subtitle
                    }

                    MouseArea {
                      id: rightMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.LeftButton
                      enabled: row.canForget && !root.busy
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onContainsMouseChanged: row.hasCursor = containsMouse
                      onExited: row.hasCursor = false
                      onClicked: if (row.net) root.forgetNetwork(row.net)
                    }

                    Text {
                      visible: row.canForget && rightMouse.containsMouse
                      anchors.centerIn: parent
                      text: "󰅙"
                      color: Color.urgent
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.subtitle
                    }
                  }

                  Column {
                    id: networkInfo
                    spacing: Style.space(1)
                    anchors.left: networkIcon.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: rightAction.visible ? rightAction.left : parent.right
                    anchors.rightMargin: rightAction.visible ? Style.space(8) : 0
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      text: row.net ? (row.net.ssid || "Hidden") : ""
                      color: root.fg
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      text: row.statusText
                      visible: row.statusText !== ""
                      height: visible ? implicitHeight : 0
                      color: row.statusColor
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }
                }

                // Inline password prompt
                Item {
                  id: passwordPanel
                  visible: row.isPasswordOpen
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: rowMouse.bottom
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.topMargin: Style.space(4)
                  implicitHeight: pwField.implicitHeight + Style.spacing.rowGap
                  height: implicitHeight

                  TextField {
                    id: pwField
                    visible: !row.isBusy && !row.isFailed
                    anchors.left: parent.left
                    anchors.right: connectPwBtn.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.spacing.rowGap / 2
                    anchors.rightMargin: Style.space(6)
                    password: true
                    placeholderText: "Passphrase"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    foreground: root.fg
                    horizontalPadding: Style.spacing.controlGap
                    verticalPadding: Style.spacing.controlPaddingY
                    enabled: !row.isBusy
                    text: row.isPasswordOpen ? root.wifiPasswordText : ""

                    onAccepted: {
                      if (text.length > 0) root.connectWithPassphrase(row.net.ssid, text)
                    }
                    onTextChanged: if (row.isPasswordOpen && text !== root.wifiPasswordText) root.wifiPasswordText = text
                    Keys.onEscapePressed: root.cancelPasswordPrompt()

                    onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
                    Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
                  }

                  BorderSurface {
                    id: statusMsgWrapper
                    visible: row.isBusy || row.isFailed
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.spacing.controlHeight
                    color: Style.normalFillFor(root.fg)
                    borderSpec: Border.controlSpec("normal", root.fg, root.accent)
                    radius: Style.cornerRadius

                    Text {
                      anchors.fill: parent
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: row.isFailed ? "Wrong password" : "Connecting..."
                      color: row.isFailed ? Color.urgent : root.fg
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  PanelActionButton {
                    id: connectPwBtn
                    visible: !row.isBusy && !row.isFailed
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: row.net && pwField.text.length > 0
                    iconText: "󰄬"
                    tooltipText: "Connect"
                    foreground: root.fg
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onClicked: {
                      if (pwField.text.length > 0) root.connectWithPassphrase(row.net.ssid, pwField.text)
                    }
                  }
                }
              }
            }
          }
        }

        // No wifi hardware
        Text {
          visible: !root.wifiStationAvailable
          text: "No Wi-Fi adapter found"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }

      // Bluetooth sub-panel (inline, like Wi-Fi)
      Column {
        id: bluetoothColumn
        visible: root.bluetoothExpanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header with back button and power toggle
        Row {
          width: parent.width
          spacing: Style.space(8)
          z: 5
          Text {
            id: bluetoothBackBtn
            text: "← Bluetooth"
            color: root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            z: 10
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              enabled: true
              z: 10
              onClicked: root.bluetoothExpanded = false
            }
          }
          Item { width: parent.width - bluetoothBackBtn.implicitWidth - bluetoothPowerToggle.implicitWidth - parent.spacing; height: 1 }
          Rectangle {
            id: bluetoothPowerToggle
            width: Style.space(34)
            implicitWidth: width
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.bluetoothEnabled ? root.accent : Util.alpha(root.fg, 0.13)
            Text {
              anchors.centerIn: parent
              text: root.bluetoothEnabled ? "󰂯" : "󰂲"
              color: root.bluetoothEnabled ? root.onAccent(root.accent) : root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleBluetooth()
            }
          }
        }

        Text {
          visible: !root.adapter
          text: "No Bluetooth adapter"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          visible: root.adapter && !root.adapter.enabled
          text: "Turn Bluetooth on to scan"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          visible: root.adapter && root.adapter.enabled && root.adapter.discovering
          text: "SCANNING…"
          color: Util.alpha(root.fg, 0.52)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        Column {
          id: bluetoothConnectedList
          visible: root.bluetoothConnectedDevices.length > 0
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: "CONNECTED"
            color: Util.alpha(root.fg, 0.52)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
          Repeater {
            model: root.bluetoothConnectedRows
            delegate: BluetoothDeviceRow {
              required property var modelData
              required property int index
              width: bluetoothConnectedList.width
              dev: modelData
              rowIndex: index
              sectionName: "connected"
              isDiscovered: false
            }
          }
        }

        ListView {
          id: bluetoothListView
          visible: root.adapter && root.adapter.enabled
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.bluetoothScrollRows
          currentIndex: root.bluetoothScrollRowIndex
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(function() { positionViewAtIndex(currentIndex, ListView.Contain) })
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: root.bluetoothScrollSectionTitle(index)
            width: ListView.view.width
            height: delegateBtCol.implicitHeight
            Column {
              id: delegateBtCol
              width: parent.width
              spacing: Style.space(4)
              Text {
                visible: sectionTitle !== ""
                text: sectionTitle
                color: Util.alpha(root.fg, 0.52)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                height: visible ? implicitHeight : 0
              }
              BluetoothDeviceRow {
                width: parent.width
                dev: modelData.dev
                rowIndex: modelData.indexInSection
                sectionName: modelData.section
                isDiscovered: modelData.section === "discovered"
              }
            }
          }
        }

        Text {
          visible: root.adapter && root.adapter.enabled && root.bluetoothConnectedDevices.length === 0 && root.bluetoothScrollRows.length === 0 && !root.adapter.discovering
          text: "No devices found"
          color: Util.alpha(root.fg, 0.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  // ----------------------------------------------------------------------
  // Processes
  // ----------------------------------------------------------------------

  Process {
    id: brightnessProc
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBrightness(text) }
  }

  Process {
    id: brightnessSetProc
    onExited: root.refresh()
  }

  Timer {
    id: brightnessDebounce
    interval: 120
    repeat: false
    onTriggered: {
      brightnessSetProc.command = ["omarchy-brightness-display", "--no-osd", root.brightnessPercent + "%"]
      brightnessSetProc.running = true
    }
  }

  Process {
    id: themeProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateTheme(text) }
  }

  Process {
    id: tailscaleProc
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateTailscale(text) }
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // WiFi scan timers
  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.wifiExpanded && root.wifiDevice) {
        root.setWifiScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Component.onDestruction: {
    if (root.wifiScannerDevice) root.wifiScannerDevice.scannerEnabled = false
    if (root.bluetoothOwesDiscoveryStop) {
      var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
      for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i] !== root) { items[i].bluetoothOwesDiscoveryStop = true; return }
      }
      if (root.adapter !== null && root.adapter.discovering) root.adapter.discovering = false
    }
  }

  Timer {
    id: wifiActionTimeout
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.wifiActionKind) return
      root.wifiFailureSsid = root.wifiActionSsid
      root.wifiFailureReason = "Timed out"
      root.wifiActionSsid = ""
      root.wifiActionKind = ""
      root.startWifiScan()
    }
  }

  // Bluetooth discovery (upstream pattern, but only if adapter enabled)
  Timer {
    id: bluetoothDiscoveryRetry
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.bluetoothExpanded && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.bluetoothOwesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  Timer {
    id: bluetoothDiscoveryStop
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.bluetoothExpanded && root.bluetoothOwesDiscoveryStop && root.adapter !== null && root.adapter.discovering === true
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      var sibling = root.bluetoothOpenSibling()
      if (sibling) { sibling.bluetoothOwesDiscoveryStop = true; root.bluetoothOwesDiscoveryStop = false; return }
      attempts += 1
      if (attempts > 3) { root.bluetoothOwesDiscoveryStop = false; return }
      root.adapter.discovering = false
    }
  }

  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (!root.adapter.discovering) root.bluetoothOwesDiscoveryStop = false
    }
  }

  Timer {
    id: bluetoothPendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.bluetoothPendingActions = ({})
  }

  Timer {
    id: bluetoothAudioSwitchTimer
    interval: 500
    repeat: false
    onTriggered: root.bluetoothSwitchPendingAudio()
  }

  // Bluetooth device row (inline, mirrors omarchy.bluetooth DeviceRow)
  component BluetoothDeviceRow: CursorSurface {
    id: btRow
    required property var dev
    required property int rowIndex
    required property string sectionName
    required property bool isDiscovered

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string action: root.bluetoothPendingAction(dev ? dev.address : "")
    readonly property bool rowSelected: root.bluetoothCursorActive && root.bluetoothFocusSection === sectionName && root.bluetoothSelectedIndex === rowIndex
    readonly property bool forgetAvailable: (sectionName === "known" || sectionName === "connected") && !isDiscovered
    readonly property bool showForgetButton: forgetAvailable && (btMouse.containsMouse || rowSelected)

    hasCursor: rowSelected && !root.bluetoothActionFocused
    current: isConnected
    foreground: root.fg
    fill: root.hoverFill
    currentFill: root.selectedFill

    readonly property string statusText: {
      if (!dev) return ""
      if (action === "forgetting") return "Forgetting…"
      if (action === "disconnecting" || devState === 2) return "Disconnecting…"
      if (isConnected) {
        if (dev.batteryAvailable) return Math.round(dev.battery * 100) + "%"
        return sectionName === "connected" ? "" : "Connected"
      }
      if (action === "connecting" || devState === 3 || dev.pairing === true) return "Connecting…"
      if (isDiscovered) return ""
      return ""
    }
    readonly property color statusColor: {
      if (isConnected) return root.fg
      if (action !== "" || devState === 3 || dev.pairing === true) return root.fg
      return Util.alpha(root.fg, 0.62)
    }

    implicitHeight: btContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: btMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: dev ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) {
        root.bluetoothCursorActive = true
        root.bluetoothFocusSection = btRow.sectionName
        root.bluetoothSelectedIndex = btRow.rowIndex
        root.bluetoothActionFocused = false
      }
      onClicked: function(mouse) {
        var devObj = root.bluetoothDeviceFor(btRow)
        if (!devObj) return
        if (mouse.button === Qt.RightButton) {
          if (btRow.isConnected) root.bluetoothDisconnectDevice(devObj)
          else if (!btRow.isDiscovered) root.bluetoothForgetDevice(devObj)
          return
        }
        if (btRow.isConnected) root.bluetoothDisconnectDevice(devObj)
        else root.bluetoothConnectDevice(devObj)
      }
    }

    Item {
      id: btContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(btIcon.implicitHeight, btInfo.implicitHeight, btForgetBtn.implicitHeight)
      Text {
        id: btIcon
        text: btRow.isConnected ? "󰂱" : "󰂯"
        color: btRow.statusColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        id: btInfo
        spacing: Style.space(1)
        anchors.left: btIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: btForgetBtn.visible ? btForgetBtn.left : parent.right
        anchors.rightMargin: btForgetBtn.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: root.bluetoothDeviceLabel(btRow.dev) || "Device"
          color: root.fg
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: btRow.statusText !== ""
          text: btRow.statusText
          color: btRow.statusColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
      PanelActionButton {
        id: btForgetBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: btRow.showForgetButton
        iconText: "󰅙"
        tooltipText: "Forget"
        foreground: root.fg
        hoverColor: root.fg
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        hasCursor: btRow.rowSelected && root.bluetoothActionFocused
        onHovered: function(isHovered) {
          if (!isHovered) { if (btMouse.containsMouse) root.bluetoothActionFocused = false; return }
          root.bluetoothCursorActive = true
          root.bluetoothFocusSection = btRow.sectionName
          root.bluetoothSelectedIndex = btRow.rowIndex
          root.bluetoothActionFocused = true
        }
        onClicked: {
          var devObj = root.bluetoothDeviceFor(btRow)
          if (!devObj) return
          root.bluetoothForgetDevice(devObj)
        }
      }
    }
  }

  // ----------------------------------------------------------------------
  // Components
  // ----------------------------------------------------------------------

  // Rounded frosted tile — the base surface every control sits on.
  component Tile: Rectangle {
    id: tile

    property bool active: false
    property bool hoverable: true
    property bool hasCursor: false
    property color foreground: root.fg
    property color accentColor: root.accent

    signal clicked
    signal rightClicked
    signal hoverSignal(bool isHovered)

    readonly property bool hot: hoverable && mouse.containsMouse

    radius: Style.space(14)
    color: active
      ? accentColor
      : (hot || hasCursor ? Util.alpha(foreground, 0.10) : Util.alpha(foreground, 0.055))
    border.width: hasCursor ? Math.max(1, Style.normalBorderWidth) : 0
    border.color: Util.alpha(foreground, 0.45)

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: tile.hoverable
      cursorShape: tile.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.LeftButton) tile.clicked()
        else tile.rightClicked()
      }
      onContainsMouseChanged: tile.hoverSignal(containsMouse)
    }
  }

  // Circular toggle inside the connectivity module: filled circle + status label.
  component CircleToggle: Tile {
    id: circle

    property string glyph: ""
    property string label: ""

    Column {
      anchors.centerIn: parent
      spacing: Style.space(3)

      Rectangle {
        width: Style.space(34)
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        color: circle.active
          ? circle.accentColor
          : Util.alpha(circle.foreground, circle.hot || circle.hasCursor ? 0.22 : 0.13)

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: circle.glyph
          color: circle.active ? root.onAccent(circle.accentColor) : circle.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: circle.label
        color: circle.active ? root.onAccent(circle.accentColor) : Util.alpha(circle.foreground, 0.62)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        width: circle.width - Style.space(8)
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  // Wide tile: circular icon on the left, title + subtitle stacked beside it.
  component IconTile: Tile {
    id: iconTile

    property string glyph: ""
    property string title: ""
    property string subtitle: ""

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(12)

      Rectangle {
        width: Style.space(36)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: iconTile.active
          ? root.onAccent(iconTile.accentColor)
          : Util.alpha(iconTile.foreground, iconTile.hot || iconTile.hasCursor ? 0.22 : 0.13)

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: iconTile.glyph
          color: iconTile.active ? iconTile.accentColor : iconTile.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }
      }

      Column {
        width: parent.width - parent.spacing - Style.space(36)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: iconTile.title
          color: iconTile.active ? root.onAccent(iconTile.accentColor) : iconTile.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: iconTile.subtitle
          color: iconTile.active
            ? Util.alpha(root.onAccent(iconTile.accentColor), 0.75)
            : Util.alpha(iconTile.foreground, 0.62)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // Full-width slider tile: icon (clickable secondary action) + slider.
  component SliderTile: Tile {
    id: sliderTile

    property string glyph: ""
    property string label: ""
    property string valueText: ""
    property real value: 0
    property bool dimmed: false

    signal moved(real v)
    signal released(real v)
    signal iconClicked

    opacity: dimmed ? 0.55 : 1.0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      id: sliderIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(34)
      height: width
      radius: width / 2
      color: Util.alpha(sliderTile.foreground, 0.13)

      Text {
        anchors.centerIn: parent
        text: sliderTile.glyph
        color: sliderTile.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sliderTile.iconClicked()
      }
    }

    Column {
      anchors.left: sliderIcon.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

        Text {
          id: labelText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: sliderTile.label
          color: sliderTile.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          id: valueText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: sliderTile.valueText
          color: Util.alpha(sliderTile.foreground, 0.62)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Item {
        id: sliderHost
        width: parent.width
        height: sliderControl.implicitHeight

        PanelSlider {
          id: sliderControl
          anchors.fill: parent
          bar: root.bar
          value: sliderTile.value
          minimum: 0
          maximum: 1
          step: 0.05

          onMoved: function(v) { sliderTile.moved(v) }
          onReleased: function(v) { sliderTile.released(v) }
          onRightClicked: sliderTile.rightClicked()
        }

        // Step dots: faint markers in the unfilled portion only — the fill
        // swallows them as it advances, and they fade out under the knob.
        Repeater {
          model: 9

          Rectangle {
            required property int index
            readonly property real fraction: (index + 1) / 10
            readonly property bool behindFill: fraction <= sliderControl.progress

            width: Style.space(3)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width, parent.width * fraction - width / 2))
            color: behindFill ? "transparent" : Util.alpha(sliderTile.foreground, 0.28)
            opacity: Math.abs(fraction - sliderControl.progress) < 0.05 ? 0 : 1

            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }
      }
    }
  }

  // Small circular transport button for the media tile.
  component MiniButton: Rectangle {
    id: mini

    property string glyph: ""
    property bool hasCursor: false

    signal clicked
    signal hoverSignal(bool isHovered)

    readonly property bool hot: miniMouse.containsMouse

    width: Style.space(32)
    height: width
    radius: width / 2
    color: hot || hasCursor ? Util.alpha(root.fg, 0.22) : Util.alpha(root.fg, 0.13)
    border.width: hasCursor ? Math.max(1, Style.normalBorderWidth) : 0
    border.color: Util.alpha(root.fg, 0.45)

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: mini.glyph
      color: root.fg
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: miniMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mini.clicked()
      onContainsMouseChanged: mini.hoverSignal(containsMouse)
    }
  }
}
