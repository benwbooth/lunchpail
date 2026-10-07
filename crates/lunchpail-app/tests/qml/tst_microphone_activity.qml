import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "MicrophoneActivity"
    Component {
        id: component
        Lunchpail.MicrophoneActivity {
            speech: QtObject {
                property bool listening: true
                property bool busy: true
                property bool awake: false
                property bool input_silent: false
                property bool speech_active: false
                property string status: "Microphone off"
            }
        }
    }
    function state() { return createTemporaryObject(component, test) }
    function test_open_session_is_idle_not_detected_speech() {
        const s = state()
        compare(s.label, "Mic idle")
        compare(s.detail, "Mic on · Waiting for speech")
        verify(!s.hearingSpeech)
        s.speech.awake = true // A wake-phrase window is not audio evidence.
        verify(!s.hearingSpeech)
        compare(s.label, "Mic idle")
    }
    function test_silent_input_has_calibrated_mute_hint() {
        const s = state(); s.speech.input_silent = true
        compare(s.label, "No input")
        compare(s.detail, "No audio input · Microphone may be muted or silent")
        verify(!s.hearingSpeech)
        s.speech.speech_active = true // End-of-utterance silence wins.
        verify(!s.hearingSpeech)
        compare(s.label, "No input")
    }
    function test_actual_speech_activates_and_recovers_after_unmute() {
        const s = state(); s.speech.input_silent = true
        s.speech.input_silent = false; s.speech.speech_active = true
        compare(s.label, "Hearing speech"); verify(s.hearingSpeech)
        s.speech.speech_active = false
        compare(s.label, "Mic idle"); verify(!s.hearingSpeech)
    }
    function test_closed_mic_never_shows_stale_activity() {
        const s = state(); s.speech.input_silent = true; s.speech.speech_active = true
        s.speech.listening = false
        compare(s.label, "Mic off"); compare(s.detail, "Microphone off")
        verify(!s.hearingSpeech); verify(!s.silent)
    }
}
