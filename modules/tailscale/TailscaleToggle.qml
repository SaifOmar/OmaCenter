import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.tailscale"

  property string tailscaleState: "Off"
  property string tailscaleHost: ""

  readonly property bool active: tailscaleState === "On"
  readonly property string tailscaleStatus: {
    if (root.tailscaleState === "On") return root.tailscaleHost !== "" ? root.tailscaleHost : "On"
    if (root.tailscaleState === "Login") return "Login"
    return "Off"
  }

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, (active || mouseArea.containsMouse) ? 0.12 : 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  Behavior on color { ColorAnimation { duration: 120 } }

  function updateTailscale(raw) {
    try {
      var d = JSON.parse(raw)
      var state = String(d.BackendState || "")
      root.tailscaleState = state === "Running" ? "On" : (state === "Starting" ? "Starting" : (state === "NeedsLogin" ? "Login" : "Off"))
      var self = d.Self
      root.tailscaleHost = self && self.DNSName ? String(self.DNSName).split(".")[0] : ""
    } catch (e) {
      root.tailscaleState = "Off"
      root.tailscaleHost = ""
    }
  }

  Process {
    id: tailscaleProc
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateTailscale(text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!tailscaleProc.running) tailscaleProc.running = true
    }
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: {
      if (!tailscaleProc.running) tailscaleProc.running = true
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(3)

    Rectangle {
      width: Style.space(34)
      height: width
      radius: width / 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.active ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: "󰖂"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.tailscaleStatus
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
        // Optimistic UI state toggle for zero-delay feedback
        var wasActive = root.tailscaleState === "On"
        root.tailscaleState = wasActive ? "Off" : "On"

        if (wasActive) {
          Quickshell.execDetached(["tailscale", "down"])
        } else {
          Quickshell.execDetached(["tailscale", "up"])
        }
        delayedRefresh.start()
      } else {
        if (root.panel) root.panel.summonPanel("omarchy.tailscale")
      }
    }
  }
}
