import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.media"

  implicitHeight: Style.space(520)

  // ─── Sticky MPRIS State ─────────────────────────────────────

  property var stickyPlayer: null
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  readonly property var player: {
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

    // 1. If any player is actively playing, prefer it
    if (playingPlayer) return playingPlayer

    // 2. If paused, stay on sticky player if it's still available
    if (root.stickyPlayer) {
      for (var j = 0; j < players.length; j++) {
        if (players[j] === root.stickyPlayer) return root.stickyPlayer
      }
    }

    // 3. Otherwise fallback to first available with metadata
    return fallbackPlayer
  }

  onPlayerChanged: {
    if (player) stickyPlayer = player
  }

  readonly property bool hasMedia: root.player !== null
  readonly property string mediaTitle: player ? (player.trackTitle || "Nothing Playing") : "Nothing Playing"
  readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
  readonly property string mediaSource: player ? (player.identity || player.appName || "Media Player") : ""
  readonly property bool mediaPlaying: player ? player.isPlaying : false
  readonly property real mediaPosition: player && player.position >= 0 ? player.position : 0
  readonly property real mediaDuration: player && player.length >= 0 ? player.length : 0

  // ─── Audio Pipewire Sinks ──────────────────────────────────

  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property real sinkVolume: defaultSink && defaultSink.audio ? defaultSink.audio.volume : 0
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

  // ─── Per-player stream volume ──────────────────────────────

  property string playerSinkInputId: ""
  property real playerStreamVolume: 0.5

  function findPlayerSinkInput(raw) {
    if (!raw || raw.length === 0 || !root.player) return

    var lines = raw.split("\n")
    var currentId = ""
    var currentAppName = ""
    var playerName = root.player.identity || root.player.appName || ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()

      if (line.indexOf("Sink Input #") === 0) {
        if (currentId && currentAppName &&
            currentAppName.toLowerCase() === playerName.toLowerCase()) {
          root.playerSinkInputId = currentId
          return
        }
        var idStr = line.replace("Sink Input #", "").trim()
        if (/^\d+$/.test(idStr)) {
          currentId = idStr
        } else {
          currentId = ""
        }
        currentAppName = ""
      }

      var appMatch = line.match(/application\.name\s*=\s*"(.+)"/)
      if (appMatch) {
        currentAppName = appMatch[1]
      }

      // Volume line for this sink-input
      var volMatch = line.match(/Volume:\s*front-left:\s*\d+\s*\/\s*(\d+)%/)
      if (volMatch && currentId && currentAppName &&
          currentAppName.toLowerCase() === playerName.toLowerCase()) {
        root.playerStreamVolume = parseInt(volMatch[1]) / 100.0
      }
    }

    if (currentId && currentAppName &&
        currentAppName.toLowerCase() === playerName.toLowerCase()) {
      root.playerSinkInputId = currentId
    }
  }

  function setPlayerStreamVolume(v) {
    if (!root.playerSinkInputId) return
    var clamped = Math.max(0, Math.min(1, v))
    var pct = Math.round(clamped * 100)
    setStreamVolProc.command = ["pactl", "set-sink-input-volume", root.playerSinkInputId, pct + "%"]
    setStreamVolProc.running = true
    root.playerStreamVolume = clamped
  }

  Process {
    id: findSinkInputProc
    command: ["pactl", "list", "sink-inputs"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.findPlayerSinkInput(text)
    }
  }

  Process {
    id: setStreamVolProc
  }

  Timer {
    interval: 2000
    running: root.player !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!findSinkInputProc.running) findSinkInputProc.running = true
    }
  }

  // ─── Helpers ───────────────────────────────────────────────

  function togglePlayPause() {
    if (!root.player) return
    if (root.player.canTogglePlaying) root.player.togglePlaying()
    else if (root.mediaPlaying && root.player.canPause) root.player.pause()
    else if (!root.mediaPlaying && root.player.canPlay) root.player.play()
  }

  function mediaPrevious() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  function mediaNext() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  function formatTime(seconds) {
    if (!seconds || seconds < 0 || isNaN(seconds)) return "0:00"
    var mins = Math.floor(seconds / 60)
    var secs = Math.floor(seconds % 60)
    return mins + ":" + (secs < 10 ? "0" : "") + secs
  }

  // Top content (flows from top)
  Column {
    id: mediaContent
    width: parent.width
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(12)

    // Player Switcher Bar (visible if multiple media sources exist)
    Row {
      width: parent.width
      spacing: Style.space(6)
      visible: root.mprisPlayers.length > 1
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: root.mprisPlayers
        delegate: Rectangle {
          required property var modelData
          readonly property bool isSelected: root.player === modelData
          width: Math.min(Style.space(100), (mediaContent.width - (root.mprisPlayers.length - 1) * Style.space(6)) / root.mprisPlayers.length)
          height: Style.space(26)
          radius: Style.space(6)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.08)

          Text {
            anchors.centerIn: parent
            text: modelData ? (modelData.identity || modelData.appName || "Player") : "Player"
            color: isSelected
              ? (root.panel ? root.panel.fg : Color.foreground)
              : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.7)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: isSelected
            elide: Text.ElideRight
            width: parent.width - Style.space(8)
            horizontalAlignment: Text.AlignHCenter
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData) root.stickyPlayer = modelData
            }
          }
        }
      }
    }

    // 1. Album Art (fixed container, image fills it)
    Item {
      id: bigArtContainer
      width: parent.width
      height: Style.space(180)
      anchors.horizontalCenter: parent.horizontalCenter

      Item {
        id: bigArtSource
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Image {
          id: bigArtImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
        }

        Rectangle {
          anchors.fill: parent
          radius: Style.space(14)
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
          visible: bigArtImage.status !== Image.Ready

          Text {
            anchors.centerIn: parent
            text: "󰝚"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.space(42)
          }
        }
      }

      Item {
        id: bigArtMask
        anchors.fill: bigArtSource
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
          anchors.fill: parent
          radius: Style.space(14)
          color: "white"
        }
      }

      MultiEffect {
        anchors.fill: bigArtSource
        source: bigArtSource
        maskEnabled: true
        maskSource: bigArtMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    // 2. Track Info: Title, Artist, Source
    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.mediaTitle
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        visible: root.mediaArtist !== ""
        text: root.mediaArtist
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.75)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        visible: root.mediaSource !== ""
        text: root.mediaSource
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.45)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }

    // 3. Seekable Progress Bar with timers on both sides
    Column {
      width: parent.width
      height: Style.space(30)
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: seekLeft
          text: root.formatTime(root.mediaPosition)
          color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          id: seekTrack
          width: parent.width - seekLeft.implicitWidth - seekRight.implicitWidth - parent.spacing * 2
          height: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

            Rectangle {
              width: root.mediaDuration > 0 ? Math.max(0, Math.min(parent.width, parent.width * (root.mediaPosition / root.mediaDuration))) : 0
              height: parent.height
              radius: height / 2
              color: root.panel ? root.panel.fg : Color.foreground
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              if (root.player && root.player.canSeek && root.mediaDuration > 0) {
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                root.player.position = ratio * root.mediaDuration
              }
            }
            onPositionChanged: function(mouse) {
              if (pressed && root.player && root.player.canSeek && root.mediaDuration > 0) {
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                root.player.position = ratio * root.mediaDuration
              }
            }
          }
        }

        Text {
          id: seekRight
          text: root.formatTime(root.mediaDuration)
          color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  // Bottom content (anchored to bottom, stays in place)
  Column {
    width: parent.width
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(12)

    // Transport Controls
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(18)

      Rectangle {
        width: Style.space(40)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

        Text {
          anchors.centerIn: parent
          text: "󰒮"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.mediaPrevious()
        }
      }

      Rectangle {
        width: Style.space(40)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

        Text {
          anchors.centerIn: parent
          text: root.mediaPlaying ? "󰏤" : "󰐊"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePlayPause()
        }
      }

      Rectangle {
        width: Style.space(40)
        height: width
        radius: width / 2
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)

        Text {
          anchors.centerIn: parent
          text: "󰒭"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.mediaNext()
        }
      }
    }

    // Volume Level Control (per-player stream)
    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: "STREAM VOLUME"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "󰕾"
          color: root.panel ? root.panel.fg : Color.foreground
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
          anchors.verticalCenter: parent.verticalCenter
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
              width: Math.max(0, Math.min(parent.width, parent.width * root.playerStreamVolume))
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
              root.setPlayerStreamVolume(v)
            }
            onPositionChanged: function(mouse) {
              if (pressed) {
                var v = Math.max(0, Math.min(1, mouse.x / width))
                root.setPlayerStreamVolume(v)
              }
            }
          }
        }

        Text {
          text: Math.round(root.playerStreamVolume * 100) + "%"
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

    // 6. Output Source Selector (Audio Sinks)
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.audioSinks.length > 0

      Text {
        text: "OUTPUT DEVICE"
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
          height: Style.space(36)
          radius: Style.space(8)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.08)
            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.03)

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
