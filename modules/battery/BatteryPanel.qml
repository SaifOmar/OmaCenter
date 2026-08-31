import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.battery"

  implicitHeight: batteryContent.implicitHeight

  property int batteryPercent: 100
  property bool isCharging: false
  property string activeProfile: "balanced"

  readonly property var profiles: [
    { id: "performance", name: "Performance", icon: "󰓅", desc: "Maximum processing speed" },
    { id: "balanced", name: "Balanced", icon: "󰾅", desc: "Balanced power & performance" },
    { id: "power-saver", name: "Power Saver", icon: "󰌪", desc: "Preserve battery runtime" }
  ]

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

  function setPowerProfile(profId) {
    root.activeProfile = profId
    Quickshell.execDetached(["omarchy-powerprofiles-set", profId])
    Quickshell.execDetached(["powerprofilesctl", "set", profId])
    refreshTimer.restart()
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
    id: refreshTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (!profProc.running) profProc.running = true
    }
  }

  Component.onCompleted: {
    battProc.running = true
    profProc.running = true
  }

  Column {
    id: batteryContent
    width: parent.width
    spacing: Style.space(12)

    // Battery Hero Status Banner
    Rectangle {
      width: parent.width
      height: Style.space(70)
      radius: Style.space(14)
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.05)

      Row {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(12)

        Rectangle {
          width: Style.space(46)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.isCharging ? 0.18 : 0.1)

          Text {
            anchors.centerIn: parent
            text: root.isCharging ? "󰂄" : (root.batteryPercent >= 80 ? "󰁹" : (root.batteryPercent >= 40 ? "󰁽" : "󰁺"))
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.space(24)
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.batteryPercent + "%"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: root.isCharging ? "Charging" : "Discharging"
            color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // Power Profiles Menu Section
    Column {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "POWER PROFILES"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.profiles
        delegate: Rectangle {
          required property var modelData
          readonly property bool isSelected: root.activeProfile === modelData.id
          width: parent.width
          height: Style.space(48)
          radius: Style.space(10)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.08)
            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.03)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            Text {
              text: modelData.icon
              color: isSelected
                ? (root.panel ? root.panel.fg : Color.foreground)
                : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.6)
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              width: parent.width - Style.space(40)

              Text {
                text: modelData.name
                color: root.panel ? root.panel.fg : Color.foreground
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: isSelected
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: modelData.desc
                color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setPowerProfile(modelData.id)
          }
        }
      }
    }
  }
}
