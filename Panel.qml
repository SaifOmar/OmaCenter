import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "so.omacenter"
    ipcTarget: "so.omacenter"

    // ─── Module registry (loaded from layout_manager.py) ────────

    property var moduleConfigs: ({})
    property bool moduleConfigsLoaded: false

    Component.onCompleted: layoutProcess.running = true

    Process {
        id: layoutProcess
        command: ["python3", Qt.resolvedUrl("layout_manager.py").toString().replace("file://", "")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var plan = JSON.parse(text);
                    root.moduleConfigs = plan.modules || {};
                } catch (e) {
                    console.warn("layout_manager: failed to parse output:", e);
                    root.moduleConfigs = {};
                }
                root.moduleConfigsLoaded = true;
            }
        }
    }

    // ─── Module expansion state ────────────────────────────────

    property string expandedModuleId: ""
    property string expandedModuleName: ""
    property var activeMprisPlayer: null

    function expandModule(moduleId, moduleName) {
        root.expandedModuleId = moduleId;
        root.expandedModuleName = moduleName;
    }

    function collapseExpanded() {
        root.expandedModuleId = "";
        root.expandedModuleName = "";
        root.activeMprisPlayer = null;
    }

    // ─── Shared styling ────────────────────────────────────────

    readonly property int panelWidth: root.setting("width", 460)
    readonly property color fg: bar ? bar.foreground : Color.foreground
    readonly property color hoverFill: Style.hoverFillFor(fg, Color.accent)
    readonly property color selectedFill: Style.selectedFillFor(fg, Color.accent)

    function setting(name, fallback) {
        var value = root.bar && typeof root.bar.setting === "function" ? root.bar.setting(name) : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    function summonPanel(pluginId) {
        if (!bar || !bar.shell || typeof bar.shell.summon !== "function")
            return;
        bar.shell.summon(pluginId);
    }

    // ─── Lifecycle ─────────────────────────────────────────────

    onOpenedChanged: {
        if (opened) {
            root.collapseExpanded();
            Qt.callLater(function () {
                keyCatcher.forceActiveFocus();
            });
        } else {
            root.collapseExpanded();
        }
    }

    // ─── Bar button ────────────────────────────────────────────

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󱇌"
        tooltipText: "Control Center"
        onPressed: function (b) {
            if (b === Qt.RightButton)
                root.close();
            else
                root.toggle();
        }
    }

    // ─── Popup ─────────────────────────────────────────────────

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
        contentHeight: panel.fittedContentHeight(expandedModuleHost.visible ? expandedModuleHost.implicitHeight : mainColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: {
                if (root.expandedModuleId)
                    root.collapseExpanded();
                else
                    root.close();
            }

            // ─── Collapsed view ────────────────────────────────────

            Column {
                id: mainColumn
                visible: !root.expandedModuleId && root.moduleConfigsLoaded
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.space(10)

                // Top row: 2x2 connectivity grid + Media
                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    readonly property real halfWidth: (width - spacing) / 2
                    readonly property int moduleHeight: Style.space(138)

                    // Left: 2x2 connectivity grid
                    Rectangle {
                        width: parent.halfWidth
                        height: parent.moduleHeight
                        radius: Style.space(14)
                        color: Util.alpha(root.fg, 0.055)

                        Grid {
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            columns: 2
                            rows: 2
                            spacing: Style.space(4)

                            readonly property real cellWidth: (width - spacing) / 2
                            readonly property real cellHeight: (height - spacing) / 2

                            Repeater {
                                model: [0, 1, 2, 3]
                                Item {
                                    required property int modelData
                                    readonly property var slotModule: {
                                        var modules = root.moduleConfigs;
                                        for (var id in modules) {
                                            if (modules[id].group === "connectivity" && modules[id].gridSlot === modelData)
                                                return modules[id];
                                        }
                                        return null;
                                    }
                                    width: parent.cellWidth
                                    height: parent.cellHeight
                                    visible: slotModule !== null

                                    ModuleHost {
                                        anchors.fill: parent
                                        panel: root
                                        moduleId: slotModule ? slotModule.id : ""
                                        moduleName: slotModule ? slotModule.name : ""
                                        moduleDir: slotModule ? Qt.resolvedUrl(slotModule.dir) : ""
                                        entry: slotModule ? slotModule.entry : ""
                                        expandable: slotModule ? slotModule.expandable || false : false
                                        expandedEntry: slotModule ? slotModule.expandedEntry || "" : ""
                                    }
                                }
                            }
                        }
                    }

                    // Right: Media module (type === "media")
                    Repeater {
                        model: Object.keys(root.moduleConfigs).filter(function (id) {
                            var m = root.moduleConfigs[id];
                            return m.type === "media" || m.group === "media";
                        })
                        ModuleHost {
                            required property string modelData
                            width: parent.halfWidth
                            height: parent.moduleHeight
                            panel: root
                            moduleId: modelData
                            moduleName: root.moduleConfigs[modelData].name
                            moduleDir: Qt.resolvedUrl(root.moduleConfigs[modelData].dir)
                            entry: root.moduleConfigs[modelData].entry
                            expandable: root.moduleConfigs[modelData].expandable || false
                            expandedEntry: root.moduleConfigs[modelData].expandedEntry || ""
                        }
                    }
                }

                // Row 2: Focus tiles (Battery & DnD side-by-side, half-width each)
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: Style.space(8)

                    readonly property real cellWidth: (width - spacing) / 2

                    Repeater {
                        model: Object.keys(root.moduleConfigs).filter(function (id) {
                            var m = root.moduleConfigs[id];
                            return m.group === "focus" && m.type !== "media";
                        })
                        ModuleHost {
                            required property string modelData
                            width: parent.cellWidth
                            panel: root
                            moduleId: modelData
                            moduleName: root.moduleConfigs[modelData].name
                            moduleDir: Qt.resolvedUrl(root.moduleConfigs[modelData].dir)
                            entry: root.moduleConfigs[modelData].entry
                            expandable: root.moduleConfigs[modelData].expandable || false
                            expandedEntry: root.moduleConfigs[modelData].expandedEntry || ""
                        }
                    }
                }

                // Row 3+: Full-width control modules
                Repeater {
                    model: Object.keys(root.moduleConfigs).filter(function (id) {
                        var m = root.moduleConfigs[id];
                        return m.group === "controls" || m.width === "full";
                    })
                    ModuleHost {
                        required property string modelData
                        width: mainColumn.width
                        panel: root
                        moduleId: modelData
                        moduleName: root.moduleConfigs[modelData].name
                        moduleDir: Qt.resolvedUrl(root.moduleConfigs[modelData].dir)
                        entry: root.moduleConfigs[modelData].entry
                        expandable: root.moduleConfigs[modelData].expandable || false
                        expandedEntry: root.moduleConfigs[modelData].expandedEntry || ""
                    }
                }
            }

            // ─── Expanded view (ModuleHost) ────────────────────────

            ModuleHost {
                id: expandedModuleHost
                visible: root.expandedModuleId !== ""
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                panel: root
                moduleId: root.expandedModuleId
                moduleName: root.expandedModuleName
                moduleDir: Qt.resolvedUrl(root.moduleConfigs[root.expandedModuleId] ? root.moduleConfigs[root.expandedModuleId].dir : "")
                entry: root.moduleConfigs[root.expandedModuleId] ? root.moduleConfigs[root.expandedModuleId].entry : ""
                expandable: root.moduleConfigs[root.expandedModuleId] ? root.moduleConfigs[root.expandedModuleId].expandable || false : false
                expandedEntry: root.moduleConfigs[root.expandedModuleId] ? root.moduleConfigs[root.expandedModuleId].expandedEntry || "" : ""
            }
        }
    }
}
