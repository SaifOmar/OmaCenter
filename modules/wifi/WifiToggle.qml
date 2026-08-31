import QtQuick
import Quickshell.Networking
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.wifi"

  readonly property bool wifiEnabled: Networking.wifiEnabled
  readonly property var wifiDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: {
    for (var i = 0; i < root.wifiDevices.length; i++) {
      var device = root.wifiDevices[i]
      if (!device || device.type !== DeviceType.Wifi) continue
      if (device.connected) return device
    }
    return null
  }
  readonly property string wifiSsid: {
    if (!root.wifiDevice) return ""
    var networks = root.wifiDevice.networks ? root.wifiDevice.networks.values : []
    for (var j = 0; j < networks.length; j++) {
      if (networks[j] && networks[j].connected) return networks[j].name || ""
    }
    return ""
  }
  readonly property string wifiStatus: !root.wifiEnabled
    ? "Off"
    : (root.wifiSsid !== "" ? root.wifiSsid : "On")

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, (wifiEnabled || mouseArea.containsMouse) ? 0.12 : 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  Behavior on color { ColorAnimation { duration: 120 } }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(3)

    Rectangle {
      width: Style.space(34)
      height: width
      radius: width / 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.wifiEnabled ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: root.wifiEnabled ? "󰤨" : "󰤭"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.wifiStatus
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      width: root.width - Style.space(8)
      horizontalAlignment: Text.AlignHCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) {
        if (root.panel) root.panel.expandModule(root.moduleId, "Wi-Fi")
      } else {
        // Right-click: toggle WiFi
        if (Networking.backend === NetworkBackendType.NetworkManager)
          Networking.wifiEnabled = !Networking.wifiEnabled
      }
    }
  }
}
