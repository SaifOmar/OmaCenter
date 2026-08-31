import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "../../Model.js" as Model

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.wifi"

  implicitHeight: wifiContent.implicitHeight

  // ─── WiFi state ────────────────────────────────────────────

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
  property string wifiPasswordSsid: ""
  property string wifiPasswordText: ""
  property string wifiActionSsid: ""
  property string wifiActionKind: ""
  property string wifiFailureSsid: ""
  property string wifiFailureReason: ""
  readonly property bool busy: wifiActionKind !== ""
  readonly property bool wifiEnabled: Networking.wifiEnabled

  // ─── Helpers ───────────────────────────────────────────────

  function setWifiScannerEnabled(enabled) {
    var nextDevice = root.wifiDevice
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

  // ─── Lifecycle ─────────────────────────────────────────────

  Component.onCompleted: {
    root.syncWifiNetworks()
    root.startWifiScan()
  }

  Component.onDestruction: {
    if (root.wifiScannerDevice) root.wifiScannerDevice.scannerEnabled = false
  }

  // ─── Timers ────────────────────────────────────────────────

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.wifiDevice) {
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

  // ─── UI ────────────────────────────────────────────────────

  Column {
    id: wifiContent
    width: parent.width
    spacing: Style.space(10)

    // Power toggle
    Row {
      width: parent.width

      Item { width: parent.width - powerToggle.width; height: 1 }

      Rectangle {
        id: powerToggle
        width: Style.space(34)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.wifiEnabled ? 0.18 : 0.13)

        Text {
          anchors.centerIn: parent
          text: root.wifiEnabled ? "󰤨" : "󰤭"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (Networking.backend === NetworkBackendType.NetworkManager)
              Networking.wifiEnabled = !Networking.wifiEnabled
          }
        }
      }
    }

    // Scanning indicator
    Text {
      visible: root.wifiScanning
      text: "SCANNING WI-FI\u2026"
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
            color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            height: visible ? implicitHeight : 0
          }

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
            foreground: root.panel ? root.panel.fg : Color.foreground
            fill: root.panel ? root.panel.hoverFill : Style.hoverFillFor(Color.foreground, Color.accent)
            currentFill: root.panel ? root.panel.selectedFill : Style.selectedFillFor(Color.foreground, Color.accent)

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

              onClicked: {
                if (!row.net) return
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
              if (isBusy && root.wifiActionKind === "connect") return "Connecting\u2026"
              if (isBusy && root.wifiActionKind === "disconnect") return "Disconnecting\u2026"
              if (isFailed) return root.wifiFailureReason || "Failed"
              if (isConnected) return "Connected"
              return ""
            }

            readonly property color statusColor: {
              if (isFailed) return Color.urgent
              if (isBusy || isConnected) return (root.panel ? root.panel.fg : Color.foreground)
              return Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
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
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
                  color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
                  font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.subtitle
                }

                MouseArea {
                  id: rightMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  enabled: row.canForget && !root.busy
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (row.net) root.forgetNetwork(row.net)
                }

                Text {
                  visible: row.canForget && rightMouse.containsMouse
                  anchors.centerIn: parent
                  text: "󰅙"
                  color: Color.urgent
                  font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
                  color: root.panel ? root.panel.fg : Color.foreground
                  font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  text: row.statusText
                  visible: row.statusText !== ""
                  height: visible ? implicitHeight : 0
                  color: row.statusColor
                  font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                foreground: root.panel ? root.panel.fg : Color.foreground
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
                visible: row.isBusy || row.isFailed
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.controlHeight
                color: Style.normalFillFor(root.panel ? root.panel.fg : Color.foreground)
                borderSpec: Border.controlSpec("normal", root.panel ? root.panel.fg : Color.foreground, root.panel ? root.panel.fg : Color.foreground)
                radius: Style.cornerRadius

                Text {
                  anchors.fill: parent
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: row.isFailed ? "Wrong password" : "Connecting..."
                  color: row.isFailed ? Color.urgent : (root.panel ? root.panel.fg : Color.foreground)
                  font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
                foreground: root.panel ? root.panel.fg : Color.foreground
                fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
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
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
}
