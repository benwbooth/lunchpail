import QtQuick

Item {
    id: controller
    required property var speech
    property bool allowed: false
    property bool wakeWordRequired: true
    // A wake-word listener can keep previews audible between commands. In
    // open conversation mode, suppress them for the whole capture session so
    // the app cannot mistake its own trailer dialogue for a user request.
    readonly property bool capturingCommand: speech.listening
        && (!speech.hands_free || !wakeWordRequired || speech.awake)
    signal searchRequested(string text)
    function reconcile() {
        if (allowed && speech.ready && !speech.busy && !speech.faulted)
            speech.start_hands_free()
        else if (!allowed && speech.hands_free) speech.cancel()
    }
    onAllowedChanged: reconcile()
    Timer { interval: 400; repeat: true; running: controller.allowed; onTriggered: controller.reconcile() }
    Timer { interval: 50; repeat: true; running: controller.speech.hands_free && controller.speech.busy; onTriggered: controller.speech.poll() }
    Connections {
        target: controller.speech
        ignoreUnknownSignals: true
        function onSearch_requested(text) {
            if (controller.allowed && !controller.speech.faulted) controller.searchRequested(text)
        }
    }
}
