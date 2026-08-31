import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.volume"

  implicitHeight: contentColumn.implicitHeight

  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property bool outputMuted: defaultSink && defaultSink.audio ? defaultSink.audio.muted : false
  readonly property real outputVolume: defaultSink && defaultSink.audio ? defaultSink.audio.volume : 0
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var audioSinks: {
    var list = []
    var nodes = root.pipewireNodes
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isSink && !node.isStream) {
        list.push(node)
      }
    }
    return list
  }

  function setOutputVolume(v) {
    if (!root.defaultSink || !root.defaultSink.audio) return
    root.defaultSink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (root.defaultSink && root.defaultSink.audio) {
      root.defaultSink.audio.muted = !root.defaultSink.audio.muted
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.space(12)

    // Header
    Row {
      width: parent.width
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(28)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

        Text {
          anchors.centerIn: parent
          text: root.outputMuted ? "󰝟" : "󰕾"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          text: "Sound Output"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: root.defaultSink ? (root.defaultSink.description || root.defaultSink.name || "Unknown") : "No device"
          color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Volume Control
    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: "VOLUME"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(24)
          height: width
          radius: width / 2
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)
          anchors.verticalCenter: parent.verticalCenter

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
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()
          }
        }

        Item {
          id: volumeTrack
          width: parent.width - Style.space(70)
          height: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Style.space(8)
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

        Text {
          text: root.outputMuted ? "Muted" : Math.round(root.outputVolume * 100) + "%"
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.7)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(32)
          horizontalAlignment: Text.AlignRight
        }
      }
    }

    // Output Devices
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.audioSinks.length > 0

      Text {
        text: "OUTPUT DEVICES"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.audioSinks
        delegate: Rectangle {
          required property var modelData
          readonly property bool isSelected: root.defaultSink && root.defaultSink === modelData
          width: parent.width
          height: Style.space(40)
          radius: Style.space(8)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.05)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: isSelected ? "󰓃" : "󰋋"
              color: isSelected
                ? (root.panel ? root.panel.fg : Color.foreground)
                : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.6)
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: modelData.description || modelData.name || "Audio Device"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: isSelected
              elide: Text.ElideRight
              width: parent.width - Style.space(40)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Pipewire.preferredDefaultAudioSink = modelData
            }
          }
        }
      }
    }
  }
}
