import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchHandsFree"
    when: windowShown
    Component {
        id: component
        Lunchpail.CouchHandsFreeController {
            speech: QtObject {
                property bool ready: true
                property bool busy: false
                property bool hands_free: false
                property bool listening: false
                property bool awake: false
                property bool faulted: false
                property int starts: 0
                property int cancels: 0
                signal search_requested(string text)
                function start_hands_free() { starts++; busy = true; hands_free = true }
                function cancel() { cancels++; busy = false; hands_free = false }
                function poll() {}
            }
        }
    }
    SignalSpy { id: searches; signalName: "searchRequested" }
    function controller() {
        const item = createTemporaryObject(component, test)
        verify(item); searches.target = item; searches.clear()
        return item
    }
    function test_disabled_never_opens_microphone() {
        const item = controller(); item.reconcile(); compare(item.speech.starts, 0)
    }
    function test_allowed_starts_once_and_suspends_immediately() {
        const item = controller(); item.allowed = true
        compare(item.speech.starts, 1)
        item.reconcile(); compare(item.speech.starts, 1)
        item.allowed = false; compare(item.speech.cancels, 1)
        item.allowed = true; compare(item.speech.starts, 2)
    }
    function test_suspended_discards_late_commands() {
        const item = controller(); item.allowed = true
        item.speech.search_requested("Mario"); compare(searches.count, 1)
        item.allowed = false; item.speech.search_requested("late"); compare(searches.count, 1)
    }
    function test_missing_model_and_device_error_do_not_loop() {
        const item = controller(); item.speech.ready = false; item.allowed = true
        compare(item.speech.starts, 0)
        item.speech.ready = true; item.speech.faulted = true; item.reconcile()
        compare(item.speech.starts, 0)
        item.speech.search_requested("late"); compare(searches.count, 0)
    }
    function test_manual_capture_is_not_interrupted_or_duplicated() {
        const item = controller(); item.speech.busy = true; item.allowed = true
        compare(item.speech.starts, 0)
        item.allowed = false; compare(item.speech.cancels, 0)
    }
    function test_wake_listener_does_not_silence_media_between_commands() {
        const item = controller(); item.allowed = true
        item.speech.listening = true
        verify(!item.capturingCommand, "Waiting for a wake phrase must not override Unmute")
        item.speech.awake = true
        verify(item.capturingCommand)
        item.speech.awake = false
        verify(!item.capturingCommand, "Audio must return after the command or wake timeout")
        item.speech.awake = true
        item.speech.listening = false
        verify(!item.capturingCommand, "A closed microphone must not hold audio muted")
    }
    function test_push_to_talk_still_suppresses_audio() {
        const item = controller()
        item.speech.listening = true
        verify(item.capturingCommand)
        item.speech.listening = false
        verify(!item.capturingCommand)
    }
    function test_open_conversation_only_suppresses_audio_during_an_utterance() {
        const item = controller(); item.allowed = true
        item.speech.listening = true
        verify(!item.capturingCommand, "An idle open microphone must not override Unmute")
        item.speech.awake = true
        verify(item.capturingCommand, "The backend marks actual speech in open conversation too")
        item.speech.awake = false
        verify(!item.capturingCommand, "Audio must return between utterances")
        item.speech.listening = false
        verify(!item.capturingCommand, "Suppression is temporary, not a saved mute preference")
    }
}
