pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: pane
    required property var ai
    property var assistant: null
    property var speechOutput: null
    required property color inkColor
    required property color mutedColor
    required property color accentColor
    property bool advanced: false
    property bool enableVoiceAfterInstall: false
    spacing: 12
    readonly property var catalog: JSON.parse(ai.models_json || "[]")
    readonly property var assistants: [{id: "", name: "Disabled"}].concat(catalog.filter(m => m.assistant))
    readonly property var speechModels: [{id: "", name: "Disabled"}].concat(catalog.filter(m => !m.assistant))
    function indexOfModel(list, id) { return Math.max(0, list.findIndex(m => m.id === id)) }
    function description(id) { const m = catalog.find(m => m.id === id); return m ? m.description + " License: " + m.license + "." : "No model selected." }
    Loader {
        Layout.fillWidth: true
        active: !!pane.assistant && !!pane.speechOutput
        sourceComponent: AssistantSettings {
            assistant: pane.assistant; speechOutput: pane.speechOutput
            inkColor: pane.inkColor; mutedColor: pane.mutedColor; accentColor: pane.accentColor
        }
    }
    Text { text: "LOCAL AI & VOICE"; color: pane.inkColor; font.bold: true; font.pixelSize: 16 }
    Text {
        Layout.fillWidth: true
        text: "Choose Yes when Lunchpail asks to install a bundled model. Download, setup and CPU/GPU selection are automatic. Bundled models need no account or separate server and process prompts and microphone audio on this device."
        color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 12
    }
    RowLayout {
        LbButton { text: pane.ai.assistant_ready ? "Assistant installed" : "Install assistant…"; enabled: !pane.ai.busy; onClicked: { pane.enableVoiceAfterInstall = false; installer.request(true, false) } }
        LbButton { text: pane.ai.speech_ready ? "Voice model installed" : "Install voice…"; enabled: !pane.ai.busy; onClicked: { pane.enableVoiceAfterInstall = false; installer.request(false, false) } }
    }
    LbCheckBox {
        id: handsFreeToggle
        objectName: "handsFreePreference"
        text: "Hands-free conversation in normal & Couch modes · microphone on"
        checked: !!pane.ai.hands_free
        onClicked: {
            if (!checked) pane.ai.enable_hands_free(false)
            else { pane.enableVoiceAfterInstall = true; installer.request(false, true) }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pane.mutedColor; font.pixelSize: 11
        text: "When enabled, the microphone listens locally while Lunchpail is focused in normal or Couch mode, pauses for games, dialogs and spoken replies, and shows a Mic on indicator. Audio is never saved or uploaded. Transcripts are sent to your chosen AI provider. Use a headset or the optional wake phrase to avoid picking up room/preview audio. F2 works for push-to-talk in the conversation panel."
    }
    LocalModelInstall {
        id: installer; ai: pane.ai
        onReady: { if (pane.enableVoiceAfterInstall) pane.ai.enable_hands_free(true); pane.enableVoiceAfterInstall = false }
        onDeclined: { pane.enableVoiceAfterInstall = false; handsFreeToggle.checked = Qt.binding(() => !!pane.ai.hands_free) }
    }
    LbButton { objectName: "advancedAiOptions"; text: pane.advanced ? "Hide advanced options" : "Advanced options"; onClicked: pane.advanced = !pane.advanced }
    ColumnLayout {
      Layout.fillWidth: true; visible: pane.advanced; spacing: 12
    Text { text: "Assistant model"; color: pane.inkColor; font.bold: true }
    LbComboBox {
        objectName: "assistantModelChoice"
        Layout.fillWidth: true; model: pane.assistants; textRole: "name"
        currentIndex: pane.indexOfModel(pane.assistants, pane.ai.assistant_model)
        onActivated: pane.ai.select_assistant(pane.assistants[currentIndex].id)
        Accessible.name: "Local assistant model"
    }
    Text { Layout.fillWidth: true; text: pane.description(pane.ai.assistant_model); color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text { text: "Speech recognition model"; color: pane.inkColor; font.bold: true }
    LbComboBox {
        objectName: "speechModelChoice"
        Layout.fillWidth: true; model: pane.speechModels; textRole: "name"
        currentIndex: pane.indexOfModel(pane.speechModels, pane.ai.speech_model)
        onActivated: pane.ai.select_speech(pane.speechModels[currentIndex].id)
        Accessible.name: "Local speech recognition model"
    }
    Text { Layout.fillWidth: true; text: pane.description(pane.ai.speech_model); color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text { text: "Compute device"; color: pane.inkColor; font.bold: true }
    LbComboBox {
        objectName: "computeChoice"
        Layout.fillWidth: true
        model: ["Automatic · Prefer GPU, fall back to CPU", "CPU only", "GPU required · Report an error if unavailable"]
        currentIndex: Math.max(0, ["auto", "cpu", "gpu"].indexOf(pane.ai.compute))
        onActivated: pane.ai.select_compute(["auto", "cpu", "gpu"][currentIndex])
        Accessible.name: "Local AI compute device"
    }
    Text {
        Layout.fillWidth: true
        text: "Whisper and assistant models support AMD, NVIDIA and Intel GPUs through Vulkan on Windows/Linux, and Metal on Apple Silicon. GPU support depends on the installed driver and available memory. Sherpa always uses the CPU. Larger models require more RAM/VRAM than their download size."
        color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11
    }
    RowLayout {
        Layout.fillWidth: true
        LbButton { text: pane.ai.busy ? "Cancel" : "Download / repair selected models"; onClicked: pane.ai.busy ? pane.ai.cancel() : pane.ai.download_selected() }
        LbButton { text: "Check hardware"; enabled: !pane.ai.busy; onClicked: pane.ai.detect_hardware() }
    }
    }
    ProgressBar { Layout.fillWidth: true; visible: pane.ai.busy; value: pane.ai.progress }
    Text { Layout.fillWidth: true; text: pane.ai.status; color: pane.accentColor; wrapMode: Text.WordWrap; font.pixelSize: 12 }
    Text { Layout.fillWidth: true; text: pane.ai.hardware; color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text {
        Layout.fillWidth: true
        text: "Models stay downloaded when disabled. Advanced model selections download immediately; Automatic compute falls back to CPU if needed. Catalog and patch lookups may contact their providers."
        color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11
    }
}
