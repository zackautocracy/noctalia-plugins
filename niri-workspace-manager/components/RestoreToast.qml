import QtQuick
import qs.Commons

// RestoreToast — multi-step restore progress notification
// v1: Uses ToastService.showNotice() in Main.qml for simple feedback
// v1.1: This component will provide per-step progress display:
//   ✓ Workspace names applied
//   ✓ Outputs reassigned
//   ⟳ Moving columns... (3/5)
//   ✗ telegram — not running

QtObject {
    id: root

    property string profileName: ""
    property var steps: []

    // Future: integrate with Popup or custom overlay for rich progress display
}
