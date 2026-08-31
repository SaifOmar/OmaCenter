import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "../../Model.js" as Model

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.bluetooth"

  implicitHeight: btContent.implicitHeight

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothEnabled: adapter ? adapter.enabled : false
  readonly property var bluetoothDevices: Bluetooth.devices ? Bluetooth.devices.values : []

  readonly property var bluetoothDeviceGroups: Model.deviceLists(bluetoothDevices)
  readonly property var bluetoothConnectedDevices: bluetoothDeviceGroups.connected || []
  readonly property var bluetoothKnownDevices: bluetoothDeviceGroups.known || []
  readonly property var bluetoothDiscoveredDevices: bluetoothDeviceGroups.discovered || []

  Component.onCompleted: {
    if (adapter && adapter.enabled && !adapter.discovering) {
      adapter.discovering = true
    }
  }

  Column {
    id: btContent
    width: parent.width
    spacing: Style.space(10)

    // Power toggle row (aligned right to avoid overlapping header)
    Row {
      width: parent.width
      height: Style.space(34)

      Item {
        width: parent.width - powerToggle.width
        height: 1
      }

      Rectangle {
        id: powerToggle
        width: Style.space(34)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.bluetoothEnabled ? 0.18 : 0.13)

        Text {
          anchors.centerIn: parent
          text: root.bluetoothEnabled ? "󰂯" : "󰂲"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Quickshell.execDetached(["omarchy-bluetooth-power", root.bluetoothEnabled ? "off" : "on"])
          }
        }
      }
    }

    Text {
      visible: !root.adapter
      text: "No Bluetooth adapter"
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      visible: root.adapter && !root.adapter.enabled
      text: "Turn Bluetooth on to scan"
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    Column {
      visible: root.adapter && root.adapter.enabled && root.bluetoothConnectedDevices.length > 0
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: "CONNECTED"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.bluetoothConnectedDevices
        delegate: Rectangle {
          required property var modelData
          width: parent.width
          height: Style.space(36)
          radius: Style.space(8)
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.05)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "󰂱"
                color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: Model.deviceLabel(modelData)
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: parent.width - Style.space(70)
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: Style.space(50)
              height: Style.space(22)
              radius: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

              Text {
                anchors.centerIn: parent
                text: "Disconnect"
                color: root.panel ? root.panel.fg : Color.foreground
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData) modelData.disconnect()
                }
              }
            }
          }
        }
      }
    }

    Column {
      visible: root.adapter && root.adapter.enabled && (root.bluetoothKnownDevices.length > 0 || root.bluetoothDiscoveredDevices.length > 0)
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: "PAIRED & DISCOVERED"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.bluetoothKnownDevices.concat(root.bluetoothDiscoveredDevices)
        delegate: Rectangle {
          required property var modelData
          width: parent.width
          height: Style.space(36)
          radius: Style.space(8)
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.03)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "󰂯"
              color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: Model.deviceLabel(modelData) || "Unknown Device"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width - Style.space(70)
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: Style.space(50)
              height: Style.space(22)
              radius: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

              Text {
                anchors.centerIn: parent
                text: "Connect"
              color: root.panel ? root.panel.fg : Color.foreground
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData) modelData.connect()
                }
              }
            }
          }
        }
      }
    }
  }
}
