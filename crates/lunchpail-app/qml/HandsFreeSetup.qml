import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One consent/readiness sequence for the header, Couch mode and Settings.
Item {
    id: setup
    required property var ai
    property var assistant: null
    property bool pending: false
    readonly property bool ready: !!assistant && !!ai && assistant.ready && ai.speech_ready
    readonly property var installDialog: assistantInstall.visible ? assistantInstall : speechInstall
    readonly property var providerDialog: providerSetup
    signal enabledListening()
    signal stoppedListening()
    signal settingsRequested()
    function toggle() {
        if (pending) { cancel(); return }
        if (ai.hands_free && ready) {
            ai.enable_hands_free(false)
            stoppedListening()
        } else request()
    }
    function request() {
        if (!ai) return
        if (ai.hands_free) ai.enable_hands_free(false)
        stoppedListening()
        pending = true
        if (assistant) assistant.refresh()
        advance()
    }
    function advance() {
        if (!pending) return
        if (!assistant || !assistant.ready) {
            const config = assistant ? JSON.parse(assistant.config_json || "{}") : ({})
            if (assistant && (!config.provider || config.provider === "builtin"))
                assistantInstall.request(true, true)
            else providerSetup.open()
        } else if (!ai.speech_ready) speechInstall.request(false, true)
        else {
            pending = false
            ai.enable_hands_free(true)
            enabledListening()
        }
    }
    function cancel() {
        pending = false
        if (assistantInstall.visible) assistantInstall.decline()
        if (speechInstall.visible) speechInstall.decline()
        providerSetup.close()
    }
    LocalModelInstall {
        id: assistantInstall
        parent: Overlay.overlay
        ai: setup.ai
        purpose: "The assistant microphone needs an assistant to understand requests, as well as a speech model to hear them."
        onReady: {
            if (!setup.pending) return
            if (setup.assistant) setup.assistant.refresh()
            // Avoid looping if an installed model still cannot be selected.
            if (!setup.assistant || !setup.assistant.ready) providerSetup.open()
            else Qt.callLater(setup.advance)
        }
        onDeclined: setup.pending = false
    }
    LocalModelInstall {
        id: speechInstall
        parent: Overlay.overlay
        ai: setup.ai
        purpose: "The assistant microphone also needs local speech recognition."
        onReady: Qt.callLater(setup.advance)
        onDeclined: setup.pending = false
    }
    LbDialog {
        id: providerSetup
        parent: Overlay.overlay
        title: "Set up assistant microphone"
        modal: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: parent
        width: Math.min(520, parent ? parent.width - 40 : 520)
        onRejected: setup.pending = false
        contentItem: ColumnLayout {
            spacing: 16
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: providerSetup.palette.windowText
                text: "Choose an assistant provider and model in AI & voice settings before enabling the microphone. The microphone is off. Any saved request stays in the conversation box until you send it."
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                LbButton { text: "Cancel"; onClicked: setup.cancel() }
                LbButton {
                    text: "AI & voice settings"
                    onClicked: { setup.cancel(); setup.settingsRequested() }
                }
            }
        }
    }
}
