import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property string outputName: ""
    property var workspaces: []
    property var dispatcher: null
    property var pluginApi: null
    property var outputAliases: ({})
    property Item dragCoordRoot: null

    // Panel drag state (set by Panel)
    property bool panelDragActive: false
    property string panelDragTargetOutput: ""
    property int panelDragTargetInsertIndex: -1
    property string panelDragSourceOutput: ""
    property int panelDragSourceModelIndex: -1

    signal workspaceNameChanged(int index, string name, string outputName)
    signal editingChanged(bool isEditing)
    signal workspaceRemoveRequested(int index, string outputName)
    signal workspaceAddRequested(string outputName)
    signal workspacePanelDragStarted(var wsData, string outputName, int modelIndex, real globalX, real globalY)
    signal workspacePanelDragMoved(real globalX, real globalY)
    signal workspacePanelDragEnded()

    Layout.fillWidth: true
    spacing: Style.marginS

    // Output header
    RowLayout {
        id: outputHeader
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
            icon: "device-desktop"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
        }

        NText {
            text: root.outputAliases[root.outputName] || root.outputName
            pointSize: Style.fontSizeS
            font.weight: Font.Bold
            color: Color.mPrimary
        }

        NIcon {
            icon: "stack-2"
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
        }

        NText {
            text: root.workspaces.length + " " + (root.workspaces.length === 1 ? "workspace" : "workspaces")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
        }

        Item { Layout.fillWidth: true }
    }

    // Workspace container with drag positioning
    Item {
        id: workspaceContainer
        Layout.fillWidth: true

        readonly property real itemHeight: Style.baseWidgetSize + Style.margin2S
        readonly property real itemSpacing: Style.marginS
        readonly property real stepSize: itemHeight + itemSpacing

        // Compute content height, adding a slot for cross-group insertion
        readonly property bool isDropTarget: root.panelDragActive
            && root.panelDragTargetOutput === root.outputName
            && root.panelDragSourceOutput !== root.outputName
        readonly property int slotCount: root.workspaces.length + (isDropTarget ? 1 : 0)
        readonly property real contentHeight: slotCount > 0
            ? slotCount * itemHeight + (slotCount - 1) * itemSpacing
            : 0

        implicitHeight: contentHeight
        clip: true

        // Cross-group insertion indicator
        Rectangle {
            visible: workspaceContainer.isDropTarget && root.panelDragTargetInsertIndex >= 0
            x: 0
            y: root.panelDragTargetInsertIndex * workspaceContainer.stepSize - 2
            width: workspaceContainer.width
            height: 3
            radius: 2
            color: Color.mPrimary
            z: 50
        }

        Repeater {
            id: wsRepeater
            model: root.workspaces

            WorkspaceRow {
                required property var modelData
                required property int index

                width: workspaceContainer.width
                height: workspaceContainer.itemHeight

                pluginApi: root.pluginApi
                dispatcher: root.dispatcher
                workspaceIndex: modelData.index ?? (index + 1)
                workspaceName: modelData.name ?? ""
                outputName: root.outputName
                windowCount: modelData.windowCount ?? 0
                dragCoordRoot: root.dragCoordRoot

                modelIndex: index
                isBeingDragged: root.panelDragActive
                    && root.panelDragSourceOutput === root.outputName
                    && root.panelDragSourceModelIndex === index

                // Position logic
                y: {
                    var isSameGroupDrag = root.panelDragActive
                        && root.panelDragSourceOutput === root.outputName
                        && root.panelDragTargetOutput === root.outputName

                    var isCrossGroupSource = root.panelDragActive
                        && root.panelDragSourceOutput === root.outputName
                        && root.panelDragTargetOutput !== root.outputName

                    var isCrossGroupTarget = root.panelDragActive
                        && root.panelDragSourceOutput !== root.outputName
                        && root.panelDragTargetOutput === root.outputName

                    var step = workspaceContainer.stepSize

                    // Same-group drag: shift rows to make room
                    if (isSameGroupDrag) {
                        var draggedIdx = root.panelDragSourceModelIndex
                        var targetIdx = root.panelDragTargetInsertIndex
                        if (draggedIdx !== -1 && targetIdx !== -1 && draggedIdx !== targetIdx) {
                            if (draggedIdx < targetIdx) {
                                if (index > draggedIdx && index <= targetIdx)
                                    return (index - 1) * step
                            } else {
                                if (index >= targetIdx && index < draggedIdx)
                                    return (index + 1) * step
                            }
                        }
                    }

                    // Source of cross-group drag: close gap
                    if (isCrossGroupSource) {
                        var src = root.panelDragSourceModelIndex
                        if (index > src)
                            return (index - 1) * step
                    }

                    // Target of cross-group drag: open gap at insertion point
                    if (isCrossGroupTarget) {
                        var ins = root.panelDragTargetInsertIndex
                        if (ins >= 0 && index >= ins)
                            return (index + 1) * step
                    }

                    return index * step
                }

                Behavior on y {
                    enabled: !isBeingDragged
                    NumberAnimation { duration: Style.animationNormal; easing.type: Easing.OutQuad }
                }

                onNameChanged: function(idx, name, output) {
                    root.workspaceNameChanged(idx, name, output)
                }
                onEditingChanged: root.editingChanged(editing)
                onRemoveRequested: function(idx, output) {
                    root.workspaceRemoveRequested(idx, output)
                }
                onPanelDragStarted: function(wsData, outputName, modelIndex, gx, gy) {
                    root.workspacePanelDragStarted(wsData, outputName, modelIndex, gx, gy)
                }
                onPanelDragMoved: function(gx, gy) {
                    root.workspacePanelDragMoved(gx, gy)
                }
                onPanelDragEnded: function() { root.workspacePanelDragEnded() }
            }
        }
    }

    // Add workspace button
    Rectangle {
        Layout.fillWidth: true
        height: Style.baseWidgetSize
        radius: Style.radiusM
        color: addArea.containsMouse ? Color.mSurfaceVariant : "transparent"
        border.color: addArea.containsMouse ? Color.mOutline : Color.mSurfaceVariant
        border.width: 1

        Behavior on color { ColorAnimation { duration: Style.animationFast } }
        Behavior on border.color { ColorAnimation { duration: Style.animationFast } }

        MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.workspaceAddRequested(root.outputName)
        }

        Row {
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                icon: "plus"
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }

            NText {
                text: "Add workspace"
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
