import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.soundoutput"

  implicitHeight: contentColumn.implicitHeight

  // Auto-detect active MPRIS player (fallback when panel.activeMprisPlayer is not set)
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  readonly property var autoPlayer: {
    var players = root.mprisPlayers
    var playingPlayer = null
    var fallbackPlayer = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      if (p.trackTitle || p.trackArtist) {
        if (!fallbackPlayer) fallbackPlayer = p
        if (p.isPlaying) {
          playingPlayer = p
          break
        }
      }
    }

    if (playingPlayer) return playingPlayer
    return fallbackPlayer
  }

  readonly property var activePlayer: (panel ? panel.activeMprisPlayer : null) || root.autoPlayer
  readonly property string playerName: activePlayer ? (activePlayer.identity || activePlayer.appName || "Unknown") : ""

  property string currentSinkInputId: ""
  property string currentSinkName: ""

  // Device list from pactl: [{id, name, description, volume, mute}]
  property var devices: []
  // Current sink volume/mute (from selected device)
  property real currentVolume: 0
  property bool currentMuted: false

  function deviceNameForId(id) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].id === id) return devices[i].name
    }
    return ""
  }

  function parseSinkInputs(raw) {
    if (!raw || raw.length === 0) return

    var lines = raw.split("\n")
    var id = ""
    var appName = ""
    var sinkId = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      if (line.indexOf("Sink Input #") === 0) {
        if (id && appName && root.playerName &&
            appName.toLowerCase() === root.playerName.toLowerCase()) {
          root.currentSinkInputId = id
          root.currentSinkName = root.deviceNameForId(sinkId)
          return
        }
        var idStr = line.replace("Sink Input #", "").trim()
        id = /^\d+$/.test(idStr) ? idStr : ""
        appName = ""
        sinkId = ""
      }

      var sinkMatch = line.match(/^Sink:\s*(\d+)/)
      if (sinkMatch && id) {
        sinkId = sinkMatch[1]
      }

      var appMatch = line.match(/application\.name\s*=\s*"(.+)"/)
      if (appMatch) {
        appName = appMatch[1]
      }
    }

    if (id && appName && root.playerName &&
        appName.toLowerCase() === root.playerName.toLowerCase()) {
      root.currentSinkInputId = id
      root.currentSinkName = root.deviceNameForId(sinkId)
    }
  }

  function parseSinksList(raw) {
    if (!raw || raw.length === 0) return
    var lines = raw.split("\n")
    var list = []
    var currentId = ""
    var currentName = ""
    var currentDesc = ""
    var currentVol = 1.0
    var currentMute = false

    function flush() {
      if (currentId && currentName) {
        list.push({ id: currentId, name: currentName, description: currentDesc || currentName, volume: currentVol, mute: currentMute })
      }
      currentId = ""
      currentName = ""
      currentDesc = ""
      currentVol = 1.0
      currentMute = false
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      var sinkMatch = line.match(/^Sink #(\d+)/)
      if (sinkMatch) {
        flush()
        currentId = sinkMatch[1]
        continue
      }

      var nameMatch = line.match(/^Name:\s*(.+)/)
      if (nameMatch && currentId) {
        currentName = nameMatch[1].trim()
        continue
      }

      var descMatch = line.match(/^Description:\s*(.+)/)
      if (descMatch && currentId) {
        currentDesc = descMatch[1].trim()
        continue
      }

      var volMatch = line.match(/front-left:\s+(\d+)\s+\/\s+(\d+)%/)
      if (volMatch && currentId) {
        currentVol = parseInt(volMatch[2]) / 100
        continue
      }

      var muteMatch = line.match(/^Mute:\s*(yes|no)/)
      if (muteMatch && currentId) {
        currentMute = muteMatch[1] === "yes"
        continue
      }
    }
    flush()

    root.devices = list

    // Update current sink volume from selected device
    for (var j = 0; j < list.length; j++) {
      if (list[j].name === root.currentSinkName) {
        root.currentVolume = list[j].volume
        root.currentMuted = list[j].mute
        return
      }
    }
    // Fallback: use first device
    if (list.length > 0) {
      root.currentVolume = list[0].volume
      root.currentMuted = list[0].mute
    }
  }

  function routeToSink(sinkName) {
    if (!sinkName || !root.currentSinkInputId) return
    root.currentSinkName = sinkName
    moveSinkInputProc.command = ["pactl", "move-sink-input", root.currentSinkInputId, sinkName]
    moveSinkInputProc.running = true
  }

  function setSinkVolume(vol) {
    if (!root.currentSinkName) return
    var pct = Math.round(Math.max(0, Math.min(1, vol)) * 100)
    setVolProc.command = ["pactl", "set-sink-volume", root.currentSinkName, pct + "%"]
    setVolProc.running = true
    root.currentVolume = vol
  }

  function toggleSinkMute() {
    if (!root.currentSinkName) return
    setMuteProc.command = ["pactl", "set-sink-mute", root.currentSinkName, "toggle"]
    setMuteProc.running = true
    root.currentMuted = !root.currentMuted
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
    command: ["pactl", "list", "sinks"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSinksList(text)
    }
  }

  Process {
    id: moveSinkInputProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: setVolProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: setMuteProc
    stdout: StdioCollector { waitForEnd: true }
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

    // Header
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
          text: root.currentMuted ? "󰝟" : "󰕾"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

    // Volume Control
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.activePlayer !== null

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
            text: root.currentMuted ? "󰝟" : "󰕾"
            color: root.currentMuted
              ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.4)
              : (root.panel ? root.panel.fg : Color.foreground)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleSinkMute()
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
              width: root.currentMuted ? 0 : Math.max(0, Math.min(parent.width, parent.width * root.currentVolume))
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
              root.setSinkVolume(v)
            }
            onPositionChanged: function(mouse) {
              if (pressed) {
                var v = Math.max(0, Math.min(1, mouse.x / width))
                root.setSinkVolume(v)
              }
            }
          }
        }

        Text {
          text: root.currentMuted ? "Muted" : Math.round(root.currentVolume * 100) + "%"
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
            onClicked: {
              root.routeToSink(modelData.name)
              root.currentVolume = modelData.volume
              root.currentMuted = modelData.mute
            }
          }
        }
      }
    }
  }
}
