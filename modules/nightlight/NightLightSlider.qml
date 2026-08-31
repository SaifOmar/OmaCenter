import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.nightlight"

  property bool nightlightEnabled: false
  property int temperatureK: 4000
  readonly property real warmthRatio: Math.max(0, Math.min(1, (6000 - temperatureK) / 4000))

  function updateStatus(raw) {
    try {
      var d = JSON.parse(raw)
      root.nightlightEnabled = d.enabled === true
      if (d.temperature && d.temperature > 0) {
        root.temperatureK = d.temperature
      }
    } catch (e) {
      root.nightlightEnabled = false
    }
  }

  function toggleNightLight() {
    Quickshell.execDetached(["omarchy-toggle-nightlight"])
    refreshTimer.restart()
  }

  function setTemperature(tempK) {
    root.temperatureK = tempK
    root.nightlightEnabled = tempK < 6000
    Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", tempK.toString()])
    refreshTimer.restart()
  }

  Process {
    id: statusProc
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStatus(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (!statusProc.running) statusProc.running = true
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!statusProc.running) statusProc.running = true
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
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.panel) root.panel.summonPanel("omarchy.nightlight")
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    // Label and percentage header
    Row {
      width: parent.width

      Row {
        spacing: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          width: Style.space(24)
          height: width
          radius: width / 2
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.nightlightEnabled ? 0.18 : 0.1)

          Text {
            anchors.centerIn: parent
            text: root.nightlightEnabled ? "󰌵" : "󰌶"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleNightLight()
          }
        }

        Text {
          text: "Night Light"
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
        text: !root.nightlightEnabled
          ? "Off"
          : (root.temperatureK + "K (" + Math.round(root.warmthRatio * 100) + "%)")
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Slider Bar (Warmth Adjuster)
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
          width: !root.nightlightEnabled ? 0 : Math.max(0, Math.min(parent.width, parent.width * root.warmthRatio))
          height: parent.height
          radius: height / 2
          color: root.panel ? root.panel.fg : Color.foreground
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          var ratio = Math.max(0, Math.min(1, mouse.x / width))
          var targetK = Math.round(6000 - (ratio * 4000))
          root.setTemperature(targetK)
        }
        onPositionChanged: function(mouse) {
          if (pressed) {
            var ratio = Math.max(0, Math.min(1, mouse.x / width))
            var targetK = Math.round(6000 - (ratio * 4000))
            root.setTemperature(targetK)
          }
        }
      }
    }
  }
}
