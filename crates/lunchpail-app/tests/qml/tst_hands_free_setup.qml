import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "HandsFreeSetup"
    when: windowShown
    visible: true; width: 900; height: 700
    Component {
        id: component
        Lunchpail.HandsFreeSetup {
            id: fixture
            ai: QtObject {
                property bool assistant_ready: true
                property bool speech_ready: true
                property bool hands_free: false
                property bool busy: false
                property string assistant_model: "qwen3-4b"
                property string speech_model: "sherpa-zipformer-en"
                property string models_json: "[]"
                property string status: "Ready"
                property real progress: 0
                property var installs: []
                signal operation_finished(bool success)
                function enable_hands_free(value) { hands_free = value }
                function install_for(assistant) { installs = installs.concat([assistant]); busy = true }
                function cancel() { busy = false }
            }
            assistant: QtObject {
                property string config_json: JSON.stringify({provider:"builtin"})
                property bool remoteReady: false
                property bool ready: JSON.parse(config_json).provider === "builtin" ? fixture.ai.assistant_ready : remoteReady
                function refresh() {}
            }
        }
    }
    SignalSpy { id: enabled; signalName: "enabledListening" }
    SignalSpy { id: settings; signalName: "settingsRequested" }
    function setup() {
        const s = createTemporaryObject(component, test); verify(s)
        enabled.target = s; enabled.clear()
        settings.target = s; settings.clear()
        return s
    }
    function finish(s, assistant) {
        if (assistant) s.ai.assistant_ready = true
        else s.ai.speech_ready = true
        s.ai.busy = false
        s.ai.operation_finished(true)
    }
    function test_ready_setup_toggles_without_installing() {
        const s = setup(); s.toggle()
        compare(s.ai.hands_free, true); compare(enabled.count, 1)
        compare(s.ai.installs.length, 0)
        s.toggle(); compare(s.ai.hands_free, false)
    }
    function test_speech_only_requires_assistant_consent_before_mic() {
        const s = setup(); s.ai.assistant_ready = false
        s.toggle()
        verify(s.installDialog.visible); verify(s.installDialog.assistantModel)
        compare(s.ai.hands_free, false); compare(s.ai.installs.length, 0)
        s.installDialog.install(); compare(s.ai.installs[0], true)
        finish(s, true)
        tryCompare(s.ai, "hands_free", true); compare(enabled.count, 1)
    }
    function test_both_models_have_separate_consent_before_enabling() {
        const s = setup(); s.ai.assistant_ready = false; s.ai.speech_ready = false
        s.request(); s.installDialog.install(); finish(s, true)
        tryVerify(() => s.installDialog.visible && !s.installDialog.assistantModel)
        compare(s.ai.hands_free, false); compare(s.ai.installs.length, 1)
        s.installDialog.install(); compare(s.ai.installs[1], false)
        finish(s, false)
        tryCompare(s.ai, "hands_free", true); compare(enabled.count, 1)
    }
    function test_cancelled_assistant_download_cannot_enable_later() {
        const s = setup(); s.ai.assistant_ready = false
        s.request(); s.installDialog.install(); s.toggle()
        compare(s.pending, false); compare(s.ai.busy, false)
        finish(s, true); wait(50)
        compare(s.ai.hands_free, false); compare(enabled.count, 0)
    }
    function test_declining_second_model_keeps_mic_off() {
        const s = setup(); s.ai.assistant_ready = false; s.ai.speech_ready = false
        s.request(); s.installDialog.install(); finish(s, true)
        tryVerify(() => s.installDialog.visible && !s.installDialog.assistantModel)
        s.installDialog.decline()
        compare(s.pending, false); compare(s.ai.hands_free, false); compare(enabled.count, 0)
    }
    function test_ready_remote_provider_needs_no_local_assistant() {
        const s = setup(); s.ai.assistant_ready = false
        s.assistant.config_json = JSON.stringify({provider:"ollama"}); s.assistant.remoteReady = true
        s.request()
        compare(s.ai.hands_free, true); compare(s.ai.installs.length, 0)
    }
    function test_unconfigured_remote_provider_explains_setup_without_download() {
        const s = setup(); s.assistant.config_json = JSON.stringify({provider:"ollama"})
        s.request()
        verify(s.providerDialog.visible); compare(s.ai.hands_free, false)
        compare(s.ai.installs.length, 0); compare(settings.count, 0)
        s.toggle(); compare(s.pending, false); tryCompare(s.providerDialog, "visible", false)
    }
    function test_persisted_enabled_but_incomplete_setup_can_be_repaired() {
        const s = setup(); s.ai.hands_free = true; s.ai.assistant_ready = false
        s.toggle()
        compare(s.ai.hands_free, false); verify(s.installDialog.visible)
        s.cancel(); compare(s.pending, false); compare(enabled.count, 0)
    }
}
