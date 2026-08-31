import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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

  property string currentSinkInputId: ""
  property string currentSinkName: ""

  // Device list from pactl: [{name, description}]
  property var devices: []

  function parseSinkInputs(raw) {
    if (!raw || raw.length === 0) return

    var lines = raw.split("\n")
    var id = ""
    var appName = ""
    var sinkName = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      if (line.indexOf("Sink Input #") === 0) {
        if (id && appName && root.playerName &&
            appName.toLowerCase() === root.playerName.toLowerCase()) {
          root.currentSinkInputId = id
          root.currentSinkName = sinkName
          return
        }
        var idStr = line.replace("Sink Input #", "").trim()
        id = /^\d+$/.test(idStr) ? idStr : ""
        appName = ""
        sinkName = ""
      }

      var nameMatch = line.match(/^Name:\s*(.+)/)
      if (nameMatch && id) {
        sinkName = nameMatch[1].trim()
      }

      var appMatch = line.match(/application\.name\s*=\s*"(.+)"/)
      if (appMatch) {
        appName = appMatch[1]
      }
    }

    if (id && appName && root.playerName &&
        appName.toLowerCase() === root.playerName.toLowerCase()) {
      root.currentSinkInputId = id
      root.currentSinkName = sinkName
    }
  }

  function parseSinksList(raw) {
    if (!raw || raw.length === 0) return
    var lines = raw.split("\n")
    var list = []
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].trim().split(/\s{2,}/)
      if (parts.length >= 2) {
        list.push({ name: parts[0], description: parts[1] || parts[0] })
      }
    }
    root.devices = list
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
    id: listSinksProc
    command: ["pactl", "list", "sinks", "short"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSinksList(text)
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
      if (!listSinksProc.running) listSinksProc.running = true
    }
  }

  Component.onCompleted: {
    listSinksProc.running = true
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
      visible: root.activePlayer !== null && root.devices.length > 0

      Text {
        text: "OUTPUT DEVICES"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.devices
        delegate: Rectangle {
          id: deviceRow
          required property var modelData
          required property int index
          readonly property bool isSelected: root.currentSinkName !== "" && modelData.name === root.currentSinkName
          property bool isHovered: false

          width: parent.width
          height: Style.space(52)
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
