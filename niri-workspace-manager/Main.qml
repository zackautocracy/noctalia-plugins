import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import "services"

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var pluginApi: null

    // --- Niri guard ---
    readonly property bool isNiri: CompositorService.isNiri
    readonly property bool ready: root.isNiri && root.pluginApi !== null

    // --- Settings with cascading defaults ---
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})
    readonly property var settings: pluginApi?.pluginSettings ?? ({})
    readonly property bool restoreOnStartup: settings.restoreOnStartup ?? defaults.restoreOnStartup ?? true
    readonly property bool autoAssign: settings.autoAssign ?? defaults.autoAssign ?? false
    readonly property string startupProfile: settings.startupProfile ?? defaults.startupProfile ?? "Default"

    NiriDispatcher {
        id: niriDispatcher
    }

    PersistenceService {
        id: persistence
        pluginApi: root.pluginApi
    }

    // Expose to other components via mainInstance
    readonly property alias dispatcher: niriDispatcher
    readonly property alias persistence: persistence

    AutoAssignService {
        id: autoAssigner
        pluginApi: root.pluginApi
        dispatcher: niriDispatcher
        persistence: persistence
        enabled: root.ready && root.autoAssign
    }

    readonly property alias autoAssigner: autoAssigner

    // --- Auto-detected output display names ---
    property var detectedOutputNames: ({})

    Process {
        id: outputInfoProc
        command: ["niri", "msg", "-j", "outputs"]
        running: root.ready

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text)
                    var names = {}
                    for (var connector in data) {
                        var info = data[connector]
                        var make = info.make ?? ""
                        var model = info.model ?? ""
                        // Skip invalid/unknown vendors
                        if (make.toLowerCase().indexOf("invalid") !== -1 || model.startsWith("0x")) {
                            continue
                        }
                        // Use model name, or "Make Model" if model is too short
                        if (model && model.length > 2) {
                            names[connector] = model
                        } else if (make) {
                            names[connector] = make
                        }
                    }
                    root.detectedOutputNames = names
                    Logger.i("NiriWSM", "Detected output names:", JSON.stringify(names))
                } catch (e) {
                    Logger.w("NiriWSM", "Failed to parse output info:", e)
                }
            }
        }
    }

    // --- Suppress model rebuild during restore ---
    property bool restoringLayout: false

    // --- Startup guard: don't check unsaved until initial load/restore completes ---
    property bool initialized: false

    // --- Unsaved changes tracking (for bar widget indicator) ---
    property bool hasUnsavedChanges: false

    // Build a fingerprint of current workspace structure (names + order per output)
    function currentWorkspaceFingerprint() {
        var result = {}
        var workspaces = CompositorService.workspaces
        for (var i = 0; i < workspaces.count; i++) {
            var ws = workspaces.get(i)
            if (!ws.name) continue
            var output = ws.output ?? "unknown"
            if (!result[output]) result[output] = []
            result[output].push(ws.name)
        }
        // Sort output keys for stable comparison
        var sorted = {}
        var keys = Object.keys(result).sort()
        for (var k = 0; k < keys.length; k++) {
            sorted[keys[k]] = result[keys[k]]
        }
        return JSON.stringify(sorted)
    }

    // Build fingerprint from saved profile data
    function savedWorkspaceFingerprint() {
        var profile = persistence.getActiveProfile()
        Logger.i("NiriWSM", "savedFingerprint: activeProfile=", persistence.activeProfile,
                  "profile=", profile ? "exists" : "null",
                  "profileKeys=", JSON.stringify(Object.keys(persistence.profiles ?? {})))
        if (!profile || !profile.outputs) return "{}"
        var result = {}
        var outputs = profile.outputs
        for (var outputName in outputs) {
            var wsList = outputs[outputName].workspaces ?? []
            if (wsList.length === 0) continue
            result[outputName] = []
            for (var i = 0; i < wsList.length; i++) {
                if (wsList[i].name) result[outputName].push(wsList[i].name)
            }
        }
        var sorted = {}
        var keys = Object.keys(result).sort()
        for (var k = 0; k < keys.length; k++) {
            sorted[keys[k]] = result[keys[k]]
        }
        return JSON.stringify(sorted)
    }

    function checkUnsavedChanges() {
        var current = currentWorkspaceFingerprint()
        var saved = savedWorkspaceFingerprint()
        Logger.i("NiriWSM", "Fingerprint current:", current)
        Logger.i("NiriWSM", "Fingerprint  saved:", saved)
        Logger.i("NiriWSM", "Match:", current === saved)
        root.hasUnsavedChanges = (current !== saved)
    }

    // --- Capture current workspace layout ---
    function captureCurrentLayout() {
        var outputs = {}
        var columns = []
        var appAssignments = {}
        var workspaces = CompositorService.workspaces

        for (var i = 0; i < workspaces.count; i++) {
            var ws = workspaces.get(i)
            var output = ws.output ?? "unknown"

            if (!outputs[output]) {
                outputs[output] = { workspaces: [] }
            }

            // Only save named workspaces (skip unnamed/auto-created)
            if (ws.name) {
                outputs[output].workspaces.push({
                    index: ws.idx ?? (i + 1),
                    name: ws.name
                })
            }

            // Only capture column data for NAMED workspaces
            if (!ws.name) continue
            var windows = CompositorService.getWindowsForWorkspace(ws.id)
            if (windows.length > 0) {
                var appIds = []
                for (var j = 0; j < windows.length; j++) {
                    var appId = windows[j].appId ?? ""
                    if (appId && appIds.indexOf(appId) === -1) {
                        appIds.push(appId)
                    }
                }
                if (appIds.length > 0) {
                    columns.push({
                        workspaceName: ws.name ?? "",
                        output: output,
                        apps: appIds
                    })
                }
            }

            // Update app assignments (per-profile)
            for (var k = 0; k < windows.length; k++) {
                var win = windows[k]
                if (win.appId) {
                    appAssignments[win.appId] = {
                        workspace: ws.name ?? "",
                        output: output
                    }
                }
            }
        }

        return { outputs: outputs, columns: columns, appAssignments: appAssignments }
    }

    function saveCurrentLayout() {
        if (!root.ready) return
        var layout = captureCurrentLayout()
        persistence.saveCurrentLayout(layout)
        root.hasUnsavedChanges = false
        Logger.i("NiriWSM", "Layout saved to profile:", persistence.activeProfile)
    }

    function restoreLayout() {
        if (!root.ready) return
        var profile = persistence.getActiveProfile()
        if (!profile) {
            Logger.w("NiriWSM", "No active profile to restore")
            ToastService.showError("Niri Workspace Manager", "No profile to restore")
            return
        }

        var profileName = persistence.activeProfile
        Logger.i("NiriWSM", "Restoring profile:", profileName)

        // Guard: prevent change detection from firing during restore
        root.restoringLayout = true

        var outputs = profile.outputs ?? {}

        // Build map of existing named workspaces: name → {output, idx}
        var existingByName = {}
        var workspaces = CompositorService.workspaces
        for (var w = 0; w < workspaces.count; w++) {
            var existing = workspaces.get(w)
            if (existing.name) {
                existingByName[existing.name] = {
                    output: existing.output,
                    idx: existing.idx
                }
            }
        }

        // Track per-output changes for summary
        var outputChanges = {} // outputName → count of actual changes
        var totalChanges = 0

        for (var outputName in outputs) {
            var savedList = outputs[outputName].workspaces ?? []
            var changes = 0

            for (var i = 0; i < savedList.length; i++) {
                var ws = savedList[i]
                if (!ws.name) continue
                var cur = existingByName[ws.name]

                if (!cur) {
                    // Workspace doesn't exist — create it
                    niriDispatcher.focusAndSetWorkspaceName(
                        outputName, ws.index, ws.name)
                    changes++
                } else {
                    // Move to correct output if needed
                    if (cur.output !== outputName) {
                        niriDispatcher.moveWorkspaceToMonitor(
                            niriDispatcher.refByName(ws.name), outputName)
                        changes++
                    }
                    // Reorder to correct index if needed
                    if (cur.idx !== ws.index || cur.output !== outputName) {
                        niriDispatcher.moveWorkspaceToIndex(
                            niriDispatcher.refByName(ws.name), ws.index)
                        changes++
                    }
                }
            }

            if (changes > 0) {
                outputChanges[outputName] = savedList.length
                totalChanges += changes
            }
        }

        niriDispatcher.whenDone(function() {
            root.restoringLayout = false
            root.initialized = true
            root.checkUnsavedChanges()

            var description
            if (totalChanges === 0) {
                description = "Profile \"" + profileName + "\" is already up to date"
            } else {
                var parts = []
                for (var out in outputChanges) {
                    parts.push(outputChanges[out] + " on " + out)
                }
                description = "Restored profile \"" + profileName + "\": " + parts.join(", ")
            }
            ToastService.showNotice("Niri Workspace Manager", description, "stack-2")
            Logger.i("NiriWSM", description)
        })
    }

    // --- React to compositor changes ---
    Connections {
        target: CompositorService
        enabled: root.ready

        function onWorkspaceChanged() {
            if (root.restoringLayout || !root.initialized) return
            root.checkUnsavedChanges()
        }

        function onWindowListChanged() {
            if (root.restoringLayout) return
            if (root.autoAssign) {
                autoAssigner.handleWindowListChanged()
            }
        }
    }

    Component.onCompleted: {
        if (!root.isNiri) {
            Logger.w("NiriWSM", "Not running on Niri compositor - plugin disabled")
            return
        }
        Logger.i("NiriWSM", "Plugin loaded, Niri detected")
        persistence.load()

        persistence.stateLoaded.connect(function() {
            // Switch to startup profile if configured
            if (root.startupProfile && root.startupProfile !== persistence.activeProfile) {
                persistence.switchProfile(root.startupProfile)
            }

            if (root.autoAssign) {
                autoAssigner.initialize()
            }
            if (!root.restoreOnStartup) {
                root.initialized = true
            }
        })

        if (root.restoreOnStartup) {
            // Delay restore to let CompositorService populate
            restoreDelayTimer.start()
        }
    }

    Timer {
        id: restoreDelayTimer
        interval: 2000
        repeat: false
        onTriggered: {
            Logger.i("NiriWSM", "Startup restore triggered")
            root.restoreLayout()
        }
    }

    IpcHandler {
        target: "plugin:niri-workspace-manager"

        function togglePanel() {
            if (!root.pluginApi) return
            root.pluginApi.withCurrentScreen(function(screen) {
                root.pluginApi.togglePanel(screen)
            })
        }

        function saveLayout() {
            if (!root.ready) return
            root.saveCurrentLayout()
            ToastService.showNotice("Niri Workspace Manager", "Saved to profile \"" + persistence.activeProfile + "\"", "stack-2")
        }

        function restoreLayout() {
            if (!root.ready) return
            root.restoreLayout()
        }

        function switchProfile(name: string) {
            if (!root.ready || !name) return
            var trimmed = name.trim()

            if (persistence.switchProfile(trimmed)) {
                root.restoreLayout()
                ToastService.showNotice("Niri Workspace Manager", "Switched to profile \"" + trimmed + "\"", "stack-2")
            } else {
                ToastService.showError("Niri Workspace Manager", "Profile \"" + trimmed + "\" not found")
            }
        }

        function listProfiles() {
            if (!root.ready) return
            var names = persistence.listProfileNames()
            Logger.i("NiriWSM", "Profiles:", JSON.stringify(names))
        }
    }
}
