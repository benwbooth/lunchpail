import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "ConversationUI"
    visible: true; width: 1100; height: 1200
    when: windowShown
    Component {
        id: backend
        QtObject {
            property bool busy: false
            property bool ready: true
            property bool key_saved: false
            property bool setup_busy: false
            property string status: "Ready"
            property string setup_status: ""
            property string result_json: "{}"
            property string history_json: "[]"
            property string models_json: "[]"
            property string config_json: JSON.stringify({provider:"builtin",profiles:{
                builtin:{model:"",endpoint:"",executable:""},codex:{model:"",endpoint:"",executable:"codex"},
                claude_code:{model:"",endpoint:"",executable:"claude"},ollama:{model:"local-test",endpoint:"http://127.0.0.1:11434",executable:""},
                openai:{model:"",endpoint:"https://api.openai.com/v1",executable:""},anthropic:{model:"",endpoint:"https://api.anthropic.com/v1",executable:""},
                compatible:{model:"",endpoint:"http://127.0.0.1:8080/v1",executable:""}},spoken_replies:true,captions:true,wake_word:false,voice:"",voice_engine:"",voice_rate:0,voice_volume:0.85})
            property string lastQuestion: ""
            property int keyWrites: 0
            function configure(value) { config_json = value }
            function save_api_key(value) { keyWrites++; key_saved = !!value }
            function discover_models() { models_json = JSON.stringify(["local-test", "other-model"]) }
            function ask(text) { lastQuestion = text; busy = true }
            function cancel() { busy = false }
        }
    }
    Component {
        id: voice
        QtObject {
            property bool speaking: false
            property var engines: ["test"]
            property var voiceNames: ["Voice one", "Voice two"]
            property string error: ""
            function stop() { speaking = false }
            function test() { speaking = true }
        }
    }
    Component {
        id: settingsComponent
        Lunchpail.AssistantSettings { width: 950; inkColor: "white"; mutedColor: "gray"; accentColor: "orange" }
    }
    Component {
        id: captionComponent
        Lunchpail.ConversationCaptions {
            width: 900
            speech: QtObject {
                property bool listening: false
                property bool awake: false
                property string transcript: ""
            }
        }
    }
    function settingsPane() {
        const ai = createTemporaryObject(backend, test)
        const output = createTemporaryObject(voice, test)
        const pane = createTemporaryObject(settingsComponent, test, {assistant:ai,speechOutput:output})
        verify(pane); return pane
    }
    function test_provider_settings_keep_each_profile_and_support_both_signins_and_apis() {
        const pane = settingsPane()
        const provider = findChild(pane, "conversationProvider")
        compare(provider.count, 7)
        provider.currentIndex = 3; provider.activated(3)
        compare(pane.provider, "ollama")
        pane.saveProfile("model", "chosen-local-model")
        provider.currentIndex = 1; provider.activated(1)
        compare(pane.provider, "codex"); verify(pane.cli)
        compare(pane.profile.executable, "codex")
        provider.currentIndex = 2; provider.activated(2)
        compare(pane.profile.executable, "claude")
        provider.currentIndex = 4; provider.activated(4)
        verify(pane.apiKey)
        provider.currentIndex = 3; provider.activated(3)
        compare(pane.profile.model, "chosen-local-model")
    }
    function test_voice_and_caption_controls_persist_without_changing_provider() {
        const pane = settingsPane()
        const spoken = findChild(pane, "spokenReplies")
        spoken.checked = false; spoken.clicked()
        compare(JSON.parse(pane.assistant.config_json).spoken_replies, false)
        pane.save("captions", false); pane.save("wake_word", true)
        const config = JSON.parse(pane.assistant.config_json)
        compare(config.captions, false); compare(config.wake_word, true); compare(config.provider, "builtin")
    }
    function test_typed_setup_test_uses_same_assistant() {
        const pane = settingsPane()
        const input = findChild(pane, "conversationTestInput")
        input.text = "help me set up my controller"; input.accepted()
        compare(pane.assistant.lastQuestion, "help me set up my controller")
        compare(input.text, "")
    }
    function test_captions_show_both_sides_and_partial_recognition() {
        const ai = createTemporaryObject(backend, test)
        const output = createTemporaryObject(voice, test)
        const captions = createTemporaryObject(captionComponent, test, {assistant:ai,speechOutput:output})
        verify(captions); verify(!captions.visible)
        ai.history_json = JSON.stringify([{role:"user",content:"search for Super Mario Bros"},{role:"assistant",content:"Here are the matching games."}])
        verify(captions.visible)
        compare(captions.playerText, "search for Super Mario Bros")
        compare(captions.assistantText, "Here are the matching games.")
        captions.speech.listening = true; captions.speech.transcript = "play the game"
        compare(captions.playerText, "play the game")
        captions.enabledCaptions = false; verify(!captions.visible)
        captions.enabledCaptions = true; captions.expanded = true; verify(!captions.visible)
    }
}
