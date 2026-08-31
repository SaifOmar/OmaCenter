import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.theme"

  property string currentTheme: "Omarchy"

  function updateTheme(raw) {
    var t = raw.trim()
    if (t) root.currentTheme = t
  }

  // Background process to check active theme name
  Process {
    id: themeProc
    command: ["sh", "-c", "cat ~/.local/state/omarchy/current/theme.name 2>/dev/null || echo 'Omarchy'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateTheme(text)
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!themeProc.running) themeProc.running = true
    }
  }

  hasCursor: false
  radius: Style.space(14)
  color: Util.alpha(panel ? panel.fg : Color.foreground, mouseArea.containsMouse ? 0.12 : 0.055)
  border.width: mouseArea.containsMouse ? Math.max(1, Style.normalBorderWidth) : 0
  border.color: Util.alpha(panel ? panel.fg : Color.foreground, 0.4)
  Behavior on color { ColorAnimation { duration: 120 } }
  implicitHeight: Style.space(58)

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.panel && typeof root.panel.close === "function") {
        root.panel.close()
      }
      Quickshell.execDetached(["sh", "-c", "choice=$(omarchy-theme-switcher); [[ -n \"$choice\" ]] && omarchy-theme-set \"$(basename \"$choice\" | cut -d. -f1)\""])
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
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

      Text {
        anchors.centerIn: parent
        text: "󰔎"
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
        text: "Theme"
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: root.currentTheme
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
