pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: pane
    required property var ai
    required property color inkColor
    required property color mutedColor
    required property color accentColor
    spacing: 12
    readonly property var catalog: JSON.parse(ai.models_json || "[]")
    readonly property var assistants: [{id: "", name: "Disabled"}].concat(catalog.filter(m => m.assistant))
    readonly property var speechModels: [{id: "", name: "Disabled"}].concat(catalog.filter(m => !m.assistant))
    function indexOfModel(list, id) { return Math.max(0, list.findIndex(m => m.id === id)) }
    function description(id) { const m = catalog.find(m => m.id === id); return m ? m.description + " License: " + m.license + "." : "No model selected." }
    Text { text: "LOCAL AI & VOICE"; color: pane.inkColor; font.bold: true; font.pixelSize: 16 }
    Text {
        Layout.fillWidth: true
        text: "Select models below and Lunchpail downloads them automatically from Hugging Face. No Ollama, Python, account, or separate server is needed. Downloads use the internet; prompts and microphone audio stay on this device. Catalog/patch lookups may contact their providers."
        color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 12
    }
    Text { text: "Assistant model"; color: pane.inkColor; font.bold: true }
    ComboBox {
        objectName: "assistantModelChoice"
        Layout.fillWidth: true; model: pane.assistants; textRole: "name"
        currentIndex: pane.indexOfModel(pane.assistants, pane.ai.assistant_model)
        onActivated: pane.ai.select_assistant(pane.assistants[currentIndex].id)
        Accessible.name: "Local assistant model"
    }
    Text { Layout.fillWidth: true; text: pane.description(pane.ai.assistant_model); color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text { text: "Speech recognition model"; color: pane.inkColor; font.bold: true }
    ComboBox {
        objectName: "speechModelChoice"
        Layout.fillWidth: true; model: pane.speechModels; textRole: "name"
        currentIndex: pane.indexOfModel(pane.speechModels, pane.ai.speech_model)
        onActivated: pane.ai.select_speech(pane.speechModels[currentIndex].id)
        Accessible.name: "Local speech recognition model"
    }
    Text { Layout.fillWidth: true; text: pane.description(pane.ai.speech_model); color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text { text: "Compute device"; color: pane.inkColor; font.bold: true }
    ComboBox {
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
        Button { text: pane.ai.busy ? "Cancel" : "Download / repair selected models"; onClicked: pane.ai.busy ? pane.ai.cancel() : pane.ai.download_selected() }
        Button { text: "Check hardware"; enabled: !pane.ai.busy; onClicked: pane.ai.detect_hardware() }
    }
    ProgressBar { Layout.fillWidth: true; visible: pane.ai.busy; value: pane.ai.progress }
    Text { Layout.fillWidth: true; text: pane.ai.status; color: pane.accentColor; wrapMode: Text.WordWrap; font.pixelSize: 12 }
    Text { Layout.fillWidth: true; text: pane.ai.hardware; color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11 }
    Text {
        Layout.fillWidth: true
        text: "Microphone access is always push-to-talk, with a 15-second limit. Recordings are never saved. Models stay downloaded when disabled."
        color: pane.mutedColor; wrapMode: Text.WordWrap; font.pixelSize: 11
    }
}
