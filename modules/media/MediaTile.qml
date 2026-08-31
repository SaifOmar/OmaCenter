import QtQuick
import QtQuick.Effects
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

    if (playingPlayer) return playingPlayer
    if (root.stickyPlayer) {
      for (var j = 0; j < players.length; j++) {
        if (players[j] === root.stickyPlayer) return root.stickyPlayer
      }
    }
    return fallbackPlayer
  }

  onPlayerChanged: {
    if (player) stickyPlayer = player
  }

  readonly property bool hasMedia: root.player !== null
  readonly property string mediaTitle: player ? (player.trackTitle || "") : ""
  readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
  readonly property bool mediaPlaying: player ? player.isPlaying : false

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

  hasCursor: false
  radius: Style.space(14)
  color: mouseArea.containsMouse
    ? Util.alpha(panel ? panel.fg : Color.foreground, 0.12)
    : Util.alpha(panel ? panel.fg : Color.foreground, 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  clip: true

  Behavior on color { ColorAnimation { duration: 120 } }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.panel) root.panel.expandModule(root.moduleId, "Now Playing")
    }
  }

  // Sound output icon top right
  Rectangle {
    width: Style.space(22)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.1)
    z: 10

    Text {
      anchors.centerIn: parent
      text: "󰓃"
      color: root.panel ? root.panel.fg : Color.foreground
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function(e) {
        e.accepted = true
        if (root.panel) root.panel.expandModule(root.soundOutputModuleId, "Sound Output")
      }
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    anchors.topMargin: Style.space(10)
    spacing: Style.space(6)

    // 1. Album art top left
    Item {
      id: mediaArt
      width: Style.space(48)
      height: width

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
          radius: Style.space(8)
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
          visible: artImage.status !== Image.Ready

          Text {
            anchors.centerIn: parent
            text: "󰝚"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.icon
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
          radius: Style.space(8)
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
    }

    // 2. Song title and artist under art
    Column {
      width: parent.width
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: root.hasMedia ? root.mediaTitle : "Nothing Playing"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.hasMedia && root.mediaArtist !== ""
        text: root.mediaArtist
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // 3. Transport controls centered at bottom
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      Rectangle {
        width: Style.space(28)
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
          onClicked: function(e) {
            e.accepted = true
            root.mediaPrevious()
          }
        }
      }

      Rectangle {
        width: Style.space(28)
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
          onClicked: function(e) {
            e.accepted = true
            root.togglePlayPause()
          }
        }
      }

      Rectangle {
        width: Style.space(28)
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
          onClicked: function(e) {
            e.accepted = true
            root.mediaNext()
          }
        }
      }
    }
  }
}
