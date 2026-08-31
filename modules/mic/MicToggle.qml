import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.mic"

  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool micMuted: source && source.audio ? source.audio.muted : true
  readonly property string micDeviceName: {
    if (!source) return "Mic"
    var p = source.properties || {}
    return p["device.description"] || p["node.description"] || source.description || source.name || "Mic"
  }
  readonly property string micStatus: root.micMuted ? "Muted" : root.micDeviceName

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, (!micMuted || mouseArea.containsMouse) ? 0.12 : 0.055)
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
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, !root.micMuted ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: !root.micMuted ? "󰍬" : "󰍭"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.micStatus
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
        if (root.source && root.source.audio) {
          root.source.audio.muted = !root.source.audio.muted
        }
      } else {
        if (root.panel) root.panel.summonPanel("omarchy.microphone")
      }
    }
  }
}
