import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
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
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var adapter: Bluetooth.defaultAdapter

  readonly property var player: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: mediaService ? mediaService.hasMedia : false
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
  property var pendingPowerAction: null
  property string pendingPowerLabel: ""

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

  readonly property string wifiStatus: root.wifiEnabled ? "On" : "Off"
  readonly property string bluetoothStatus: root.bluetoothEnabled
    ? (root.connectedBluetoothCount > 0 ? "On · " + root.connectedBluetoothCount : "On")
    : "Off"
  readonly property string tailscaleStatus: {
    if (root.tailscaleState === "On") return root.tailscaleHost !== "" ? "On · " + root.tailscaleHost : "On"
    if (root.tailscaleState === "Login") return "Login"
    return "Off"
  }
  readonly property string micStatus: root.micMuted ? "Muted" : "Live"
  readonly property string nightlightStatus: root.nightlightEnabled ? "On" : "Off"
  readonly property string dndStatus: root.dndEnabled ? "Silenced" : "On"

  // ----------------------------------------------------------------------
  // Keyboard cursor: a flat list of focusable targets. j/k walk the list,
  // h/l adjust sliders or move along horizontal runs (media, power).
  // ----------------------------------------------------------------------

  readonly property var targets: {
    var t = ["wifi", "bluetooth", "tailscale", "nightlight", "dnd", "mic", "volume", "brightness"]
    if (root.hasMedia) t = t.concat(["mprev", "mplay", "mnext"])
    t = t.concat(["theme", "lock", "sleep", "reboot", "shutdown"])
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
    if (root.pendingPowerAction) return
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
    } else if (target === "mprev" || target === "mplay" || target === "mnext") {
      var mIdx = root.targets.indexOf("mprev")
      if (mIdx >= 0) {
        var mCount = 3
        var mCursor = Math.max(0, Math.min(mCount - 1, root.cursorIndex - mIdx + dx))
        root.cursorIndex = mIdx + mCursor
      }
    } else if (target === "lock" || target === "sleep" || target === "reboot" || target === "shutdown") {
      var pIdx = root.targets.indexOf("lock")
      if (pIdx >= 0) {
        var pCount = 4
        var pCursor = Math.max(0, Math.min(pCount - 1, root.cursorIndex - pIdx + dx))
        root.cursorIndex = pIdx + pCursor
      }
    }
  }

  function activateCursor() {
    if (root.pendingPowerAction) return
    var target = root.currentTarget()
    if (target === "wifi") toggleWifi()
    else if (target === "bluetooth") toggleBluetooth()
    else if (target === "tailscale") toggleTailscale()
    else if (target === "nightlight") toggleNightlight()
    else if (target === "dnd") toggleDnd()
    else if (target === "mic") toggleMic()
    else if (target === "mprev") mediaPrevious()
    else if (target === "mplay") togglePlayPause()
    else if (target === "mnext") mediaNext()
    else if (target === "theme") openThemeSwitcher()
    else if (target === "lock") doLock()
    else if (target === "sleep") doSleep()
    else if (target === "reboot") askPower("reboot", "Restart this machine?")
    else if (target === "shutdown") askPower("shutdown", "Shut down this machine?")
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

  function askPower(action, message) {
    root.pendingPowerAction = action
    root.pendingPowerLabel = message
    confirmDialog.selectedIndex = 1
  }

  function runPendingPower() {
    var action = root.pendingPowerAction
    root.pendingPowerAction = null
    if (action === "reboot") Quickshell.execDetached(["omarchy", "system", "reboot"])
    else if (action === "shutdown") Quickshell.execDetached(["omarchy", "system", "shutdown"])
  }

  function cancelPendingPower() {
    root.pendingPowerAction = null
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
      onMoveRequested: function(dx, dy) {
        if (root.pendingPowerAction) {
          if (dx !== 0 || dy !== 0) confirmDialog.selectedIndex = 1 - confirmDialog.selectedIndex
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.pendingPowerAction) {
          if (confirmDialog.selectedIndex === 1) root.runPendingPower()
          else root.cancelPendingPower()
          return
        }
        root.activateCursor()
      }
      onCloseRequested: {
        if (root.pendingPowerAction) root.cancelPendingPower()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(16)

        // ---------- Header ----------
        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Text {
            id: headerTitle
            text: "Control Center"
            color: root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            text: "esc"
            color: Qt.darker(root.fg, 1.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        // ---------- Quick controls ----------
        Column {
          width: parent.width
          spacing: Style.spacing.sm

          ToggleRow {
            label: "Wi-Fi"
            status: root.wifiStatus
            checked: root.wifiEnabled
            hasCursor: root.hasCursor("wifi")
            onHovered: function(h) { if (h) root.setCursor("wifi") }
            onClicked: root.toggleWifi()
          }
          ToggleRow {
            label: "Bluetooth"
            status: root.bluetoothStatus
            checked: root.bluetoothEnabled
            hasCursor: root.hasCursor("bluetooth")
            onHovered: function(h) { if (h) root.setCursor("bluetooth") }
            onClicked: root.toggleBluetooth()
          }
          ToggleRow {
            label: "Tailscale"
            status: root.tailscaleStatus
            checked: root.tailscaleState === "On"
            hasCursor: root.hasCursor("tailscale")
            onHovered: function(h) { if (h) root.setCursor("tailscale") }
            onClicked: root.toggleTailscale()
          }
          ToggleRow {
            label: "Night Light"
            status: root.nightlightStatus
            checked: root.nightlightEnabled
            hasCursor: root.hasCursor("nightlight")
            onHovered: function(h) { if (h) root.setCursor("nightlight") }
            onClicked: root.toggleNightlight()
          }
          ToggleRow {
            label: "Do Not Disturb"
            status: root.dndStatus
            checked: root.dndEnabled
            hasCursor: root.hasCursor("dnd")
            onHovered: function(h) { if (h) root.setCursor("dnd") }
            onClicked: root.toggleDnd()
          }
          ToggleRow {
            label: "Microphone"
            status: root.micStatus
            checked: !root.micMuted
            hasCursor: root.hasCursor("mic")
            onHovered: function(h) { if (h) root.setCursor("mic") }
            onClicked: root.toggleMic()
          }
        }

        // ---------- Volume & brightness ----------
        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.space(14)

          SliderRow {
            label: "Volume"
            valueText: root.outputMuted ? "muted" : Math.round(root.outputVolume * 100) + "%"
            value: root.outputVolume
            dimmed: root.outputMuted
            bar: root.bar
            hasCursor: root.hasCursor("volume")
            onHovered: function(h) { if (h) root.setCursor("volume") }
            onMoved: root.setOutputVolume(v)
            onRightClicked: root.toggleMute()
            onReleased: root.setOutputVolume(v)
          }

          SliderRow {
            label: "Brightness"
            valueText: root.brightnessPercent + "%"
            value: root.brightnessAvailable ? root.brightnessPercent / 100 : 0
            maximum: 1
            integerSteps: true
            bar: root.bar
            hasCursor: root.hasCursor("brightness")
            onHovered: function(h) { if (h) root.setCursor("brightness") }
            onMoved: root.setBrightness(v * 100)
            onReleased: function(v) {
              root.setBrightness(v * 100)
              root.showBrightnessOsd(Math.round(v * 100))
            }
          }
        }

        // ---------- Now playing ----------
        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        Item {
          width: parent.width
          height: root.hasMedia ? mediaRow.implicitHeight : Style.space(30)

          Column {
            visible: !root.hasMedia
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            Text {
              text: "Now Playing"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              text: "Nothing playing"
              color: Qt.darker(root.fg, 1.6)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }

          RowLayout {
            id: mediaRow
            visible: root.hasMedia
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Column {
              width: Math.max(0, parent.width - mediaButtons.implicitWidth - parent.spacing)
              spacing: Style.spacing.xs

              Text {
                text: root.mediaTitle
                color: root.fg
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.mediaArtist
                color: Qt.darker(root.fg, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: mediaButtons
              Layout.alignment: Qt.AlignVCenter
              spacing: Style.spacing.xs

              Button {
                iconText: "󰒭"
                iconSize: Style.font.title
                bordered: true
                hasCursor: root.hasCursor("mprev")
                foreground: root.fg
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.mediaPrevious()
                onHovered: function(h) { if (h) root.setCursor("mprev") }
              }

              Button {
                iconText: root.mediaPlaying ? "󰒰" : "󰒮"
                iconSize: Style.font.title
                bordered: true
                hasCursor: root.hasCursor("mplay")
                foreground: root.fg
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.togglePlayPause()
                onHovered: function(h) { if (h) root.setCursor("mplay") }
              }

              Button {
                iconText: "󰒱"
                iconSize: Style.font.title
                bordered: true
                hasCursor: root.hasCursor("mnext")
                foreground: root.fg
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.mediaNext()
                onHovered: function(h) { if (h) root.setCursor("mnext") }
              }
            }
          }
        }

        // ---------- Theme ----------
        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        Button {
          width: parent.width
          text: root.themeName !== "" ? "Theme — " + root.themeName : "Theme"
          iconText: "󰍜"
          iconSize: Style.font.title
          fontSize: Style.font.body
          leftAlign: true
          bordered: true
          hasCursor: root.hasCursor("theme")
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          onClicked: root.openThemeSwitcher()
          onHovered: function(h) { if (h) root.setCursor("theme") }
        }

        // ---------- Power ----------
        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm

          Row {
            id: powerRow
            width: parent.width
            spacing: Style.spacing.sm

            readonly property real cellWidth: (width - spacing * 3) / 4

            Repeater {
              model: ["Lock", "Sleep", "Reboot", "Shutdown"]
              Button {
                required property string modelData
                required property int index

                width: powerRow.cellWidth
                text: String(modelData).toUpperCase()
                fontSize: Style.font.bodySmall
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                horizontalPadding: 0
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                foreground: root.fg
                hasCursor: root.hasCursor(["lock", "sleep", "reboot", "shutdown"][index])
                onClicked: {
                  if (index === 0) root.doLock()
                  else if (index === 1) root.doSleep()
                  else if (index === 2) root.askPower("reboot", "Restart this machine?")
                  else root.askPower("shutdown", "Shut down this machine?")
                }
                onHovered: function(h) { if (h) root.setCursor(["lock", "sleep", "reboot", "shutdown"][index]) }
              }
            }
          }
        }

        // Bottom breathing room
        Item { width: 1; height: Style.space(2) }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        visible: root.pendingPowerAction !== null
        message: root.pendingPowerLabel
        confirmText: "Confirm"
        background: Color.popups.background
        foreground: root.fg
        onConfirmed: root.runPendingPower()
        onCanceled: root.cancelPendingPower()
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
  // Row components
  // ----------------------------------------------------------------------

  component ToggleRow: Item {
    id: row

    property string label: ""
    property string status: ""
    property bool checked: false
    property bool hasCursor: false
    property color foreground: root.fg
    property color accent: root.accent
    property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

    signal clicked
    signal hovered(bool isHovered)

    readonly property bool hot: row.hasCursor || mouse.containsMouse

    height: Style.space(38)
    implicitWidth: parent ? parent.width : Style.space(240)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.hot ? Style.hoverFillFor(row.foreground, row.accent) : "transparent"

      Behavior on color { ColorAnimation { duration: 100 } }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Text {
        text: row.label
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Text {
        text: row.status
        color: Qt.darker(row.foreground, 1.5)
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      ToggleSwitch {
        checked: row.checked
        hasCursor: row.hasCursor
        interactive: false
        foreground: row.foreground
        accent: row.accent
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
      onContainsMouseChanged: row.hovered(containsMouse)
    }
  }

  component SliderRow: Item {
    id: slider

    property string label: ""
    property string valueText: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property bool dimmed: false
    property bool hasCursor: false
    property bool integerSteps: false
    property QtObject bar: null
    property color foreground: root.fg
    property color accent: root.accent
    property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

    signal moved(real v)
    signal released(real v)
    signal rightClicked
    signal hovered(bool isHovered)

    readonly property int labelH: Style.space(18)
    readonly property int sliderH: Style.space(24)
    readonly property int gap: Style.spacing.sm

    height: labelH + gap + sliderH
    implicitWidth: parent ? parent.width : Style.space(240)
    opacity: root.dimmed ? 0.55 : 1.0

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: slider.hasCursor ? Style.hoverFillFor(slider.foreground, slider.accent) : "transparent"

      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Text {
      text: slider.label
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.top: parent.top
      anchors.topMargin: Style.space(2)
      color: slider.foreground
      font.family: slider.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      text: slider.valueText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.top: parent.top
      anchors.topMargin: Style.space(2)
      color: Qt.darker(slider.foreground, 1.5)
      font.family: slider.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    PanelSlider {
      id: sliderControl
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.bottomMargin: Style.space(2)
      bar: slider.bar
      value: slider.value
      minimum: slider.minimum
      maximum: slider.maximum
      step: slider.integerSteps ? 0.05 : 0.05
      integer: false

      onMoved: function(v) { slider.moved(v) }
      onReleased: function(v) { slider.released(v) }
      onRightClicked: slider.rightClicked()
    }

    HoverHandler {
      onHoveredChanged: slider.hovered(hovered)
    }
  }
}
