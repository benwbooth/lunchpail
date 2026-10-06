import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

LbDialog {
    id: dialog
    property var ai: null
    property bool assistantModel: false
    property bool pending: false
    property bool microphoneConsent: false
    signal ready()
    signal declined()
    modal: true
    anchors.centerIn: parent
    width: Math.min(540, parent ? parent.width - 40 : 540)
    closePolicy: Popup.NoAutoClose
    onRejected: decline()
    title: "Install a model?"
    readonly property var modelInfo: {
        if (!ai) return ({})
        const id = assistantModel ? (ai.assistant_model || "qwen3-4b") : (ai.speech_model || "sherpa-zipformer-en")
        return JSON.parse(ai.models_json || "[]").find(m => m.id === id) || ({})
    }
    function request(assistant, microphone) {
        assistantModel = assistant
        microphoneConsent = microphone
        pending = false
        if (ai && (assistant ? ai.assistant_ready : ai.speech_ready)) { ready(); return }
        open()
    }
    function install() {
        if (!ai || ai.busy) return
        pending = true
        ai.install_for(assistantModel)
    }
    function decline() {
        const wasPending = pending
        pending = false
        if (wasPending && ai && ai.busy) ai.cancel()
        close()
        declined()
    }
    Connections {
        target: dialog.ai
        ignoreUnknownSignals: true
        function onOperation_finished(success) {
            if (!dialog.pending) return
            dialog.pending = false
            if (success && (dialog.assistantModel ? dialog.ai.assistant_ready : dialog.ai.speech_ready)) {
                dialog.close()
                dialog.ready()
            }
        }
    }
    contentItem: ColumnLayout {
        spacing: 16
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: (dialog.assistantModel ? "Install the local assistant model" : "Install the local voice model")
                  + (dialog.modelInfo.name ? " (" + dialog.modelInfo.name + ")" : "") + "?"
                  + (dialog.modelInfo.bytes ? " Download: " + (dialog.modelInfo.bytes / 1e9 < 1 ? Math.ceil(dialog.modelInfo.bytes / 1e6) + " MB" : (dialog.modelInfo.bytes / 1e9).toFixed(1) + " GB") + "." : "")
                  + " Lunchpail handles installation and CPU/GPU selection automatically."
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "The download needs internet. Speech and prompts stay on this device."
                  + (dialog.microphoneConsent ? " After installation, the microphone will listen locally for requests while you browse Lunchpail in normal or Couch mode. You can turn it off at any time. Transcribed requests go to your selected AI provider." : "")
        }
        ProgressBar { Layout.fillWidth: true; visible: dialog.pending; value: dialog.ai ? dialog.ai.progress : 0 }
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: dialog.pending || (dialog.ai && !dialog.ai.busy); text: dialog.ai ? dialog.ai.status : "" }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            LbButton { objectName: "installModelNo"; text: dialog.pending ? "Cancel" : "No"; onClicked: dialog.decline() }
            LbButton { objectName: "installModelYes"; text: "Yes"; enabled: dialog.ai && !dialog.ai.busy; visible: !dialog.pending; onClicked: dialog.install() }
        }
    }
}
