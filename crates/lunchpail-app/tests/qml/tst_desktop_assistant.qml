import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "DesktopAssistant"
    when: windowShown
    visible: true; width: 1000; height: 740
    readonly property var overlay: Controls.Overlay.overlay
    Component {
        id: popupComponent
        Controls.Dialog {
            parent: Controls.Overlay.overlay
            modal: true; width: 900; height: 650
            title: "Settings fixture"
        }
    }
    Component {
        id: component
        Lunchpail.DesktopAssistant {
            width: 1000; height: 740
            assistant: QtObject {
                property string config_json: JSON.stringify({captions:true,wake_word:false})
                property string history_json: "[]"
                property string result_json: "{}"
                property string status: "Ready"
                property bool ready: true
                property bool busy: false
                property string question: ""
                function ask(text) { question = text; busy = true }
                function cancel() { busy = false }
                function clear() { history_json = "[]" }
            }
            speech: QtObject {
                property bool busy: false
                property bool ready: true
                property bool listening: false
                property bool hands_free: false
                property bool awake: false
                property bool faulted: false
                property string transcript: ""
                property string status: "Voice ready"
                signal completed(string text)
                signal search_requested(string text)
                function start() { busy = true; listening = true }
                function start_hands_free() { hands_free = true; start() }
                function cancel() { busy = false; hands_free = false; listening = false }
                function stop() { listening = false }
                function poll() {}
            }
            speechOutput: QtObject {
                property bool speaking: false
                function stop() { speaking = false }
            }
            ai: QtObject {
                property bool hands_free: false
                function enable_hands_free(value) { hands_free = value }
            }
        }
    }
    function pane() { const p = createTemporaryObject(component, test); verify(p); return p }
    function test_compact_panel_is_conversation_only_and_sends_same_backend() {
        const p = pane(); p.open("find Mario")
        compare(p.opened, true); compare(p.searchPanel.askMode, true)
        compare(p.searchPanel.baseActionCount, 3)
        p.searchPanel.toggleMode(); compare(p.searchPanel.askMode, true)
        p.searchPanel.submit(); compare(p.assistant.question, "find Mario")
        compare(findChild(p, "couchSearchField").text, "")
        p.close(); compare(p.opened, false); compare(p.assistant.busy, true)
    }
    function test_push_to_talk_cancels_on_background_or_mode_switch() {
        const p = pane(); p.open(""); p.searchPanel.microphone()
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, true)
        p.windowActive = false; compare(p.speech.listening, false)
        p.windowActive = true; p.searchPanel.microphone(); p.active = false
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
    }
    function test_hands_free_is_opt_in_and_pauses_for_games_dialogs_and_replies() {
        const p = pane(); compare(p.handsFreeAllowed, false)
        p.ai.hands_free = true; compare(p.handsFreeAllowed, true)
        compare(p.speech.listening, true)
        p.inputBlocked = true; compare(p.handsFreeAllowed, false); compare(p.speech.listening, false)
        p.inputBlocked = false; p.gameRunning = true; compare(p.speech.listening, false)
        p.gameRunning = false; p.speechOutput.speaking = true
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, true)
        p.speechOutput.speaking = false; compare(p.handsFreeAllowed, false)
        p.coolingDown = false; compare(p.handsFreeAllowed, true)
        p.assistant.busy = true; compare(p.speech.listening, false)
    }
    function test_voice_request_uses_shared_history_and_stops_capture() {
        const p = pane(); p.ai.hands_free = true
        p.speech.search_requested("play the selected game")
        compare(p.assistant.question, "play the selected game")
        compare(p.speech.listening, false); compare(p.assistant.busy, true)
    }
    function test_visible_mic_off_control_stops_listening_without_settings() {
        const p = pane(); p.open(""); p.ai.hands_free = true
        const off = findChild(p, "desktopHandsFreeOff"); verify(off.visible)
        off.clicked(); compare(p.ai.hands_free, false); compare(p.speech.listening, false)
    }
    function test_captions_and_transcript_keep_literal_text() {
        const p = pane(); p.open("")
        p.assistant.history_json = JSON.stringify([{role:"user",content:"<b>literal</b>"},{role:"assistant",content:"Selected Mario."}])
        compare(p.searchPanel.conversation.length, 2)
        compare(findChild(p, "conversationTranscript").count, 2)
        p.close(); compare(p.assistant.history_json.indexOf("Selected Mario.") > 0, true)
    }
    function test_conversation_remains_mouse_accessible_above_modal_workflow() {
        const p = pane(); p.parent = test.overlay; p.z = 19000; p.open("")
        const popup = createTemporaryObject(popupComponent, test); verify(popup)
        popup.open(); tryCompare(popup, "opened", true)
        const field = findChild(p, "couchSearchField")
        mouseClick(field, 20, 20); tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_H); compare(field.text, "h")
        popup.close(); p.close()
    }
}
