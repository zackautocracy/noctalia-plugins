import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

RowLayout {
    id: root

    property var pluginApi: null
    property var persistence: null
    property var service: null

    signal profileSwitched(string name)
    signal profileCreated(string name)
    signal profileDeleted(string name)

    spacing: Style.marginS

    readonly property string activeProfile: persistence?.activeProfile ?? "Default"

    // Force model refresh counter for NComboBox binding
    property int _profileRefresh: 0

    // Refresh profile list when persistence loads state from disk
    Connections {
        target: root.persistence
        function onStateLoaded() { root._profileRefresh++ }
    }

    // Also refresh on creation (stateLoaded may have already fired)
    Component.onCompleted: Qt.callLater(function() { root._profileRefresh++ })

    readonly property var profileNames: {
        // Touch refresh counter to force binding re-evaluation
        var _ = root._profileRefresh
        var p = persistence?.profiles ?? {}
        var keys = Object.keys(p)
        console.log("[ProfileSelector] profileNames refresh #" + _ + " keys:", JSON.stringify(keys))
        return keys
    }

    property bool creatingNew: false
    property string newProfileName: ""

    NIcon {
        icon: "user"
        color: Color.mPrimary
        pointSize: Style.fontSizeXL
        Layout.alignment: Qt.AlignVCenter
    }

    // Profile dropdown
    NComboBox {
        id: profileCombo
        visible: !root.creatingNew
        Layout.fillWidth: true

        model: {
            var items = []
            for (var i = 0; i < root.profileNames.length; i++) {
                items.push({ key: root.profileNames[i], name: root.profileNames[i] })
            }
            return items
        }
        currentKey: root.activeProfile

        onSelected: function(key) {
            if (key !== root.activeProfile) {
                if (root.persistence.switchProfile(key)) {
                    root._profileRefresh++
                    root.profileSwitched(key)
                }
            }
        }
    }

    // New profile input
    NTextInput {
        id: newProfileInput
        visible: root.creatingNew
        Layout.fillWidth: true
        placeholderText: "Profile name..."
        text: root.newProfileName
        onTextChanged: root.newProfileName = text

        Keys.onReturnPressed: root.confirmNewProfile()
        Keys.onEscapePressed: root.cancelNewProfile()
    }

    // Track inner input focus to cancel on blur
    Connections {
        target: newProfileInput.inputItem
        function onActiveFocusChanged() {
            if (!newProfileInput.inputItem.activeFocus && root.creatingNew) {
                root.cancelNewProfile()
            }
        }
    }

    // New profile button
    NIconButton {
        icon: root.creatingNew ? "check" : "plus"
        tooltipText: root.creatingNew ? "Confirm" : "New profile"
        onClicked: {
            if (root.creatingNew) {
                root.confirmNewProfile()
            } else {
                root.creatingNew = true
                root.newProfileName = ""
                Qt.callLater(function() { newProfileInput.inputItem.forceActiveFocus() })
            }
        }
    }

    // Cancel / Delete
    NIconButton {
        icon: root.creatingNew ? "x" : "trash"
        visible: root.creatingNew || root.activeProfile !== "Default"
        tooltipText: root.creatingNew ? "Cancel" : "Delete profile"
        onClicked: {
            if (root.creatingNew) {
                root.cancelNewProfile()
            } else {
                root.deleteCurrentProfile()
            }
        }
    }

    function confirmNewProfile() {
        var name = root.newProfileName.trim()
        if (!name) {
            root.cancelNewProfile()
            return
        }

        var layout = root.service?.captureCurrentLayout() ?? { outputs: {}, columns: [] }
        if (root.persistence.createProfile(name, layout)) {
            root._profileRefresh++
            root.profileCreated(name)
            ToastService.showNotice("Niri Workspace Manager", "Profile \"" + name + "\" created", "stack-2")
        } else {
            ToastService.showError("Niri Workspace Manager", "Profile \"" + name + "\" already exists")
        }
        root.creatingNew = false
        root.newProfileName = ""
    }

    function cancelNewProfile() {
        root.creatingNew = false
        root.newProfileName = ""
    }

    function deleteCurrentProfile() {
        var name = root.activeProfile
        if (root.persistence.deleteProfile(name)) {
            root._profileRefresh++
            root.profileDeleted(name)
            root.profileSwitched(root.persistence.activeProfile)
            ToastService.showNotice("Niri Workspace Manager", "Profile \"" + name + "\" deleted", "stack-2")
        }
    }
}
