pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: pane
    required property var assistant
    required property var speechOutput
    required property color inkColor
    required property color mutedColor
    required property color accentColor
    readonly property var config: JSON.parse(assistant.config_json || "{}")
    readonly property var providers: [
        {id: "builtin", name: "Bundled local model"}, {id: "codex", name: "Codex · existing sign-in"},
        {id: "claude_code", name: "Claude Code · existing sign-in"}, {id: "ollama", name: "Ollama · local server"},
        {id: "openai", name: "OpenAI API"}, {id: "anthropic", name: "Anthropic API"}, {id: "compatible", name: "OpenAI-compatible server"}]
    readonly property string provider: config.provider || "builtin"
    readonly property var profile: (config.profiles || {})[provider] || ({})
    readonly property bool cli: provider === "codex" || provider === "claude_code"
    readonly property bool apiKey: ["openai", "anthropic", "compatible"].indexOf(provider) >= 0
    readonly property var models: JSON.parse(assistant.models_json || "[]")
    spacing: 10
    function save(name, value) {
        const next = JSON.parse(assistant.config_json)
        next[name] = value
        assistant.configure(JSON.stringify(next))
    }
    function saveProfile(name, value) {
        const next = JSON.parse(assistant.config_json)
        next.profiles[provider][name] = value.trim()
        assistant.configure(JSON.stringify(next))
    }
    Text { text: "CONVERSATIONAL ASSISTANT"; color: pane.inkColor; font.bold: true; font.pixelSize: 16 }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pane.mutedColor; font.pixelSize: 12
        text: "Say or type ‘search for Super Mario Bros’, ‘play the game’, or ask for help with settings. Every provider uses the same app tools and conversation. Microphone audio is recognized locally; with a cloud provider, your transcript and relevant library/tool results are sent to that provider. Commands work without spoken replies. Optional speech playback uses your computer's installed voices."
    }
    LbComboBox {
        objectName: "conversationProvider"
        Layout.fillWidth: true; model: pane.providers; textRole: "name"
        currentIndex: Math.max(0, pane.providers.findIndex(p => p.id === pane.provider))
        onActivated: { pane.assistant.cancel(); keyField.text = ""; pane.save("provider", pane.providers[currentIndex].id) }
        Accessible.name: "Conversation provider"
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pane.mutedColor; font.pixelSize: 12
        text: pane.provider === "builtin" ? "Install a bundled assistant below. No account or server is needed."
            : pane.provider === "codex" ? "Install the Codex CLI and sign in with ‘codex login’ once, then Lunchpail uses that sign-in. A blank model uses your CLI's configured default. Lunchpail runs an isolated conversation with app tools only."
            : pane.provider === "claude_code" ? "Install Claude Code and sign in once using its normal login. A blank model uses its default. Lunchpail provides a private MCP connection for app tools; built-in coding tools are disabled."
            : pane.provider === "ollama" ? "Run Ollama locally, download a tool-capable model, then refresh the model list. Lunchpail does not start the server or download a model for you."
            : "Choose the endpoint and a tool-capable model. Save your key in the OS keyring, never in chat. API use may incur charges. Refreshing models checks connectivity, not conversation capability."
    }
    LbTextField {
        objectName: "conversationExecutable"
        Layout.fillWidth: true; visible: pane.cli; text: pane.profile.executable || ""
        placeholderText: "CLI executable name or full path"; selectByMouse: true
        onEditingFinished: pane.saveProfile("executable", text)
        Accessible.name: "Provider executable"
    }
    LbTextField {
        objectName: "conversationEndpoint"
        Layout.fillWidth: true; visible: pane.provider !== "builtin" && !pane.cli; text: pane.profile.endpoint || ""
        placeholderText: "Server URL"; selectByMouse: true
        onEditingFinished: pane.saveProfile("endpoint", text)
        Accessible.name: "AI server URL"
    }
    RowLayout {
        Layout.fillWidth: true; visible: pane.provider !== "builtin"
        LbTextField {
            objectName: "conversationModel"
            Layout.fillWidth: true; text: pane.profile.model || ""; selectByMouse: true
            placeholderText: pane.cli ? "Model override (optional)" : "Model ID (required)"
            onEditingFinished: pane.saveProfile("model", text)
            Accessible.name: "AI model"
        }
        LbButton { text: "Refresh models"; visible: !pane.cli; enabled: !pane.assistant.setup_busy; onClicked: pane.assistant.discover_models() }
    }
    LbComboBox {
        objectName: "conversationAvailableModels"
        Layout.fillWidth: true; visible: pane.models.length > 0 && !pane.cli && pane.provider !== "builtin"
        model: pane.models
        currentIndex: pane.models.indexOf(pane.profile.model)
        onActivated: pane.saveProfile("model", pane.models[currentIndex])
        Accessible.name: "Available provider models"
    }
    RowLayout {
        Layout.fillWidth: true; visible: pane.apiKey
        LbTextField {
            id: keyField; objectName: "conversationApiKey"
            Layout.fillWidth: true; echoMode: TextInput.Password; selectByMouse: true
            placeholderText: pane.assistant.key_saved ? "Key stored · enter a replacement" : "API key (stored only in the OS keyring)"
            Accessible.name: "Private API key"
        }
        LbButton { text: "Save key"; enabled: keyField.text.length > 0; onClicked: { pane.assistant.save_api_key(keyField.text); keyField.text = "" } }
        LbButton { text: "Clear key"; enabled: pane.assistant.key_saved; onClicked: pane.assistant.save_api_key("") }
    }
    Text { Layout.fillWidth: true; text: pane.assistant.setup_status; color: pane.accentColor; wrapMode: Text.WordWrap; textFormat: Text.PlainText; font.pixelSize: 12 }
    RowLayout {
        LbCheckBox { objectName: "spokenReplies"; text: "Speak replies (optional)"; checked: pane.config.spoken_replies === true; onClicked: pane.save("spoken_replies", checked) }
        LbCheckBox { objectName: "conversationCaptions"; text: "Player + assistant captions"; checked: pane.config.captions !== false; onClicked: pane.save("captions", checked) }
    }
    LbCheckBox { objectName: "conversationWakeWord"; text: "Require ‘Lunchpail’ before hands-free requests"; checked: !!pane.config.wake_word; onClicked: pane.save("wake_word", checked) }
    LbComboBox {
        objectName: "conversationSpeechEngine"
        Layout.fillWidth: true; visible: pane.speechOutput.engines.length > 1
        model: ["System default"].concat(pane.speechOutput.engines)
        currentIndex: Math.max(0, pane.speechOutput.engines.indexOf(pane.config.voice_engine || "") + 1)
        onActivated: pane.save("voice_engine", currentIndex ? pane.speechOutput.engines[currentIndex - 1] : "")
        Accessible.name: "Speech engine"
    }
    LbComboBox {
        objectName: "conversationVoice"
        Layout.fillWidth: true; model: ["System default voice"].concat(pane.speechOutput.voiceNames)
        currentIndex: Math.max(0, pane.speechOutput.voiceNames.indexOf(pane.config.voice || "") + 1)
        onActivated: pane.save("voice", currentIndex ? pane.speechOutput.voiceNames[currentIndex - 1] : "")
        Accessible.name: "Assistant speaking voice"
    }
    RowLayout {
        Layout.fillWidth: true
        Text { text: "Speed"; color: pane.inkColor }
        LbSlider { Layout.fillWidth: true; from: -1; to: 1; stepSize: 0.05; value: pane.config.voice_rate || 0; onMoved: pane.save("voice_rate", value); Accessible.name: "Speaking speed" }
        Text { text: "Volume"; color: pane.inkColor }
        LbSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: pane.config.voice_volume === undefined ? 0.85 : pane.config.voice_volume; onMoved: pane.save("voice_volume", value); Accessible.name: "Voice volume" }
        LbButton { objectName: "conversationTestVoice"; text: pane.speechOutput.speaking ? "Stop voice" : "Test voice"; onClicked: pane.speechOutput.speaking ? pane.speechOutput.stop() : pane.speechOutput.test() }
    }
    Text { Layout.fillWidth: true; visible: !!pane.speechOutput.error; text: pane.speechOutput.error; color: pane.accentColor; wrapMode: Text.WordWrap }
    RowLayout {
        Layout.fillWidth: true
        LbTextField {
            id: testMessage; objectName: "conversationTestInput"
            Layout.fillWidth: true; placeholderText: "Ask a question or test: What can you help me do?"
            onAccepted: if (text.trim()) { pane.assistant.ask(text); text = "" }
            Accessible.name: "Assistant test message"
        }
        LbButton { objectName: "conversationTestButton"; text: pane.assistant.busy ? "Stop" : "Test conversation"; onClicked: {
            if (pane.assistant.busy) pane.assistant.cancel()
            else { pane.assistant.ask(testMessage.text.trim() || "What can you help me do? Do not change anything for this test."); testMessage.text = "" }
        } }
    }
    Text { Layout.fillWidth: true; text: pane.assistant.status; color: pane.mutedColor; wrapMode: Text.WordWrap; textFormat: Text.PlainText }
    Text { Layout.fillWidth: true; text: JSON.parse(pane.assistant.result_json || "{}").message || ""; color: pane.inkColor; wrapMode: Text.WordWrap; textFormat: Text.PlainText }
}
