import QtQuick
import qs.Commons

Item {
  id: host

  property var panel: null
  property string moduleId: ""
  property string moduleName: ""
  property string moduleDir: ""
  property string entry: ""
  property string expandedEntry: ""
  property bool expandable: false
  property var moduleConfig: ({})

  readonly property bool isExpanded: panel && panel.expandedModuleId !== "" && panel.expandedModuleId === moduleId

  property string _resolvedExpandedSource: ""

  onIsExpandedChanged: {
    if (isExpanded && host.expandedEntry) {
      _resolvedExpandedSource = host.moduleDir + "/" + host.expandedEntry
    }
  }

  implicitHeight: isExpanded
    ? expandedColumn.implicitHeight
    : (collapsedLoader.item ? collapsedLoader.item.implicitHeight : 0)
  height: implicitHeight

  visible: moduleId !== ""

  // Collapsed view — load the entry QML (kept alive for instant collapse)
  Loader {
    id: collapsedLoader
    anchors.fill: parent
    visible: !host.isExpanded
    source: host.entry ? host.moduleDir + "/" + host.entry : ""

    onLoaded: {
      item.panel = host.panel
      item.moduleDir = host.moduleDir
      if (item.moduleConfig !== undefined) item.moduleConfig = host.moduleConfig
    }
  }

  // Expanded view — back header + expanded content
  Column {
    id: expandedColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(10)
    visible: host.isExpanded

    // Back button header
    Row {
      width: parent.width
      spacing: Style.space(8)
      z: 5

      Text {
        id: backText
        text: "\u2190 " + host.moduleName
        color: host.panel ? host.panel.fg : Color.foreground
        font.family: host.panel && host.panel.bar ? host.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        z: 10

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          z: 10
          onClicked: {
            if (host.panel) host.panel.collapseExpanded()
          }
        }
      }

      Item {
        width: parent.width - backText.implicitWidth - parent.spacing
        height: 1
      }
    }

    // Expanded content
    Loader {
      id: expandedLoader
      width: parent.width
      source: _resolvedExpandedSource

      onLoaded: {
        item.panel = host.panel
        item.moduleDir = host.moduleDir
        if (item.moduleConfig !== undefined) item.moduleConfig = host.moduleConfig
      }
    }
  }
}
