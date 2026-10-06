import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "AssistantSpeechReadiness"
    when: windowShown
    // Never play audio or open a microphone in a readiness check.
    Lunchpail.AssistantSpeechOutput { id: voice; config: ({spoken_replies:false}) }
    function test_async_engine_readiness_refreshes_voices_and_clears_startup_error() {
        if (!voice.engines.length) { skip("No speech engine installed on this test host"); return }
        tryVerify(() => voice.voiceNames.length > 0, 5000)
        compare(voice.error, "")
        verify(!voice.speaking)
    }
}
