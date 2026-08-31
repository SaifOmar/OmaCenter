import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.screenshot"

  implicitHeight: captureContent.implicitHeight

  property var pendingCmd: []

  readonly property var captureModes: [
    { id: "smart", name: "Smart Capture", icon: "󰹑", desc: "Interactive region or window selection", cmd: ["omarchy-capture-screenshot", "smart"] },
    { id: "fullscreen", name: "Entire Screen", icon: "󰍹", desc: "Capture full desktop display", cmd: ["omarchy-capture-screenshot", "fullscreen"] },
    { id: "record", name: "Screen Recording", icon: "󰕧", desc: "Record video of screen area", cmd: ["omarchy-capture-screenrecording"] }
  ]

  Timer {
    id: delayTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (root.pendingCmd && root.pendingCmd.length > 0) {
        Quickshell.execDetached(root.pendingCmd)
      }
    }
  }

  function runCapture(cmdArray) {
    root.pendingCmd = cmdArray
    if (root.panel) {
      if (typeof root.panel.collapseExpanded === "function") root.panel.collapseExpanded()
      if (typeof root.panel.close === "function") root.panel.close()
    }
    delayTimer.restart()
  }

  Column {
    id: captureContent
    width: parent.width
    spacing: Style.space(8)

    Text {
      text: "SCREEN CAPTURE MODES"
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Repeater {
      model: root.captureModes
      delegate: Rectangle {
        required property var modelData
        width: parent.width
        height: Style.space(48)
        radius: Style.space(10)
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.04)

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          Text {
            text: modelData.icon
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            width: parent.width - Style.space(40)

            Text {
              text: modelData.name
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: modelData.desc
              color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.runCapture(modelData.cmd)
        }
      }
    }
  }
}
