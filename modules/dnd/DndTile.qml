import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.dnd"

  property bool dndEnabled: false
  readonly property var notificationService: panel && panel.bar && panel.bar.shell
    ? panel.bar.shell.firstPartyServiceFor("omarchy.notifications")
    : null

  function toggleDnd() {
    // Optimistic UI state toggle for zero-delay feedback
    root.dndEnabled = !root.dndEnabled

    if (root.notificationService && typeof root.notificationService.setDoNotDisturb === "function") {
      root.notificationService.setDoNotDisturb(root.dndEnabled)
    } else {
      Quickshell.execDetached(["omarchy-toggle-notification-silencing"])
      refreshTimer.restart()
    }
  }

  function updateStatus(raw) {
    var txt = raw.trim()
    root.dndEnabled = txt === "true" || txt === "on" || txt === "1"
  }

  Process {
    id: statusProc
    command: ["sh", "-c", "omarchy-shell notifications dnd 2>/dev/null || echo false"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStatus(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (!statusProc.running) statusProc.running = true
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.notificationService && root.notificationService.doNotDisturb !== undefined) {
        root.dndEnabled = root.notificationService.doNotDisturb
      } else if (!statusProc.running) {
        statusProc.running = true
      }
    }
  }

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, (dndEnabled || mouseArea.containsMouse) ? 0.12 : 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  Behavior on color { ColorAnimation { duration: 120 } }
  implicitHeight: Style.space(58)

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) {
        root.toggleDnd()
      } else {
        if (root.panel) root.panel.summonPanel("omarchy.notifications")
      }
    }
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(10)

    Rectangle {
      width: Style.space(34)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.dndEnabled ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: root.dndEnabled ? "󰂛" : "󰂚"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      width: parent.width - Style.space(54)

      Text {
        text: "Do Not Disturb"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: root.dndEnabled ? "On" : "Off"
      color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
