import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.soundoutput"

  implicitHeight: contentColumn.implicitHeight

  readonly property var activePlayer: panel ? panel.activeMprisPlayer : null
  readonly property string playerName: activePlayer ? (activePlayer.identity || activePlayer.appName || "Unknown") : ""
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

  property string currentSinkInputId: ""
  property string currentSinkId: ""

  function parseSinkInputs(raw) {
    if (!raw || raw.length === 0) return

    var lines = raw.split("\n")
    var currentId = ""
    var currentAppName = ""
    var currentSinkId = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      if (line.indexOf("Sink Input #") === 0) {
        if (currentId && currentAppName && root.playerName &&
            currentAppName.toLowerCase() === root.playerName.toLowerCase()) {
          root.currentSinkInputId = currentId
          root.currentSinkId = currentSinkId
          return
        }
        var idStr = line.replace("Sink Input #", "").trim()
        if (/^\d+$/.test(idStr)) {
          currentId = idStr
        } else {
          currentId = ""
        }
        currentAppName = ""
        currentSinkId = ""
      }

      var sinkMatch = line.match(/^Sink:\s*(\d+)/)
      if (sinkMatch) {
        currentSinkId = sinkMatch[1]
      }

      var appMatch = line.match(/application\.name\s*=\s*"(.+)"/)
      if (appMatch) {
        currentAppName = appMatch[1]
      }
    }

    if (currentId && currentAppName && root.playerName &&
        currentAppName.toLowerCase() === root.playerName.toLowerCase()) {
      root.currentSinkInputId = currentId
      root.currentSinkId = currentSinkId
    }
  }

  function routeToSink(sinkName) {
    if (!sinkName || !root.currentSinkInputId) return
    moveSinkInputProc.command = ["pactl", "move-sink-input", root.currentSinkInputId, sinkName]
    moveSinkInputProc.running = true
  }

  Process {
    id: listSinkInputsProc
    command: ["pactl", "list", "sink-inputs"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSinkInputs(text)
    }
  }

  Process {
    id: moveSinkInputProc
    stdout: StdioCollector {
      waitForEnd: true
      onFinished: listSinkInputsProc.running = true
    }
  }

  Timer {
    interval: 800
    running: root.activePlayer !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!listSinkInputsProc.running) listSinkInputsProc.running = true
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.space(12)

    Column {
      width: parent.width
      visible: !root.activePlayer
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: "No active media player"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        text: "Play some media to route its audio"
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.5)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      visible: root.activePlayer !== null

      Rectangle {
        width: Style.space(28)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

        Text {
          anchors.centerIn: parent
          text: "󰓃"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          text: "Route Audio"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: root.playerName
          color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.activePlayer !== null && root.audioSinks.length > 0

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
          id: deviceRow
          required property var modelData
          readonly property bool isSelected: root.currentSinkId !== "" &&
            String(modelData.properties ? modelData.properties["object.serial"] : "") === root.currentSinkId
          property bool isHovered: false

          width: parent.width
          height: Style.space(60)
          radius: Style.space(10)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.18)
            : isHovered
              ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.08)
              : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.03)

          Behavior on color {
            ColorAnimation { duration: 120 }
          }

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            Text {
              text: deviceRow.isSelected ? "󰓃" : "󰋋"
              color: deviceRow.isSelected
                ? (root.panel ? root.panel.fg : Color.foreground)
                : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.6)
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: modelData.description || modelData.name || "Audio Device"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: deviceRow.isSelected
              elide: Text.ElideRight
              width: parent.width - Style.space(50)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "✓"
              visible: deviceRow.isSelected
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: deviceRow.isHovered = true
            onExited: deviceRow.isHovered = false
            onClicked: root.routeToSink(modelData.name)
          }
        }
      }
    }
  }
}
