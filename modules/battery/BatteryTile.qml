import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.battery"

  property int batteryPercent: 100
  property bool isCharging: false
  property string activeProfile: "balanced"

  readonly property string batteryIcon: {
    if (root.isCharging) return "󰂄"
    if (root.batteryPercent >= 80) return "󰁹"
    if (root.batteryPercent >= 40) return "󰁽"
    return "󰁺"
  }

  readonly property string formattedProfile: {
    if (root.activeProfile === "performance") return "Performance"
    if (root.activeProfile === "power-saver") return "Power Saver"
    return "Balanced"
  }

  function updateBattery(raw) {
    try {
      var lines = raw.trim().split("\n")
      if (lines.length >= 1) {
        var pct = parseInt(lines[0].trim(), 10)
        if (!isNaN(pct)) root.batteryPercent = Math.max(0, Math.min(100, pct))
      }
      if (lines.length >= 2) {
        var status = lines[1].trim().toLowerCase()
        root.isCharging = status === "charging"
      }
    } catch (e) {}
  }

  function updateProfile(raw) {
    var prof = raw.trim().toLowerCase()
    if (prof) root.activeProfile = prof
  }

  Process {
    id: battProc
    command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/BAT*/status 2>/dev/null || echo '100\\nDischarging'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBattery(text)
    }
  }

  Process {
    id: profProc
    command: ["powerprofilesctl", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateProfile(text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!battProc.running) battProc.running = true
      if (!profProc.running) profProc.running = true
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
      if (root.panel) root.panel.expandModule(root.moduleId, "Battery & Power")
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
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.isCharging ? 0.18 : 0.13)

      Text {
        anchors.centerIn: parent
        text: root.batteryIcon
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
        text: root.batteryPercent + "%" + (root.isCharging ? " Charging" : "")
        color: root.panel ? root.panel.fg : Color.foreground
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: root.formattedProfile
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
