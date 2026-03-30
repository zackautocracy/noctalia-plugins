import QtQuick
import Quickshell.Io
import qs.Commons

Item {
    id: root

    visible: false
    width: 0
    height: 0

    // Reusable process for fire-and-forget niri commands
    Process {
        id: niriProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    Logger.w("NiriWSM", "niri stderr:", text.trim())
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                Logger.e("NiriWSM", "niri exited with code:", exitCode)
        }
    }

    // Queue for commands (Process can only run one at a time)
    property var commandQueue: []
    property bool running: false

    function enqueue(args) {
        root.commandQueue.push(args)
        if (!root.running)
            runNext()
    }

    // Enqueue a callback to run after all preceding commands complete
    function whenDone(callback) {
        root.commandQueue.push(callback)
        if (!root.running)
            runNext()
    }

    function runNext() {
        if (root.commandQueue.length === 0) {
            root.running = false
            return
        }
        root.running = true
        var next = root.commandQueue.shift()

        // If it's a function callback, execute and continue
        if (typeof next === "function") {
            next()
            Qt.callLater(root.runNext)
            return
        }

        niriProc.command = ["niri", "msg", "action"].concat(next)
        Logger.i("NiriWSM", "dispatch:", niriProc.command.join(" "))
        niriProc.running = true
    }

    Connections {
        target: niriProc
        function onExited() { Qt.callLater(root.runNext) }
    }

    // --- Workspace name operations ---

    function setWorkspaceName(workspaceRef, name) {
        enqueue(["set-workspace-name", "--workspace", String(workspaceRef), String(name)])
    }

    // Focus a monitor then set the name of a workspace by index (for unnamed workspaces)
    function focusAndSetWorkspaceName(outputName, workspaceIndex, name) {
        enqueue(["focus-monitor", String(outputName)])
        enqueue(["focus-workspace", String(workspaceIndex)])
        enqueue(["set-workspace-name", String(name)])
    }

    function unsetWorkspaceName(workspaceRef) {
        enqueue(["unset-workspace-name", String(workspaceRef)])
    }

    // Remove a workspace by unsetting its name
    function removeWorkspace(outputName, workspaceIndex, workspaceName) {
        if (workspaceName) {
            // Named: use direct name reference (unambiguous, no focus needed)
            enqueue(["unset-workspace-name", String(workspaceName)])
        } else {
            // Unnamed: must focus first
            enqueue(["focus-monitor", String(outputName)])
            enqueue(["focus-workspace", String(workspaceIndex)])
            enqueue(["unset-workspace-name"])
        }
    }

    // --- Workspace movement ---

    function moveWorkspaceToMonitor(workspaceRef, outputName) {
        enqueue(["move-workspace-to-monitor", "--reference", String(workspaceRef), String(outputName)])
    }

    // Focus source monitor + workspace, then move to target monitor (for unnamed workspaces)
    function focusAndMoveWorkspaceToMonitor(sourceOutput, workspaceIndex, targetOutput, targetIndex) {
        enqueue(["focus-monitor", String(sourceOutput)])
        enqueue(["focus-workspace", String(workspaceIndex)])
        enqueue(["move-workspace-to-monitor", String(targetOutput)])
        if (targetIndex !== undefined) {
            enqueue(["move-workspace-to-index", String(targetIndex)])
        }
    }

    function moveWorkspaceToIndex(workspaceRef, targetIndex) {
        enqueue(["move-workspace-to-index", "--reference", String(workspaceRef), String(targetIndex)])
    }

    // --- Window movement ---

    function moveWindowToWorkspace(workspaceRef, windowId) {
        var args = ["move-window-to-workspace", String(workspaceRef)]
        if (windowId !== undefined)
            args = args.concat(["--window-id", String(windowId)])
        enqueue(args)
    }

    // --- Focus operations ---

    function focusWindow(windowId) {
        enqueue(["focus-window", "--id", String(windowId)])
    }

    // --- Helpers ---

    function refByIndex(index) {
        return String(index)
    }

    function refByName(name) {
        return String(name)
    }
}
