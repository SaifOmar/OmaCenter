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

    implicitHeight: contentColumn.implicitHeight

    // ─── Sticky MPRIS State ─────────────────────────────────────

    property var stickyPlayer: null
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

    readonly property var player: {
        var players = root.mprisPlayers;
        var playingPlayer = null;
        var fallbackPlayer = null;

        for (var i = 0; i < players.length; i++) {
            var p = players[i];
            if (!p)
                continue;
            if (p.trackTitle || p.trackArtist) {
                if (!fallbackPlayer)
                    fallbackPlayer = p;
                if (p.isPlaying) {
                    playingPlayer = p;
                    break;
                }
            }
        }

        // User explicitly selected a player — always honor it
        if (root.stickyPlayer) {
            for (var j = 0; j < players.length; j++) {
                if (players[j] === root.stickyPlayer)
                    return root.stickyPlayer;
            }
        }

        // Auto-detect: show playing, else fallback
        if (playingPlayer)
            return playingPlayer;
        return fallbackPlayer;
    }

    onPlayerChanged: {
        if (player)
            stickyPlayer = player;
    }

    readonly property bool hasMedia: root.player !== null
    readonly property string mediaTitle: player ? (player.trackTitle || "Nothing Playing") : "Nothing Playing"
    readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
    readonly property string mediaSource: player ? (player.identity || player.appName || "Media Player") : ""
    readonly property bool mediaPlaying: player ? player.isPlaying : false
    readonly property real mediaPosition: player && player.position >= 0 ? player.position : 0
    readonly property real mediaDuration: player && player.length >= 0 ? player.length : 0

    // ─── Per-player stream volume ──────────────────────────────

    property string playerSinkInputId: ""
    property real playerStreamVolume: 0.5

    function findPlayerSinkInput(raw) {
        if (!raw || raw.length === 0 || !root.player)
            return;
        var lines = raw.split("\n");
        var currentId = "";
        var currentAppName = "";
        var playerName = root.player.identity || root.player.appName || "";

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();

            if (line.indexOf("Sink Input #") === 0) {
                if (currentId && currentAppName && currentAppName.toLowerCase() === playerName.toLowerCase()) {
                    root.playerSinkInputId = currentId;
                    return;
                }
                var idStr = line.replace("Sink Input #", "").trim();
                if (/^\d+$/.test(idStr)) {
                    currentId = idStr;
                } else {
                    currentId = "";
                }
                currentAppName = "";
            }

            var appMatch = line.match(/application\.name\s*=\s*"(.+)"/);
            if (appMatch) {
                currentAppName = appMatch[1];
            }

            var volMatch = line.match(/Volume:\s*front-left:\s*\d+\s*\/\s*(\d+)%/);
            if (volMatch && currentId && currentAppName && currentAppName.toLowerCase() === playerName.toLowerCase()) {
                root.playerStreamVolume = parseInt(volMatch[1]) / 100.0;
            }
        }

        if (currentId && currentAppName && currentAppName.toLowerCase() === playerName.toLowerCase()) {
            root.playerSinkInputId = currentId;
        }
    }

    function setPlayerStreamVolume(v) {
        if (!root.playerSinkInputId)
            return;
        var clamped = Math.max(0, Math.min(1, v));
        var pct = Math.round(clamped * 100);
        setStreamVolProc.command = ["pactl", "set-sink-input-volume", root.playerSinkInputId, pct + "%"];
        setStreamVolProc.running = true;
        root.playerStreamVolume = clamped;
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
            if (!findSinkInputProc.running)
                findSinkInputProc.running = true;
        }
    }

    // Force position updates — MPRIS position is not reactive
    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }

    function launchPlayerApp() {
        if (!root.player) return
        var appName = root.player.identity || root.player.desktopEntry || ""
        if (appName) {
            focusProc.command = ["omarchy-hyprland-focus-app", appName]
            focusProc.running = true
        }
    }

    Process {
        id: focusProc
    }

    // ─── Helpers ───────────────────────────────────────────────

    function togglePlayPause() {
        if (!root.player)
            return;
        if (root.player.canTogglePlaying)
            root.player.togglePlaying();
        else if (root.mediaPlaying && root.player.canPause)
            root.player.pause();
        else if (!root.mediaPlaying && root.player.canPlay)
            root.player.play();
    }

    function mediaPrevious() {
        if (root.player && root.player.canGoPrevious)
            root.player.previous();
    }

    function mediaNext() {
        if (root.player && root.player.canGoNext)
            root.player.next();
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0 || isNaN(seconds))
            return "0:00";
        var mins = Math.floor(seconds / 60);
        var secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    // Everything flows top-to-bottom, no bottom anchoring
    Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(14)

        // Player Switcher Bar — pill tabs with icons
        Row {
            width: parent.width
            spacing: Style.space(6)
            visible: root.mprisPlayers.length > 1
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: root.mprisPlayers
                delegate: Rectangle {
                    id: pillTab
                    required property var modelData
                    readonly property bool isSelected: root.player === modelData
                    property bool isHovered: false
                    property string iconPath: {
                        var de = modelData ? modelData.desktopEntry : ""
                        if (!de) return ""
                        var p = Quickshell.iconPath(de, true)
                        return (p && p.length > 0) ? p : ""
                    }

                    width: pillContent.implicitWidth + Style.space(20)
                    height: Style.space(30)
                    radius: height / 2
                    color: isSelected
                        ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.18)
                        : isHovered
                            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.10)
                            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.05)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: pillContent
                        anchors.centerIn: parent
                        spacing: Style.space(5)

                        Image {
                            width: Style.space(14)
                            height: width
                            fillMode: Image.PreserveAspectFit
                            source: pillTab.iconPath
                            visible: status === Image.Ready
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: pillTab.modelData ? (pillTab.modelData.identity || "Player") : "Player"
                            color: pillTab.isSelected
                                ? (root.panel ? root.panel.fg : Color.foreground)
                                : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.7)
                            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: pillTab.isSelected
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: pillTab.isHovered = true
                        onExited: pillTab.isHovered = false
                        onClicked: {
                            if (pillTab.modelData) {
                                // Toggle: clicking same source clears sticky (auto-detect)
                                if (root.stickyPlayer === pillTab.modelData)
                                    root.stickyPlayer = null;
                                else
                                    root.stickyPlayer = pillTab.modelData;
                            }
                        }
                    }
                }
            }
        }

        // 1. Album Art
        Item {
            id: bigArtContainer
            width: parent.width
            height: Style.space(200)
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

            MouseArea {
                anchors.fill: bigArtSource
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchPlayerApp()
            }
        }

        // 2. Track Info
        Column {
            width: parent.width
            spacing: Style.space(2)

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
        // Seek bar is slightly wider than volume (volume = 90% of seek width)
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
                    onClicked: function (mouse) {
                        if (root.player && root.player.canSeek && root.mediaDuration > 0) {
                            var ratio = Math.max(0, Math.min(1, mouse.x / width));
                            root.player.position = ratio * root.mediaDuration;
                        }
                    }
                    onPositionChanged: function (mouse) {
                        if (pressed && root.player && root.player.canSeek && root.mediaDuration > 0) {
                            var ratio = Math.max(0, Math.min(1, mouse.x / width));
                            root.player.position = ratio * root.mediaDuration;
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

        // 4. Transport Controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(22)

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

        // 5. Volume strip: [low icon] [slider] [high icon]
        // Compact: 80% width of content, thin bar
        Row {
            width: parent.width * 0.9
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Text {
                text: ""
                color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.5)
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: parent.width - Style.space(28)
                height: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: Style.space(5)
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
                    onClicked: function (mouse) {
                        var v = Math.max(0, Math.min(1, mouse.x / width));
                        root.setPlayerStreamVolume(v);
                    }
                    onPositionChanged: function (mouse) {
                        if (pressed) {
                            var v = Math.max(0, Math.min(1, mouse.x / width));
                            root.setPlayerStreamVolume(v);
                        }
                    }
                }
            }

            Text {
                text: ""
                color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.8)
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
