import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.display"

  property real percent: 1.0

  function setBrightness(val) {
    var clamped = Math.max(0.01, Math.min(1.0, val))
    root.percent = clamped
    var intPct = Math.round(clamped * 100)
    Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", intPct.toString() + "%"])
  }

  function checkBrightness(raw) {
    try {
      var lines = raw.trim().split("\n")
      var val = parseFloat(lines[0])
      if (!isNaN(val)) {
        root.percent = val > 1.0 ? Math.min(1.0, val / 100.0) : val
      }
    } catch (e) {}
  }

  Process {
    id: checkProc
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkBrightness(text)
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!checkProc.running) checkProc.running = true
    }
  }

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, mouseArea.containsMouse ? 0.12 : 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  Behavior on color { ColorAnimation { duration: 120 } }
  implicitHeight: Style.space(58)

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.panel) root.panel.expandModule(root.moduleId, "Display Management")
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    Row {
      width: parent.width

      Row {
        spacing: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          width: Style.space(24)
          height: width
          radius: width / 2
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

          Text {
            anchors.centerIn: parent
            text: "󰍹"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Text {
          text: "Display"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Item {
        width: parent.width - parent.children[0].implicitWidth - valText.implicitWidth
        height: 1
      }

      Text {
        id: valText
        text: Math.round(root.percent * 100) + "%"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Item {
      width: parent.width
      height: Style.space(16)

      Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Style.space(6)
        radius: height / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * root.percent))
          height: parent.height
          radius: height / 2
          color: root.panel ? root.panel.fg : Color.foreground
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          mouse.accepted = true
          root.setBrightness(mouse.x / width)
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.setBrightness(mouse.x / width)
        }
      }
    }
  }
}
