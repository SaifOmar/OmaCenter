import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.volume"

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0

  function setOutputVolume(v) {
    if (!root.sink || !root.sink.audio) return
    root.sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (root.sink && root.sink.audio) {
      root.sink.audio.muted = !root.sink.audio.muted
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
      if (root.panel) root.panel.expandModule(root.moduleId, "Sound Output")
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    // Label and percentage header
    Row {
      width: parent.width

      // Icon + Label
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
            text: root.outputMuted ? "󰝟" : "󰕾"
            color: root.outputMuted
              ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.4)
              : (root.panel ? root.panel.fg : Color.foreground)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(e) {
              e.accepted = true
              root.toggleMute()
            }
          }
        }

        Text {
          text: "Sound"
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
        text: root.outputMuted ? "Muted" : Math.round(root.outputVolume * 100) + "%"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Slider Bar
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
          width: root.outputMuted ? 0 : Math.max(0, Math.min(parent.width, parent.width * root.outputVolume))
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
          var v = Math.max(0, Math.min(1, mouse.x / width))
          root.setOutputVolume(v)
        }
        onPositionChanged: function(mouse) {
          if (pressed) {
            var v = Math.max(0, Math.min(1, mouse.x / width))
            root.setOutputVolume(v)
          }
        }
      }
    }
  }
}
