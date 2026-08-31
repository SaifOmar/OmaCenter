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

  // Parse pactl list sink-inputs output to find sink-input for our player
  function parseSinkInputs(raw) {
    if (!raw || raw.length === 0) return

    var lines = raw.split("\n")
    var currentId = ""
    var currentAppName = ""
    var currentSinkId = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      // New sink-input block
      if (line.indexOf("Sink Input #") === 0) {
        // Check previous entry
        if (currentId && currentAppName && root.playerName &&
            currentAppName.toLowerCase() === root.playerName.toLowerCase()) {
          root.currentSinkInputId = currentId
          root.currentSinkId = currentSinkId
          return
        }
        var idStr = line.replace("Sink Input #", "").trim()
        // Validate: only numeric IDs are safe
        if (/^\d+$/.test(idStr)) {
          currentId = idStr
        } else {
          currentId = ""
        }
        currentAppName = ""
        currentSinkId = ""
      }

      // Sink ID line (e.g., "Sink: 47")
      var sinkMatch = line.match(/^Sink:\s*(\d+)/)
      if (sinkMatch) {
        currentSinkId = sinkMatch[1]
      }

      // Application name property
      var appMatch = line.match(/application\.name\s*=\s*"(.+)"/)
      if (appMatch) {
        currentAppName = appMatch[1]
      }
    }

    // Check last entry
    if (currentId && currentAppName && root.playerName &&
        currentAppName.toLowerCase() === root.playerName.toLowerCase()) {
      root.currentSinkInputId = currentId
      root.currentSinkId = currentSinkId
    }
  }

  // Sanitize: only allow alphanumeric, dots, hyphens, underscores in sink names
  function sanitizeSinkName(name) {
    if (!name) return ""
    return name.replace(/[^a-zA-Z0-9._\-]/g, "")
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
    property string targetSink: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Refresh after move
        listSinkInputsProc.running = true
      }
    }
  }

  Timer {
    interval: 2000
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

    // No player message
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

    // Header (when player is active)
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

    // Output Devices
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
          required property var modelData
          readonly property bool isSelected: root.currentSinkId !== "" &&
            String(modelData.properties ? modelData.properties["object.serial"] : "") === root.currentSinkId
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
              var sinkName = root.sanitizeSinkName(modelData.name)
              if (sinkName && root.currentSinkInputId) {
                moveSinkInputProc.command = ["pactl", "move-sink-input", root.currentSinkInputId, sinkName]
                moveSinkInputProc.running = true
              }
            }
          }
        }
      }
    }
  }
}
