import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    spacing: Style.marginL
    width: 560

    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})
    readonly property var settings: pluginApi?.pluginSettings ?? ({})

    // --- Local edit state ---
    property bool editRestoreOnStartup: settings.restoreOnStartup ?? defaults.restoreOnStartup ?? true
    property bool editAutoAssign: settings.autoAssign ?? defaults.autoAssign ?? false
    property string editStartupProfile: settings.startupProfile ?? defaults.startupProfile ?? "Default"

    readonly property var persistence: pluginApi?.mainInstance?.persistence ?? null
    readonly property var profileNames: {
        if (!root.persistence) return ["Default"]
        return root.persistence.listProfileNames()
    }

    // --- Required: called by settings dialog on Save ---
    function saveSettings() {
        if (!pluginApi) {
            Logger.e("NiriWSM", "Cannot save: pluginApi is null")
            return
        }

        pluginApi.pluginSettings.restoreOnStartup = root.editRestoreOnStartup
        pluginApi.pluginSettings.autoAssign = root.editAutoAssign
        pluginApi.pluginSettings.startupProfile = root.editStartupProfile
        pluginApi.saveSettings()

        Logger.i("NiriWSM", "Settings saved")
    }

    // --- UI ---

    NLabel {
        label: "Behavior"
    }

    NBox {
        Layout.fillWidth: true
        implicitHeight: settingsSection.implicitHeight + Style.marginXL

        ColumnLayout {
            id: settingsSection
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Style.marginM
            }
            spacing: Style.marginM

            NToggle {
                Layout.fillWidth: true
                label: "Restore on startup"
                description: "Re-apply the startup profile layout when Noctalia starts"
                checked: root.editRestoreOnStartup
                onToggled: function(checked) { root.editRestoreOnStartup = checked }
            }

            NComboBox {
                Layout.fillWidth: true
                label: "Startup profile"
                description: "Which profile to restore on startup"
                enabled: root.editRestoreOnStartup
                model: root.profileNames.map(function(name) { return { key: name, name: name } })
                currentKey: root.editStartupProfile
                onSelected: function(key) { root.editStartupProfile = key }
            }

            NToggle {
                Layout.fillWidth: true
                label: "Auto-assign windows"
                description: "Move new windows to the workspace where that app was last seen"
                checked: root.editAutoAssign
                onToggled: function(checked) { root.editAutoAssign = checked }
            }
        }
    }
}
