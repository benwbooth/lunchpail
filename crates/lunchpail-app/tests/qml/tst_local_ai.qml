import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "IntegratedLocalAI"
    when: windowShown
    visible: true; width: 1100; height: 950
    Component {
        id: settingsComponent
        Lunchpail.LocalAiSettings {
            width: 900; height: 900
            inkColor: "white"; mutedColor: "gray"; accentColor: "orange"
            ai: QtObject {
                property string models_json: JSON.stringify([
                    {id: "llm", name: "Test LLM", assistant: true, description: "Assistant", license: "MIT"},
                    {id: "stt", name: "Test STT", assistant: false, description: "Speech", license: "MIT"}])
                property string assistant_model: ""
                property string speech_model: ""
                property string compute: "auto"
                property string status: "Choose a model"
                property string hardware: "CPU"
                property bool busy: false
                property real progress: 0
                property int selections: 0
                function select_assistant(id) { assistant_model = id; selections++ }
                function select_speech(id) { speech_model = id; selections++ }
                function select_compute(mode) { compute = mode }
                function cancel() { busy = false }
                function download_selected() { busy = true }
                function detect_hardware() {}
            }
        }
    }
    Component {
        id: searchComponent
        Lunchpail.CouchSearchOverlay {
            width: 960; height: 800
            speech: QtObject {
                property bool ready: true
                property bool busy: false
                property bool listening: false
                property string status: "Ready"
                property string transcript: ""
                signal completed(string text)
                function prepare() {}
                function start() { busy = true; listening = true }
                function stop() { busy = false; listening = false }
                function cancel() { busy = false; listening = false }
                function poll() {}
            }
            assistant: QtObject {
                property bool ready: true
                property bool busy: false
                property string status: "Ready"
                property string result_json: "{}"
                property int calls: 0
                property int cancels: 0
                property string lastQuestion: ""
                function ask(question) { calls++; lastQuestion = question; busy = true }
                function cancel() { cancels++; busy = false }
                function clear() { cancel(); result_json = "{}" }
            }
        }
    }
    SignalSpy { id: edits; signalName: "queryEdited" }
    SignalSpy { id: chosen; signalName: "gameChosen" }
    SignalSpy { id: settings; signalName: "settingsRequested" }
    function panel() {
        const pane = createTemporaryObject(searchComponent, test)
        verify(pane)
        edits.target = pane; edits.clear()
        chosen.target = pane; chosen.clear()
        settings.target = pane; settings.clear()
        pane.open("Mario")
        return pane
    }
    function test_model_choices_call_correct_save_and_download_entrypoint() {
        const pane = createTemporaryObject(settingsComponent, test)
        verify(pane)
        const llm = findChild(pane, "assistantModelChoice")
        const stt = findChild(pane, "speechModelChoice")
        const compute = findChild(pane, "computeChoice")
        compare(llm.count, 2); compare(stt.count, 2)
        llm.currentIndex = 1; llm.activated(1)
        stt.currentIndex = 1; stt.activated(1)
        compute.currentIndex = 2; compute.activated(2)
        compare(pane.ai.assistant_model, "llm")
        compare(pane.ai.speech_model, "stt")
        compare(pane.ai.compute, "gpu")
        compare(pane.ai.selections, 2)
    }
    function test_ask_typing_does_not_filter_shelf_or_auto_submit() {
        const pane = panel()
        pane.toggleMode()
        compare(pane.askMode, true)
        keyClick(Qt.Key_S); keyClick(Qt.Key_N); keyClick(Qt.Key_E); keyClick(Qt.Key_S)
        compare(edits.count, 0); compare(pane.assistant.calls, 0)
        keyClick(Qt.Key_Return)
        compare(pane.assistant.calls, 1)
        compare(pane.assistant.lastQuestion, "snes")
    }
    function test_voice_submits_only_completed_utterance() {
        const pane = panel()
        pane.toggleMode(); pane.microphone()
        pane.speech.transcript = "find me"
        compare(pane.assistant.calls, 0); compare(edits.count, 0)
        pane.speech.transcript = "find me an SNES RPG"
        pane.speech.busy = false; pane.speech.listening = false
        pane.speech.completed(pane.speech.transcript)
        compare(pane.assistant.calls, 1)
        compare(pane.assistant.lastQuestion, "find me an SNES RPG")
        pane.speech.completed("duplicate")
        compare(pane.assistant.calls, 1)
    }
    function test_cancel_rejects_late_voice_and_stops_assistant() {
        const pane = panel()
        pane.toggleMode(); pane.microphone(); pane.cancelVoice()
        pane.speech.completed("late")
        compare(pane.assistant.calls, 0)
        pane.assistant.ask("question"); pane.close()
        verify(!pane.assistant.busy)
        compare(pane.assistant.cancels, 1)
    }
    function test_controller_opens_catalog_card_not_game_launch() {
        const pane = panel()
        pane.toggleMode()
        pane.assistant.result_json = JSON.stringify({message:"Try this", games:[{id:"real-id",title:"Catalog title",platform:"SNES",genre:"RPG",year:"1995",rating:"4.5"}],patches:[]})
        compare(pane.actionCount, 5)
        pane.controllerIndex = 4
        pane.handleNavigation("accept")
        compare(chosen.count, 1)
        compare(chosen.signalArguments[0][0].id, "real-id")
    }
    function test_missing_model_opens_settings() {
        const pane = panel()
        pane.toggleMode(); pane.assistant.ready = false
        pane.controllerIndex = 2; pane.handleNavigation("accept")
        compare(settings.count, 1); compare(pane.assistant.calls, 0)
    }
    function test_new_answer_reveals_evidence_header_instead_of_skipping_it() {
        const pane = panel()
        pane.toggleMode()
        const rows = Array.from({length: 8}, (_, index) => ({id: "real-" + index, title: "Game " + index, platform: "SNES", genre: "RPG", year: "1995", rating: "4"}))
        pane.assistant.result_json = JSON.stringify({message: "Provider language is unknown. This is not a verified English translation.", games: rows})
        const results = findChild(pane, "assistantResults")
        tryCompare(results, "count", 8)
        results.positionViewAtEnd()
        tryCompare(results, "atYBeginning", false)
        pane.assistant.result_json = JSON.stringify({message: "New lookup; compatibility remains unknown.", games: rows.slice(0, 4)})
        tryCompare(results, "atYBeginning", true)
    }
}
