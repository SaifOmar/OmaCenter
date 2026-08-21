import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "saif.control-center"
  ipcTarget: "saif.control-center"

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

  readonly property int panelWidth: root.setting("width", 400)

  readonly property color fg: root.barForeground
  readonly property color accent: Color.accent

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
    var s = c.toString()
    var r = parseInt(s.substring(3, 5), 16) / 255
    var g = parseInt(s.substring(5, 7), 16) / 255
    var b = parseInt(s.substring(7, 9), 16) / 255
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
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
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
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
            color: Qt.darker(root.fg, 1.5)
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
                onRightClicked: root.summonPanel("omarchy.network")
                onHoverSignal: function(h) { if (h) root.setCursor("wifi") }
              }
              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: root.bluetoothEnabled ? "󰂯" : "󰂲"
                label: root.bluetoothStatus
                active: root.bluetoothEnabled
                hasCursor: root.hasCursor("bluetooth")
                onClicked: root.toggleBluetooth()
                onRightClicked: root.summonPanel("omarchy.bluetooth")
                onHoverSignal: function(h) { if (h) root.setCursor("bluetooth") }
              }
              CircleToggle {
                width: parent.cellWidth
                height: parent.cellHeight
                glyph: "󰘂"
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
                color: Qt.darker(root.fg, 1.5)
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
                color: parent.hot || parent.hasCursor ? root.fg : Qt.darker(root.fg, 1.3)
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
        color: circle.active ? root.onAccent(circle.accentColor) : Qt.darker(circle.foreground, 1.4)
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
            : Qt.darker(iconTile.foreground, 1.5)
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
          color: Qt.darker(sliderTile.foreground, 1.5)
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
