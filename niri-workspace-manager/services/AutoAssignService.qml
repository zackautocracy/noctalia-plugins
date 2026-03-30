import QtQuick
import qs.Commons
import qs.Services.Compositor

QtObject {
    id: root

    required property var pluginApi
    required property var dispatcher
    required property var persistence
    property bool enabled: false

    // Track known window IDs to detect new windows
    property var knownWindowIds: ({})

    readonly property var windowList: CompositorService.windows

    function initialize() {
        // Snapshot all currently known window IDs
        root.knownWindowIds = {}
        for (var i = 0; i < windowList.count; i++) {
            var win = windowList.get(i)
            if (win.id !== undefined) {
                root.knownWindowIds[win.id] = true
            }
        }
        Logger.i("NiriWSM", "AutoAssign initialized with", Object.keys(root.knownWindowIds).length, "windows")
    }

    function handleWindowListChanged() {
        if (!root.enabled) return

        var newWindows = []

        for (var i = 0; i < windowList.count; i++) {
            var win = windowList.get(i)
            var winId = win.id
            if (winId !== undefined && !root.knownWindowIds[winId]) {
                newWindows.push(win)
                root.knownWindowIds[winId] = true
            }
        }

        // Clean up removed windows from tracking
        var currentIds = {}
        for (var j = 0; j < windowList.count; j++) {
            var w = windowList.get(j)
            if (w.id !== undefined) {
                currentIds[w.id] = true
            }
        }
        root.knownWindowIds = currentIds

        // Process new windows
        for (var k = 0; k < newWindows.length; k++) {
            processNewWindow(newWindows[k])
        }
    }

    function processNewWindow(win) {
        var appId = win.appId ?? ""
        if (!appId) return

        var assignment = root.persistence.getAppAssignment(appId)
        if (!assignment) {
            Logger.d("NiriWSM", "No assignment for app:", appId)
            return
        }

        var targetWorkspace = assignment.workspace
        if (!targetWorkspace) return

        Logger.i("NiriWSM", "Auto-assigning", appId, "to workspace:", targetWorkspace)

        // Focus the new window first, then move it
        root.dispatcher.focusWindow(win.id)

        // Small delay to let focus settle
        Qt.callLater(function() {
            var ref = root.dispatcher.refByName(targetWorkspace)
            root.dispatcher.moveWindowToWorkspace(ref)
        })
    }
}
