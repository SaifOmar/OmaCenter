import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var panel: null
  property string moduleDir: ""
  readonly property string moduleId: "so.omacenter.display"

  implicitHeight: displayContent.implicitHeight

  property real percent: 1.0
  property string monitorName: "eDP-1"
  property real currentScale: 1.0
  property var availableModes: []
  property string activeMode: "1920x1080@60.00Hz"

  property bool nightlightEnabled: false
  property int temperatureK: 4000
  readonly property real warmthRatio: Math.max(0, Math.min(1, (6000 - temperatureK) / 4000))

  function setBrightness(val) {
    var clamped = Math.max(0.01, Math.min(1.0, val))
    root.percent = clamped
    var intPct = Math.round(clamped * 100)
    Quickshell.execDetached(["omarchy-brightness-display", "--no-osd", intPct.toString() + "%"])
  }

  function setScale(scaleVal) {
    root.currentScale = scaleVal
    Quickshell.execDetached(["omarchy-hyprland-monitor-scaling", scaleVal.toString()])
    monTimer.restart()
  }

  function setMode(modeStr) {
    root.activeMode = modeStr
    var cmd = "hyprctl eval 'hl.monitor({ output = \"" + root.monitorName + "\", mode = \"" + modeStr + "\", position = \"auto\", scale = " + root.currentScale.toString() + " })'"
    Quickshell.execDetached(["sh", "-c", cmd])
    monTimer.restart()
  }

  function toggleNightLight() {
    root.nightlightEnabled = !root.nightlightEnabled
    Quickshell.execDetached(["omarchy-toggle-nightlight"])
    nlTimer.restart()
  }

  function setTemperature(tempK) {
    root.temperatureK = tempK
    root.nightlightEnabled = tempK < 6000
    Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", tempK.toString()])
    nlTimer.restart()
  }

  function parseMonitors(raw) {
    try {
      var list = JSON.parse(raw)
      if (list && list.length > 0) {
        var m = list[0]
        root.monitorName = m.name || "eDP-1"
        if (m.scale) root.currentScale = parseFloat(m.scale) || 1.0
        if (m.availableModes && Array.isArray(m.availableModes)) {
          root.availableModes = m.availableModes
        }
      }
    } catch (e) {}
  }

  function parseBrightness(raw) {
    try {
      var val = parseFloat(raw.trim())
      if (!isNaN(val)) root.percent = val > 1.0 ? Math.min(1.0, val / 100.0) : val
    } catch (e) {}
  }

  function parseNightlight(raw) {
    try {
      var d = JSON.parse(raw)
      root.nightlightEnabled = d.enabled === true
      if (d.temperature && d.temperature > 0) root.temperatureK = d.temperature
    } catch (e) {}
  }

  Process {
    id: monProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMonitors(text)
    }
  }

  Process {
    id: brightProc
    command: ["omarchy-brightness-display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseBrightness(text)
    }
  }

  Process {
    id: nlProc
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseNightlight(text)
    }
  }

  Timer {
    id: monTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (!monProc.running) monProc.running = true
    }
  }

  Timer {
    id: nlTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (!nlProc.running) nlProc.running = true
    }
  }

  Component.onCompleted: {
    monProc.running = true
    brightProc.running = true
    nlProc.running = true
  }

  Column {
    id: displayContent
    width: parent.width
    spacing: Style.space(12)

    // Section 1: Brightness Adjustment
    Rectangle {
      width: parent.width
      height: Style.space(66)
      radius: Style.space(12)
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.04)

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(6)

        Row {
          width: parent.width

          Text {
            text: "Display Brightness (" + root.monitorName + ")"
            color: root.panel ? root.panel.fg : Color.foreground
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Item {
            width: parent.width - parent.children[0].implicitWidth - bVal.implicitWidth
            height: 1
          }

          Text {
            id: bVal
            text: Math.round(root.percent * 100) + "%"
            color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Item {
          width: parent.width
          height: Style.space(16)

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

            Rectangle {
              width: Math.max(0, Math.min(parent.width, parent.width * root.percent))
              height: parent.height
              radius: height / 2
              color: root.panel ? root.panel.fg : Color.foreground
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) { root.setBrightness(mouse.x / width) }
            onPositionChanged: function(mouse) { if (pressed) root.setBrightness(mouse.x / width) }
          }
        }
      }
    }

    // Section 2: Night Light Controls
    Rectangle {
      width: parent.width
      height: Style.space(66)
      radius: Style.space(12)
      color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.04)

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(6)

        Row {
          width: parent.width

          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: Style.space(20)
              height: width
              radius: width / 2
              color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, root.nightlightEnabled ? 0.18 : 0.1)

              Text {
                anchors.centerIn: parent
                text: root.nightlightEnabled ? "󰌵" : "󰌶"
                color: root.panel ? root.panel.fg : Color.foreground
                font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNightLight()
              }
            }

            Text {
              text: "Night Light Warmth"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Item {
            width: parent.width - parent.children[0].implicitWidth - nlVal.implicitWidth
            height: 1
          }

          Text {
            id: nlVal
            text: !root.nightlightEnabled
              ? "Off"
              : (root.temperatureK + "K (" + Math.round(root.warmthRatio * 100) + "%)")
            color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          width: parent.width
          height: Style.space(16)

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.13)

            Rectangle {
              width: !root.nightlightEnabled ? 0 : Math.max(0, Math.min(parent.width, parent.width * root.warmthRatio))
              height: parent.height
              radius: height / 2
              color: root.panel ? root.panel.fg : Color.foreground
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              var ratio = Math.max(0, Math.min(1, mouse.x / width))
              root.setTemperature(Math.round(6000 - (ratio * 4000)))
            }
            onPositionChanged: function(mouse) {
              if (pressed) {
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                root.setTemperature(Math.round(6000 - (ratio * 4000)))
              }
            }
          }
        }
      }
    }

    // Section 3: Display Scaling Options
    Column {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "DISPLAY SCALING"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        readonly property var scaleOptions: [1.0, 1.25, 1.6, 2.0]
        readonly property real btnWidth: (width - (spacing * 3)) / 4

        Repeater {
          model: parent.scaleOptions
          delegate: Rectangle {
            required property real modelData
            readonly property bool isSelected: Math.abs(root.currentScale - modelData) < 0.05
            width: parent.btnWidth
            height: Style.space(36)
            radius: Style.space(8)
            color: isSelected
              ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.12)
              : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.05)

            Text {
              anchors.centerIn: parent
              text: modelData + "x"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: isSelected
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setScale(modelData)
            }
          }
        }
      }
    }

    // Section 4: Display Resolution & Refresh Rate Modes
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: root.availableModes.length > 0

      Text {
        text: "AVAILABLE DISPLAY MODES"
        color: Qt.darker(root.panel ? root.panel.fg : Color.foreground, 1.4)
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Repeater {
        model: root.availableModes
        delegate: Rectangle {
          required property string modelData
          readonly property bool isSelected: root.activeMode === modelData
          width: parent.width
          height: Style.space(40)
          radius: Style.space(8)
          color: isSelected
            ? Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.08)
            : Util.alpha(root.panel ? root.panel.fg : Color.foreground, 0.03)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            Text {
              text: "󰍹"
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: modelData
              color: root.panel ? root.panel.fg : Color.foreground
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: isSelected
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setMode(modelData)
          }
        }
      }
    }
  }
}
