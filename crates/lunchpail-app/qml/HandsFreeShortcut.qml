import QtQuick

Shortcut {
    required property var desktopController
    required property var couchController
    property bool couchModeActive: false
    sequence: "F4"
    // Remain available from modal settings/model dialogs, but not other apps.
    context: Qt.ApplicationShortcut
    autoRepeat: false
    onActivated: {
        if (couchModeActive) couchController.toggleHandsFree()
        else desktopController.toggleHandsFree()
    }
}
