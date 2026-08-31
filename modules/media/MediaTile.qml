import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.media"
  readonly property string soundOutputModuleId: "so.omacenter.soundoutput"

  // ─── Sticky MPRIS State ─────────────────────────────────────

  property var stickyPlayer: null
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  property var lastShownPlayer: null

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

    // Something playing — show that
    if (playingPlayer) {
      root.lastShownPlayer = playingPlayer
      return playingPlayer
    }

    // Nothing playing — stay on the last shown player if it has a track
    if (root.lastShownPlayer) {
      for (var j = 0; j < players.length; j++) {
        if (players[j] === root.lastShownPlayer && (root.lastShownPlayer.trackTitle || root.lastShownPlayer.trackArtist))
          return root.lastShownPlayer
      }
    }

    return fallbackPlayer
  }

  onPlayerChanged: {
    // Don't auto-set sticky — tile always shows playing player
  }

  readonly property bool hasMedia: root.player !== null
  readonly property string mediaTitle: player ? (player.trackTitle || "") : ""
  readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
  readonly property bool mediaPlaying: player ? player.isPlaying : false
  readonly property real mediaPosition: player && player.position >= 0 ? player.position : 0
  readonly property real mediaDuration: player && player.length >= 0 ? player.length : 0

  // ─── Transport Helpers ─────────────────────────────────────

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

  // Force position updates — MPRIS position is not reactive
  Timer {
    interval: 1000
    running: root.player !== null && root.player.isPlaying
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  hasCursor: false
  radius: Style.space(14)
  color: mouseArea.containsMouse
    ? Util.alpha(panel ? panel.fg : Color.foreground, 0.12)
    : Util.alpha(panel ? panel.fg : Color.foreground, 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  clip: true

  Behavior on color { ColorAnimation { duration: 120 } }

  // ─── Art Background (fills entire tile) ─────────────────────

  Item {
    id: artContainer
    anchors.fill: parent

    Item {
      id: artSource
      anchors.fill: parent
      visible: false
      layer.enabled: true
      layer.smooth: true

      Image {
        id: artImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
      }

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
        visible: artImage.status !== Image.Ready

        Text {
          anchors.centerIn: parent
          text: "󰝚"
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.3)
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.space(36)
        }
      }
    }

    Item {
      id: artMask
      anchors.fill: artSource
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
      anchors.fill: artSource
      source: artSource
      maskEnabled: true
      maskSource: artMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    // Horizontal dark gradient for text readability
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.25) }
      }
      radius: Style.space(14)
    }
  }

  // ─── Click → Open Inner Panel (background, defined first) ───

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    z: 0
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.panel) root.panel.expandModule(root.moduleId, "Now Playing")
    }
  }

  // ─── Track Info (top-left overlaid) ─────────────────────────

  Column {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    width: parent.width - Style.space(50)
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.hasMedia ? root.mediaTitle : "Nothing Playing"
      color: "white"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: root.hasMedia && root.mediaArtist !== ""
      text: root.mediaArtist
      color: "#cccccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // ─── Sound Output Icon (top-right) ──────────────────────────

  Rectangle {
    width: Style.space(22)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    color: Qt.rgba(0, 0, 0, 0.3)
    z: 10

    Text {
      anchors.centerIn: parent
      text: "󰓃"
      color: "white"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function(e) {
        e.accepted = true
        if (root.panel) {
          root.panel.activeMprisPlayer = root.player
          root.panel.expandModule(root.soundOutputModuleId, "Sound Output")
        }
      }
    }
  }

  // ─── Seek Bar + Wave (bottom area, above transport) ─────────

  Item {
    id: seekContainer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: transportRow.top
    anchors.bottomMargin: Style.space(2)
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    height: seekCol.implicitHeight
    visible: root.hasMedia && root.mediaDuration > 0

    Column {
      id: seekCol
      width: parent.width
      spacing: Style.space(1)

      // Progress bar with wave
      Item {
        width: parent.width
        height: Style.space(6)

        Rectangle {
          width: parent.width
          height: 2
          radius: 1
          color: "#22ffffff"
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            width: root.mediaDuration > 0 ? Math.max(0, Math.min(parent.width, parent.width * (root.mediaPosition / root.mediaDuration))) : 0
            height: parent.height
            radius: 1
            color: "#bbffffff"
          }
        }

        // Wave animation — sits above the bar
        Canvas {
          id: progressWave
          anchors.left: parent.left
          width: root.mediaDuration > 0 ? Math.max(0, Math.min(parent.width, parent.width * (root.mediaPosition / root.mediaDuration))) : 0
          height: Style.space(6)
          y: -Style.space(5)
          clip: true
          antialiasing: true
          opacity: 0.35
          z: 1
          visible: root.mediaPlaying
          property real phase: 0

          NumberAnimation on phase {
            running: root.mediaPlaying
            from: 0
            to: Math.PI * 2
            duration: 1700
            loops: Animation.Infinite
          }

          onPhaseChanged: requestPaint()

          onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)

            function wave(amplitude, length, offset, color) {
              context.beginPath()
              context.moveTo(0, height)
              for (var x = 0; x <= width; x += 2) {
                var y = height / 2 + Math.sin((x / length) * Math.PI * 2 + phase + offset) * amplitude
                context.lineTo(x, y)
              }
              context.lineTo(width, height)
              context.closePath()
              var fade = context.createLinearGradient(0, 0, width, 0)
              fade.addColorStop(0, "rgba(255, 255, 255, 0)")
              fade.addColorStop(0.14, color)
              fade.addColorStop(0.86, color)
              fade.addColorStop(1, "rgba(255, 255, 255, 0)")
              context.fillStyle = fade
              context.fill()
            }

            wave(height * 0.38, Math.max(18, width * 0.7), 0, "rgba(255, 255, 255, 0.8)")
            wave(height * 0.28, Math.max(14, width * 0.45), Math.PI, "rgba(255, 255, 255, 0.45)")
          }
        }

        // Seek interaction — on top of everything
        MouseArea {
          anchors.fill: parent
          anchors.topMargin: -Style.space(4)
          anchors.bottomMargin: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          z: 10
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

      // Time labels
      Row {
        width: parent.width
        Text {
          text: root.formatTime(root.mediaPosition)
          color: "#99ffffff"
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption - 1
        }

        Item { width: parent.width - elapsedText2.implicitWidth - totalText2.implicitWidth; height: 1 }

        Text {
          id: totalText2
          text: root.formatTime(root.mediaDuration)
          color: "#99ffffff"
          font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption - 1
        }
      }

      Text {
        id: elapsedText2
        text: root.formatTime(root.mediaPosition)
        color: "#99ffffff"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption - 1
        visible: false
      }
    }
  }

  // ─── Transport Controls (bottom-center overlaid) ────────────

  Row {
    id: transportRow
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(8)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(12)

    Rectangle {
      width: Style.space(26)
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.3)

      Text {
        anchors.centerIn: parent
        text: "󰒮"
        color: "white"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(e) {
          e.accepted = true
          root.mediaPrevious()
        }
      }
    }

    Rectangle {
      width: Style.space(26)
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.4)

      Text {
        anchors.centerIn: parent
        text: root.mediaPlaying ? "󰏤" : "󰐊"
        color: "white"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(e) {
          e.accepted = true
          root.togglePlayPause()
        }
      }
    }

    Rectangle {
      width: Style.space(26)
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.3)

      Text {
        anchors.centerIn: parent
        text: "󰒭"
        color: "white"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(e) {
          e.accepted = true
          root.mediaNext()
        }
      }
    }
  }
}
