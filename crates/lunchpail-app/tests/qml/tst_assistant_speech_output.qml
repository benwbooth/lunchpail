import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "AssistantSpeechReadiness"
    when: windowShown
    // Never play audio or open a microphone in a readiness check.
    Lunchpail.AssistantSpeechOutput { id: voice; config: ({spoken_replies:false}) }
    function cleanup() { voice.config = ({spoken_replies:false}); voice.stop() }
    function test_replies_are_silent_without_an_explicit_opt_in() {
        for (const config of [{}, {spoken_replies:false}]) {
            voice.config = config
            voice.say("open up super mario brothers")
            compare(voice.queued, false)
            verify(!voice.speaking)
        }
    }
    function test_async_engine_readiness_refreshes_voices_and_clears_startup_error() {
        if (!voice.engines.length) { skip("No speech engine installed on this test host"); return }
        tryVerify(() => voice.voiceNames.length > 0, 5000)
        compare(voice.error, "")
        verify(!voice.speaking)
    }
}
