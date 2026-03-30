import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property var pluginApi

    readonly property string stateFilePath: {
        var dir = pluginApi?.pluginDir ?? ""
        return dir ? dir + "/state.json" : ""
    }

    // --- Current state ---
    property string activeProfile: "Default"
    property var profiles: ({})
    property int stateVersion: 3

    // --- Signals ---
    signal stateLoaded()
    signal stateSaved()
    signal profileSwitched(string profileName)

    // --- File I/O ---

    FileView {
        id: stateFile
        path: root.stateFilePath
        watchChanges: false
    }

    // Track whether we've loaded state yet
    property bool _loaded: false

    function load() {
        if (!root.stateFilePath) {
            Logger.w("NiriWSM", "No plugin dir — cannot load state")
            initDefaults()
            return
        }

        // FileView loads asynchronously — check if content is ready
        var content = stateFile.text()
        if (content && content.length > 0) {
            parseStateContent(content)
        } else {
            // Content not ready yet — wait for async load
            Logger.i("NiriWSM", "Waiting for FileView to load state.json...")
            loadFallbackTimer.start()
        }
    }

    // React when FileView finishes loading the file
    Connections {
        target: stateFile
        enabled: !root._loaded
        function onTextChanged() {
            var content = stateFile.text()
            if (content && content.length > 0) {
                root.parseStateContent(content)
            }
        }
    }

    // Fallback: if FileView never loads (file doesn't exist), init defaults
    Timer {
        id: loadFallbackTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!root._loaded) {
                Logger.i("NiriWSM", "FileView load timed out — initializing defaults")
                root.initDefaults()
                root._loaded = true
            }
        }
    }

    function parseStateContent(content) {
        if (root._loaded) return
        root._loaded = true

        try {
            var data = JSON.parse(content)
            root.activeProfile = data.activeProfile ?? "Default"

            var profiles = data.profiles ?? {}
            if (!profiles["Default"]) {
                profiles["Default"] = makeEmptyProfile()
            }

            // Ensure all profiles have appAssignments
            for (var p in profiles) {
                if (!profiles[p].appAssignments) {
                    profiles[p].appAssignments = {}
                }
            }

            root.profiles = profiles
            root.stateVersion = 3

            Logger.i("NiriWSM", "State loaded. Active profile:", root.activeProfile,
                      "Profiles:", Object.keys(root.profiles).length,
                      "Profile names:", JSON.stringify(Object.keys(root.profiles)))
            root.stateLoaded()
        } catch (error) {
            Logger.e("NiriWSM", "Failed to parse state.json:", error)
            initDefaults()
        }
    }

    function save() {
        if (!root.stateFilePath) {
            Logger.e("NiriWSM", "No plugin dir — cannot save state")
            return
        }

        var data = {
            version: root.stateVersion,
            activeProfile: root.activeProfile,
            profiles: root.profiles
        }

        try {
            stateFile.setText(JSON.stringify(data, null, 2))
            Logger.d("NiriWSM", "State saved")
            root.stateSaved()
        } catch (error) {
            Logger.e("NiriWSM", "Failed to save state.json:", error)
        }
    }

    // --- Profile CRUD ---

    function getActiveProfile() {
        return root.profiles[root.activeProfile] ?? null
    }

    function saveCurrentLayout(workspaceData) {
        var profile = getActiveProfile()
        if (!profile) {
            Logger.e("NiriWSM", "No active profile to save to")
            return
        }

        profile.savedAt = new Date().toISOString()
        profile.outputs = workspaceData.outputs ?? {}
        profile.columns = workspaceData.columns ?? []
        if (workspaceData.appAssignments) {
            profile.appAssignments = workspaceData.appAssignments
        }

        // Reassign to trigger binding updates (in-place mutation doesn't)
        var tmp = root.profiles
        tmp[root.activeProfile] = profile
        root.profiles = tmp
        save()
    }

    function createProfile(name, workspaceData) {
        if (!name || name.trim() === "") return false
        name = name.trim()

        if (root.profiles[name]) {
            Logger.w("NiriWSM", "Profile already exists:", name)
            return false
        }

        // Reassign to trigger binding updates
        var tmp = root.profiles
        tmp[name] = {
            savedAt: new Date().toISOString(),
            outputs: workspaceData?.outputs ?? {},
            columns: workspaceData?.columns ?? [],
            appAssignments: workspaceData?.appAssignments ?? {}
        }
        root.profiles = tmp

        root.activeProfile = name
        save()
        root.profileSwitched(name)
        Logger.i("NiriWSM", "Profile created:", name)
        return true
    }

    function deleteProfile(name) {
        if (name === "Default") {
            Logger.w("NiriWSM", "Cannot delete Default profile")
            return false
        }
        if (!root.profiles[name]) return false

        // Reassign to trigger binding updates
        var tmp = root.profiles
        delete tmp[name]
        root.profiles = tmp

        if (root.activeProfile === name) {
            root.activeProfile = "Default"
        }

        save()
        Logger.i("NiriWSM", "Profile deleted:", name)
        return true
    }

    function switchProfile(name) {
        if (!root.profiles[name]) {
            Logger.w("NiriWSM", "Profile not found:", name)
            return false
        }
        if (root.activeProfile === name) return true

        root.activeProfile = name
        save()
        root.profileSwitched(name)
        Logger.i("NiriWSM", "Switched to profile:", name)
        return true
    }

    function listProfileNames() {
        return Object.keys(root.profiles)
    }

    // --- Helpers ---

    function initDefaults() {
        root.stateVersion = 3
        root.activeProfile = "Default"
        root.profiles = { "Default": makeEmptyProfile() }
        root.stateLoaded()
    }

    function makeEmptyProfile() {
        return {
            savedAt: new Date().toISOString(),
            outputs: {},
            columns: [],
            appAssignments: {}
        }
    }

    // --- App assignment tracking (per-profile) ---

    function updateAppAssignment(appId, workspaceName, outputName) {
        if (!appId) return
        var profile = getActiveProfile()
        if (!profile) return

        if (!profile.appAssignments) profile.appAssignments = {}
        profile.appAssignments[appId] = {
            workspace: workspaceName,
            output: outputName
        }

        // Reassign to trigger binding updates
        var tmp = root.profiles
        tmp[root.activeProfile] = profile
        root.profiles = tmp
    }

    function getAppAssignment(appId) {
        var profile = getActiveProfile()
        if (!profile || !profile.appAssignments) return null
        return profile.appAssignments[appId] ?? null
    }
}
