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
  property string pendingThemeName: ""

  function updateTheme(raw) {
    var t = raw.trim()
    if (t) root.currentTheme = t
  }

  function applyThemeChoice(raw) {
    var choice = raw.trim()
    if (!choice) return
    // Extract theme name from path: /path/to/Theme.qml -> Theme
    var baseName = choice.split("/").pop()
    var themeName = baseName.split(".")[0]
    if (themeName) {
      root.pendingThemeName = themeName
      setThemeProc.running = true
    }
  }

  // Background process to check active theme name
  Process {
    id: themeProc
    command: ["cat", Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = text.trim()
        root.updateTheme(result || "Omarchy")
      }
    }
  }

  // Get theme choice from switcher
  Process {
    id: getThemeChoiceProc
    command: ["omarchy-theme-switcher"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyThemeChoice(text)
    }
  }

  // Set the selected theme
  Process {
    id: setThemeProc
    command: ["omarchy-theme-set", root.pendingThemeName]
    stdout: StdioCollector { waitForEnd: true }
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
      getThemeChoiceProc.running = true
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
