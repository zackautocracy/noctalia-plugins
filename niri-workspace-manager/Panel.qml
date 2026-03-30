import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets
import "components"

Item {
    id: root

    property var pluginApi: null

    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: Math.round(460 * Style.uiScaleRatio)
    property real contentPreferredHeight: Math.round(500 * Style.uiScaleRatio)

    readonly property var service: pluginApi?.mainInstance
    readonly property var dispatcher: service?.dispatcher ?? null
    readonly property var persistence: service?.persistence ?? null
    readonly property bool isReady: service?.ready ?? false

    // Display name mapping for outputs (user aliases override auto-detected)
    readonly property var outputAliases: {
        var detected = service?.detectedOutputNames ?? {}
        var userAliases = service?.settings?.outputAliases ?? {}
        var merged = {}
        for (var k in detected) merged[k] = detected[k]
        for (var k2 in userAliases) merged[k2] = userAliases[k2]
        return merged
    }

    function displayName(outputName) {
        return root.outputAliases[outputName] || outputName
    }

    anchors.fill: parent

    // Track whether any workspace row is being edited or dragged
    property bool editing: false

    // --- Panel-level drag state ---
    property bool panelDragActive: false
    property string panelDragSourceOutput: ""
    property int panelDragSourceModelIndex: -1
    property var panelDragData: null
    property string panelDragTargetOutput: ""
    property int panelDragTargetInsertIndex: -1
    property real panelDragProxyX: 0
    property real panelDragProxyY: 0
    property real _dragScrollSpeed: 0

    Timer {
        id: dragScrollTimer
        interval: 16
        repeat: true
        running: root.panelDragActive && root._dragScrollSpeed !== 0
        onTriggered: {
            var flickable = workspaceScrollView.contentItem
            var newY = flickable.contentY + root._dragScrollSpeed
            flickable.contentY = Math.max(0, Math.min(newY, flickable.contentHeight - flickable.height))
        }
    }

    function startPanelDrag(wsData, sourceOutput, sourceModelIndex, globalX, globalY) {
        Logger.i("NiriWSM", "[DRAG] startPanelDrag: source=", sourceOutput, "idx=", sourceModelIndex, "pos=", globalX, globalY)
        root.panelDragData = wsData
        root.panelDragSourceOutput = sourceOutput
        root.panelDragSourceModelIndex = sourceModelIndex
        root.panelDragTargetOutput = sourceOutput
        root.panelDragTargetInsertIndex = sourceModelIndex
        root.panelDragProxyX = globalX - dragProxy.width / 2
        root.panelDragProxyY = globalY - dragProxy.height / 2
        root.panelDragActive = true
        root.editing = true
    }

    function updatePanelDrag(globalX, globalY) {
        root.panelDragProxyX = globalX - dragProxy.width / 2
        root.panelDragProxyY = globalY - dragProxy.height / 2

        // Auto-scroll when dragging near scroll view edges
        var scrollEdge = 40
        var maxSpeed = 8
        var localPos = workspaceScrollView.mapFromItem(panelContainer, globalX, globalY)
        if (localPos.y < scrollEdge && localPos.y >= 0) {
            root._dragScrollSpeed = -maxSpeed * (1 - localPos.y / scrollEdge)
        } else if (localPos.y > workspaceScrollView.height - scrollEdge && localPos.y <= workspaceScrollView.height) {
            root._dragScrollSpeed = maxSpeed * (1 - (workspaceScrollView.height - localPos.y) / scrollEdge)
        } else {
            root._dragScrollSpeed = 0
        }

        var target = findDropTarget(globalX, globalY)
        if (target) {
            root.panelDragTargetOutput = target.output
            root.panelDragTargetInsertIndex = target.index
        }
    }

    function endPanelDrag() {
        root._dragScrollSpeed = 0
        Logger.i("NiriWSM", "[DRAG] endPanelDrag: target=", root.panelDragTargetOutput, "idx=", root.panelDragTargetInsertIndex, "source=", root.panelDragSourceOutput)
        if (root.panelDragTargetOutput && root.panelDragTargetInsertIndex >= 0) {
            if (root.panelDragTargetOutput === root.panelDragSourceOutput) {
                // Same group: reorder
                root.handleReorderWorkspace(root.panelDragSourceModelIndex, root.panelDragTargetInsertIndex, root.panelDragSourceOutput)
            } else {
                // Cross-group: move to other monitor then position
                var targetNiriIndex = root.panelDragTargetInsertIndex + 1  // 0-based model → 1-based niri
                if (root.panelDragData.name) {
                    var ref = root.dispatcher.refByName(root.panelDragData.name)
                    root.dispatcher.moveWorkspaceToMonitor(ref, root.panelDragTargetOutput)
                    root.dispatcher.moveWorkspaceToIndex(ref, targetNiriIndex)
                } else {
                    // Unnamed: focus source monitor + workspace first, then move focused
                    root.dispatcher.focusAndMoveWorkspaceToMonitor(
                        root.panelDragSourceOutput, root.panelDragData.index,
                        root.panelDragTargetOutput, targetNiriIndex)
                }
                Logger.i("NiriWSM", "Moved workspace to", root.panelDragTargetOutput, "at index", targetNiriIndex)
            }
        }

        root.panelDragActive = false
        root.panelDragSourceOutput = ""
        root.panelDragSourceModelIndex = -1
        root.panelDragData = null
        root.panelDragTargetOutput = ""
        root.panelDragTargetInsertIndex = -1
        root.editing = false
    }

    function findDropTarget(globalX, globalY) {
        for (var i = 0; i < outputGroupRepeater.count; i++) {
            var group = outputGroupRepeater.itemAt(i)
            if (!group) continue

            var localPos = group.mapFromItem(panelContainer, globalX, globalY)
            if (localPos.y >= 0 && localPos.y < group.height) {
                Logger.d("NiriWSM", "[DRAG] findDropTarget: hit group", group.outputName, "localY=", localPos.y, "groupH=", group.height)
                // Calculate insertion index within the group's workspace container
                var headerHeight = group.spacing + 30 // approximate header height
                var containerY = localPos.y - headerHeight
                if (containerY < 0) return { output: group.outputName, index: 0 }

                var step = (Style.baseWidgetSize + Style.margin2S) + Style.marginS
                var idx = Math.floor((containerY + (Style.baseWidgetSize + Style.margin2S) / 2) / step)
                idx = Math.max(0, Math.min(idx, group.workspaces.length))
                return { output: group.outputName, index: idx }
            }
        }
        Logger.d("NiriWSM", "[DRAG] findDropTarget: NO HIT globalX=", globalX, "globalY=", globalY, "groupCount=", outputGroupRepeater.count)
        return null
    }

    // --- Build workspace data grouped by output ---
    // Use a cached model that freezes during editing to prevent Repeater rebuilds
    property var workspacesByOutput: []

    function rebuildWorkspaceModel() {
        if (!root.isReady) {
            root.workspacesByOutput = []
            return
        }

        var outputMap = {}
        var outputOrder = []
        var workspaces = CompositorService.workspaces

        for (var i = 0; i < workspaces.count; i++) {
            var ws = workspaces.get(i)
            var output = ws.output ?? "unknown"

            if (!outputMap[output]) {
                outputMap[output] = []
                outputOrder.push(output)
            }

            var windowCount = CompositorService.getWindowsForWorkspace(ws.id).length
            outputMap[output].push({
                index: ws.idx ?? (i + 1),
                name: ws.name ?? "",
                windowCount: windowCount,
                id: ws.id ?? 0
            })
        }

        var result = []
        for (var j = 0; j < outputOrder.length; j++) {
            var wsList = outputMap[outputOrder[j]]
            // Hide trailing unnamed empty workspaces (auto-created + removal leftovers)
            while (wsList.length > 0) {
                var last = wsList[wsList.length - 1]
                if (!last.name && last.windowCount === 0) {
                    wsList = wsList.slice(0, -1)
                } else {
                    break
                }
            }
            result.push({
                output: outputOrder[j],
                workspaces: wsList
            })
        }
        root.workspacesByOutput = result
    }

    // Rebuild on readiness change
    onIsReadyChanged: if (!root.editing) rebuildWorkspaceModel()

    // Rebuild when editing ends
    onEditingChanged: if (!root.editing) rebuildWorkspaceModel()

    Connections {
        target: CompositorService
        function onWorkspaceChanged() { if (!root.editing) root.rebuildWorkspaceModel() }
        function onWindowListChanged() { if (!root.editing) root.rebuildWorkspaceModel() }
    }

    Component.onCompleted: rebuildWorkspaceModel()

    // --- Actions ---

    // Get best reference for a workspace - prefer name (unambiguous) over index
    function getWorkspaceRef(index, outputName) {
        for (var i = 0; i < root.workspacesByOutput.length; i++) {
            var group = root.workspacesByOutput[i]
            if (group.output === outputName) {
                for (var j = 0; j < group.workspaces.length; j++) {
                    var ws = group.workspaces[j]
                    if (ws.index === index && ws.name) {
                        return root.dispatcher.refByName(ws.name)
                    }
                }
            }
        }
        return root.dispatcher.refByIndex(index)
    }

    function handleNameChange(index, name, outputName) {
        if (!root.dispatcher) return

        if (name && name.trim() !== "") {
            var trimmedName = name.trim()

            // Check for duplicate workspace names across all outputs
            for (var d = 0; d < root.workspacesByOutput.length; d++) {
                var dGroup = root.workspacesByOutput[d]
                for (var dk = 0; dk < dGroup.workspaces.length; dk++) {
                    var dws = dGroup.workspaces[dk]
                    if (dws.name === trimmedName && !(dGroup.output === outputName && dws.index === index)) {
                        ToastService.showError("Niri Workspace Manager", "Workspace \"" + trimmedName + "\" already exists")
                        return
                    }
                }
            }

            // Check if the workspace currently has a name (unambiguous ref)
            var currentName = null
            for (var i = 0; i < root.workspacesByOutput.length; i++) {
                var group = root.workspacesByOutput[i]
                if (group.output === outputName) {
                    for (var j = 0; j < group.workspaces.length; j++) {
                        var ws = group.workspaces[j]
                        if (ws.index === index && ws.name) {
                            currentName = ws.name
                        }
                    }
                }
            }

            if (currentName) {
                // Has a name: use name-based ref (unambiguous)
                root.dispatcher.setWorkspaceName(root.dispatcher.refByName(currentName), trimmedName)
            } else {
                // Unnamed: focus monitor + workspace, then set name on focused
                root.editing = true
                root.dispatcher.focusAndSetWorkspaceName(outputName, index, trimmedName)
                root.dispatcher.whenDone(function() {
                    root.editing = false
                })
            }
        } else {
            var ref = root.getWorkspaceRef(index, outputName)
            root.dispatcher.unsetWorkspaceName(ref)
        }
        Logger.i("NiriWSM", "Renamed workspace", index, "on", outputName, "to", name)
    }

    function handleReorderWorkspace(fromModelIndex, toModelIndex, outputName) {
        if (!root.dispatcher) return

        for (var i = 0; i < root.workspacesByOutput.length; i++) {
            var group = root.workspacesByOutput[i]
            if (group.output !== outputName) continue

            if (fromModelIndex < 0 || fromModelIndex >= group.workspaces.length) return
            if (toModelIndex < 0 || toModelIndex > group.workspaces.length) return

            // "After last" → clamp to last position
            var effectiveTarget = Math.min(toModelIndex, group.workspaces.length - 1)
            if (fromModelIndex === effectiveTarget) return

            var sourceWs = group.workspaces[fromModelIndex]
            var targetWs = group.workspaces[effectiveTarget]

            var ref = sourceWs.name
                ? root.dispatcher.refByName(sourceWs.name)
                : root.dispatcher.refByIndex(sourceWs.index)

            root.dispatcher.moveWorkspaceToIndex(ref, targetWs.index)
            Logger.i("NiriWSM", "Reordered workspace from index", sourceWs.index, "to", targetWs.index, "on", outputName)
            break
        }
    }

    function handleRemoveWorkspace(index, outputName) {
        if (!root.dispatcher) return

        root.editing = true  // Freeze model during removal

        // Find the workspace data and adjacent target for window migration
        var targetRef = null
        var wsId = null
        var wsName = null
        for (var i = 0; i < root.workspacesByOutput.length; i++) {
            var group = root.workspacesByOutput[i]
            if (group.output !== outputName) continue

            for (var j = 0; j < group.workspaces.length; j++) {
                var ws = group.workspaces[j]
                if (ws.index !== index) continue

                wsId = ws.id
                wsName = ws.name

                // Pick adjacent workspace on same output as migration target
                var adjacent = group.workspaces[j - 1] || group.workspaces[j + 1]
                if (adjacent) {
                    targetRef = adjacent.name
                        ? root.dispatcher.refByName(adjacent.name)
                        : root.dispatcher.refByIndex(adjacent.index)
                }
                break
            }
            break
        }

        // Move all windows from this workspace to the adjacent one
        if (wsId !== null && targetRef) {
            var windows = CompositorService.getWindowsForWorkspace(wsId)
            for (var w = 0; w < windows.length; w++) {
                root.dispatcher.moveWindowToWorkspace(targetRef, windows[w].id)
            }
        }

        // Focus the workspace, unset name, move to end so Niri auto-removes it
        root.dispatcher.removeWorkspace(outputName, index, wsName)
        Logger.i("NiriWSM", "Removed workspace", index, "on", outputName)

        // Unfreeze model after all commands complete
        root.dispatcher.whenDone(function() {
            root.editing = false
        })
    }

    function handleAddWorkspace(outputName) {
        if (!root.dispatcher) return

        root.editing = true  // Freeze model during add

        // Name the auto-created last workspace on this output, claiming it
        // Niri will then auto-create a new empty workspace after it
        // Get the actual last workspace index from compositor (not the trimmed model)
        var workspaces = CompositorService.workspaces
        var lastIndex = 0
        for (var i = 0; i < workspaces.count; i++) {
            var ws = workspaces.get(i)
            if (ws.output === outputName) {
                if (ws.idx > lastIndex) lastIndex = ws.idx
            }
        }

        // Generate unique name
        var baseName = "New workspace"
        var newName = baseName
        var counter = 2
        var nameExists = true
        while (nameExists) {
            nameExists = false
            for (var d = 0; d < root.workspacesByOutput.length && !nameExists; d++) {
                var grp = root.workspacesByOutput[d]
                for (var dk = 0; dk < grp.workspaces.length; dk++) {
                    if (grp.workspaces[dk].name === newName) {
                        nameExists = true
                        newName = baseName + " " + counter
                        counter++
                        break
                    }
                }
            }
        }

        // Name the trailing auto-created workspace to claim it
        root.dispatcher.focusAndSetWorkspaceName(outputName, lastIndex, newName)
        Logger.i("NiriWSM", "Added workspace on", outputName)

        // Unfreeze model after commands complete
        root.dispatcher.whenDone(function() {
            root.editing = false
        })
    }

    function handleSaveLayout() {
        if (!root.service) return
        root.service.saveCurrentLayout()
        ToastService.showNotice("Niri Workspace Manager", "Saved to profile \"" + (root.persistence?.activeProfile ?? "Default") + "\"", "stack-2")
    }

    function handleRestoreLayout() {
        if (!root.service) return
        root.service.restoreLayout()
    }

    // --- Panel UI ---

    Item {
        id: panelContainer
        anchors.fill: parent

        ColumnLayout {
            id: panelContent
            anchors {
                fill: parent
                margins: Style.marginL
            }
            spacing: Style.marginL

            // --- Title ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NIcon {
                    icon: "stack-2"
                    color: Color.mPrimary
                    pointSize: Style.fontSizeXL
                    Layout.alignment: Qt.AlignVCenter
                }

                NText {
                    text: "Niri Workspace Manager"
                    pointSize: Style.fontSizeXL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                NIconButton {
                    icon: "settings"
                    tooltipText: "Plugin Settings"
                    onClicked: {
                        if (pluginApi?.manifest) {
                            BarService.openPluginSettings(
                                pluginApi.panelOpenScreen,
                                pluginApi.manifest
                            )
                        }
                    }
                }
            }

            // --- Profile section ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NText {
                    text: "Profiles"
                    pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                }

                NText {
                    text: "Save and restore workspace layouts"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                ProfileSelector {
                    pluginApi: root.pluginApi
                    persistence: root.persistence
                    service: root.service
                    Layout.fillWidth: true

                    onProfileSwitched: function(name) {
                        root.handleRestoreLayout()
                    }
                }

                NIconButton {
                    icon: "device-floppy"
                    tooltipText: "Save profile"
                    onClicked: root.handleSaveLayout()
                }

                NIconButton {
                    icon: "arrow-back-up"
                    tooltipText: "Restore profile"
                    onClicked: root.handleRestoreLayout()
                }
            }

            // --- Layout section ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NText {
                    text: "Layout"
                    pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                }

                NText {
                    text: "Drag, rename, and manage workspaces across monitors"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }
            }

            // --- Workspace list ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Color.mSurfaceVariant
                radius: Style.radiusL

                NScrollView {
                    id: workspaceScrollView
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    horizontalPolicy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: workspaceScrollView.availableWidth
                        spacing: Style.marginL

                        // Not ready message
                        NText {
                            visible: !root.isReady
                            text: "Plugin not ready or not on Niri"
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurfaceVariant
                            Layout.alignment: Qt.AlignHCenter
                        }

                        // Output groups
                        Repeater {
                            id: outputGroupRepeater
                            model: root.workspacesByOutput

                            OutputGroup {
                                required property var modelData
                                Layout.fillWidth: true

                                pluginApi: root.pluginApi
                                dispatcher: root.dispatcher
                                outputName: modelData.output
                                workspaces: modelData.workspaces
                                outputAliases: root.outputAliases
                                dragCoordRoot: panelContainer

                                // Pass panel drag state
                                panelDragActive: root.panelDragActive
                                panelDragTargetOutput: root.panelDragTargetOutput
                                panelDragTargetInsertIndex: root.panelDragTargetInsertIndex
                                panelDragSourceOutput: root.panelDragSourceOutput
                                panelDragSourceModelIndex: root.panelDragSourceModelIndex

                                onWorkspaceNameChanged: function(index, name, outputName) {
                                    root.handleNameChange(index, name, outputName)
                                }
                                onWorkspaceRemoveRequested: function(index, outputName) {
                                    root.handleRemoveWorkspace(index, outputName)
                                }
                                onWorkspaceAddRequested: function(outputName) {
                                    root.handleAddWorkspace(outputName)
                                }
                                onEditingChanged: function(isEditing) {
                                    root.editing = isEditing
                                }
                                onWorkspacePanelDragStarted: function(wsData, outputName, modelIndex, gx, gy) {
                                    root.startPanelDrag(wsData, outputName, modelIndex, gx, gy)
                                }
                                onWorkspacePanelDragMoved: function(gx, gy) {
                                    root.updatePanelDrag(gx, gy)
                                }
                                onWorkspacePanelDragEnded: function() { root.endPanelDrag() }
                            }
                        }
                    }
                }
            }

            // --- Footer ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM
                visible: root.service?.hasUnsavedChanges ?? false

                NText {
                    text: "Unsaved changes"
                    pointSize: Style.fontSizeS
                    color: Color.mError
                    font.weight: Font.Medium
                }

                Item { Layout.fillWidth: true }
            }
        }

        // Floating drag proxy
        Rectangle {
            id: dragProxy
            visible: root.panelDragActive
            x: root.panelDragProxyX
            y: root.panelDragProxyY
            z: 1000
            width: Math.round(280 * Style.uiScaleRatio)
            height: Style.baseWidgetSize + Style.margin2S
            color: Color.mSurface
            radius: Style.radiusM
            opacity: 0.92
            border.color: Color.mPrimary
            border.width: Style.borderS

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Style.marginM
                    rightMargin: Style.marginM
                }
                spacing: Style.marginM

                // Grip icon
                ColumnLayout {
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

                // Index badge
                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: Style.radiusS
                    color: Color.mSurfaceVariant
                    NText {
                        anchors.centerIn: parent
                        text: String(root.panelDragData?.index ?? "")
                        pointSize: Style.fontSizeXS
                        font.weight: Font.Bold
                        color: Color.mOnSurfaceVariant
                    }
                }

                // Workspace name
                NText {
                    Layout.fillWidth: true
                    text: root.panelDragData?.name || "(unnamed)"
                    pointSize: Style.fontSizeM
                    font.weight: root.panelDragData?.name ? Font.Medium : Font.Normal
                    color: root.panelDragData?.name ? Color.mOnSurface : Color.mOnSurfaceVariant
                    font.italic: !root.panelDragData?.name
                    elide: Text.ElideRight
                }
            }
        }
    }
}
