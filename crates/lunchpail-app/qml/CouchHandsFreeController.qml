import QtQuick

Item {
    id: controller
    required property var speech
    property bool allowed: false
    // The wake-word listener stays open between commands. Only an actual
    // command (or push-to-talk capture) should suppress the user's audio.
    readonly property bool capturingCommand: speech.listening
        && (!speech.hands_free || speech.awake)
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
