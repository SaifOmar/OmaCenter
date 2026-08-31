import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.bluetooth"

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothEnabled: adapter ? adapter.enabled : false
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var connectedDevices: devices ? devices.filter(function(d) { return d.connected }) : []
  readonly property int connectedCount: connectedDevices.length

  readonly property string bluetoothStatus: !root.bluetoothEnabled
    ? "Off"
    : (root.connectedCount > 0 ? root.connectedDevices[0].name || root.connectedDevices[0].address || "Device" : "On")

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, (bluetoothEnabled || mouseArea.containsMouse) ? 0.12 : 0.055)
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
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.bluetoothEnabled ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: root.bluetoothEnabled ? "󰂯" : "󰂲"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.bluetoothStatus
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
        if (root.panel) root.panel.expandModule(root.moduleId, "Bluetooth")
      } else {
        Quickshell.execDetached(["omarchy-bluetooth-power", root.bluetoothEnabled ? "off" : "on"])
      }
    }
  }
}
