import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property var dispatcher: null
    property int workspaceIndex: 0
    property string workspaceName: ""
    property string outputName: ""
    property int windowCount: 0

    // Drag-and-drop
    property int modelIndex: 0
    property Item dragCoordRoot: null
    property bool isBeingDragged: false

    signal nameChanged(int index, string newName, string outputName)
    signal removeRequested(int index, string outputName)
    signal panelDragStarted(var wsData, string outputName, int modelIndex, real globalX, real globalY)
    signal panelDragMoved(real globalX, real globalY)
    signal panelDragEnded()

    property bool editing: false
    property string editText: root.workspaceName

    Rectangle {
        anchors.fill: parent
        color: Color.mSurface
        radius: Style.radiusM
        opacity: root.isBeingDragged ? 0.3 : 1.0

        Behavior on opacity {
            NumberAnimation { duration: Style.animationFast }
        }

        RowLayout {
            id: rowLayout
            anchors {
                fill: parent
                leftMargin: Style.marginM
                rightMargin: Style.marginM
                topMargin: Style.marginS
                bottomMargin: Style.marginS
            }
            spacing: Style.marginM

            // Drag handle
            Rectangle {
                id: dragHandle
                Layout.preferredWidth: 20
                Layout.preferredHeight: 28
                radius: Style.radiusS
                color: dragHandleArea.containsMouse ? Color.mSurfaceVariant : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Style.animationFast }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: 3
                        Rectangle {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 2
                            radius: 1
                            color: Color.mOutline
                        }
                    }
                }

                MouseArea {
                    id: dragHandleArea
                    anchors.fill: parent
                    cursorShape: Qt.SizeVerCursor
                    hoverEnabled: true
                    preventStealing: false

                    onEntered: TooltipService.show(dragHandle, "Drag to reorder")
                    onExited: TooltipService.hide(dragHandle)

                    onPressed: mouse => {
                        TooltipService.hide(dragHandle)
                        if (!root.dragCoordRoot) return
                        preventStealing = true
                        var gp = dragHandle.mapToItem(root.dragCoordRoot, mouse.x, mouse.y)
                        root.panelDragStarted(
                            { index: root.workspaceIndex, name: root.workspaceName, windowCount: root.windowCount },
                            root.outputName, root.modelIndex, gp.x, gp.y
                        )
                    }

                    onPositionChanged: mouse => {
                        if (!root.isBeingDragged || !root.dragCoordRoot) return
                        var gp = dragHandle.mapToItem(root.dragCoordRoot, mouse.x, mouse.y)
                        root.panelDragMoved(gp.x, gp.y)
                    }

                    onReleased: {
                        preventStealing = false
                        if (root.isBeingDragged) root.panelDragEnded()
                    }

                    onCanceled: {
                        preventStealing = false
                        if (root.isBeingDragged) root.panelDragEnded()
                    }
                }
            }

            // Index badge
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Style.radiusS
                color: Color.mSurfaceVariant

                NText {
                    anchors.centerIn: parent
                    text: String(root.workspaceIndex)
                    pointSize: Style.fontSizeS
                    font.weight: Font.Bold
                    color: Color.mOnSurfaceVariant
                }
            }

            // Workspace name
            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 80
                Layout.preferredHeight: nameDisplay.implicitHeight + Style.marginS
                color: "transparent"
                clip: true

                NText {
                    id: nameDisplay
                    width: parent.width
                    visible: !root.editing
                    text: root.workspaceName || "(unnamed)"
                    pointSize: Style.fontSizeS
                    font.weight: root.workspaceName ? Font.Medium : Font.Normal
                    color: root.workspaceName ? Color.mOnSurface : Color.mOnSurfaceVariant
                    font.italic: !root.workspaceName
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: {
                            root.editing = true
                            root.editText = root.workspaceName
                            editField.forceActiveFocus()
                            editField.selectAll()
                        }
                    }
                }

                TextInput {
                    id: editField
                    width: parent.width
                    visible: root.editing
                    text: root.editText
                    color: Color.mPrimary
                    font.family: nameDisplay.font.family
                    font.pointSize: nameDisplay.font.pointSize
                    font.weight: Font.Medium
                    clip: true
                    selectByMouse: true
                    anchors.verticalCenter: parent.verticalCenter

                    onTextChanged: root.editText = text

                    Keys.onReturnPressed: {
                        if (root.editText !== root.workspaceName) {
                            root.nameChanged(root.workspaceIndex, root.editText, root.outputName)
                        }
                        root.editing = false
                    }

                    Keys.onEscapePressed: {
                        root.editing = false
                        root.editText = root.workspaceName
                    }

                    onActiveFocusChanged: {
                        if (!activeFocus && root.editing) {
                            root.editing = false
                            root.editText = root.workspaceName
                        }
                    }
                }
            }

            // Window count badge
            Rectangle {
                visible: root.windowCount > 0
                Layout.preferredWidth: countRow.implicitWidth + Style.marginM * 2
                Layout.preferredHeight: 26
                radius: Style.radiusS
                color: Color.mSurfaceVariant

                Row {
                    id: countRow
                    anchors.centerIn: parent
                    spacing: 4

                    NIcon {
                        icon: "app-window"
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    NText {
                        text: String(root.windowCount)
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    NText {
                        text: root.windowCount === 1 ? "column" : "columns"
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Remove workspace
            NIconButton {
                icon: "trash"
                tooltipText: "Remove workspace"
                onClicked: root.removeRequested(root.workspaceIndex, root.outputName)
            }
        }
    }
}
