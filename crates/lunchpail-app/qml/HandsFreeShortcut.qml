import QtQuick

Shortcut {
    required property var desktopController
    required property var couchController
    property bool couchModeActive: false
    property var setupControllers: []
    sequence: "F4"
    // Remain available from modal settings/model dialogs, but not other apps.
    context: Qt.ApplicationShortcut
    autoRepeat: false
    onActivated: {
        // Setup can be started from Settings as well as either mode's button.
        // F4 must revoke that pending consent, not start a second setup flow.
        for (const setup of setupControllers) {
            if (setup && setup.pending) { setup.cancel(); return }
        }
        if (couchModeActive) couchController.toggleHandsFree()
        else desktopController.toggleHandsFree()
    }
}
