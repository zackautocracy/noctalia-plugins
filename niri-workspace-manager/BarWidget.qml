import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // --- Per-screen bar properties ---
    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    // --- Access Main.qml service ---
    readonly property var service: pluginApi?.mainInstance
    readonly property bool isNiri: service?.isNiri ?? false

    // --- Sizing ---
    readonly property real contentWidth: isBarVertical
        ? capsuleHeight
        : Math.round(content.implicitWidth + Style.marginM * 2)
    readonly property real contentHeight: isBarVertical
        ? Math.round(content.implicitHeight + Style.marginM * 2)
        : capsuleHeight

    visible: root.isNiri
    implicitWidth: root.isNiri ? contentWidth : 0
    implicitHeight: root.isNiri ? contentHeight : 0

    // --- Visual capsule ---
    Rectangle {
        id: visualCapsule

        visible: root.isNiri
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Style.marginS
            visible: !root.isBarVertical

            NIcon {
                icon: "stack-2"
                pointSize: Math.max(1, Math.round(root.barFontSize * 1.15))
                applyUiScale: false
                color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
            }

            // Unsaved changes dot
            Rectangle {
                visible: root.service?.hasUnsavedChanges ?? false
                width: 6
                height: 6
                radius: 3
                color: Color.mError
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ColumnLayout {
            id: verticalContent
            anchors.centerIn: parent
            spacing: Style.marginXS
            visible: root.isBarVertical

            NIcon {
                icon: "stack-2"
                pointSize: Math.max(1, Math.round(root.barFontSize))
                applyUiScale: false
                color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
            }

            // Unsaved changes dot
            Rectangle {
                visible: root.service?.hasUnsavedChanges ?? false
                width: 6
                height: 6
                radius: 3
                color: Color.mError
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // --- Context menu ---
    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": pluginApi?.tr("menu.settings") || "Settings",
                "action": "settings",
                "icon": "settings"
            }
        ]

        onTriggered: function(action) {
            contextMenu.close()
            PanelService.closeContextMenu(screen)

            if (action === "settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest)
            }
        }
    }

    // --- Mouse interaction ---
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: root.isNiri
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onEntered: {
            TooltipService.show(root, "Niri Workspace Manager", BarService.getTooltipDirection())
        }

        onExited: {
            TooltipService.hide(root)
        }

        onPressed: {
            TooltipService.hide(root)
        }

        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (pluginApi) {
                    pluginApi.togglePanel(root.screen, root)
                }
            } else if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen)
            }
        }
    }
}
