import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "LocalModelInstallation"
    when: windowShown
    visible: true; width: 900; height: 700
    Component {
        id: component
        Lunchpail.LocalModelInstall {
            ai: QtObject {
                property bool assistant_ready: false
                property bool speech_ready: false
                property bool busy: false
                property string assistant_model: ""
                property string speech_model: "sherpa-zipformer-en"
                property string models_json: "[]"
                property string status: "Ready"
                property real progress: 0
                property int installs: 0
                property bool requestedAssistant: false
                signal operation_finished(bool success)
                function finish(success) { busy = false; operation_finished(success) }
                function install_for(assistant) { installs++; requestedAssistant = assistant; busy = true }
                function cancel() { busy = false }
            }
        }
    }
    SignalSpy { id: ready; signalName: "ready" }
    SignalSpy { id: declined; signalName: "declined" }
    function dialog() {
        const item = createTemporaryObject(component, test)
        verify(item)
        ready.target = item; ready.clear()
        declined.target = item; declined.clear()
        return item
    }
    function test_no_does_not_install_or_continue() {
        const item = dialog()
        item.request(false, true)
        compare(item.ai.installs, 0)
        verify(item.visible)
        item.decline()
        compare(item.ai.installs, 0); compare(ready.count, 0); compare(declined.count, 1)
    }
    function test_yes_continues_automatically_only_after_verified_ready() {
        const item = dialog()
        item.request(true, false); item.install()
        compare(item.ai.installs, 1); compare(item.ai.requestedAssistant, true)
        compare(ready.count, 0)
        item.ai.assistant_ready = true
        item.ai.finish(true)
        compare(ready.count, 1); verify(!item.visible)
    }
    function test_cancel_rejects_late_download_completion() {
        const item = dialog()
        item.request(false, true); item.install(); item.decline()
        item.ai.speech_ready = true; item.ai.finish(true)
        compare(ready.count, 0); compare(declined.count, 1)
    }
    function test_failure_stays_open_for_retry_without_continuing() {
        const item = dialog()
        item.request(false, false); item.install(); item.ai.finish(false)
        compare(ready.count, 0); verify(item.visible); verify(!item.pending)
        item.install(); compare(item.ai.installs, 2)
        item.decline()
    }
    function test_error_does_not_trust_existing_file_size_readiness() {
        const item = dialog()
        item.request(false, false); item.install()
        item.ai.speech_ready = true; item.ai.finish(false)
        compare(ready.count, 0); verify(item.visible); verify(!item.pending)
        item.decline()
    }
    function test_installed_model_needs_no_download() {
        const item = dialog()
        item.ai.speech_ready = true; item.request(false, true)
        compare(ready.count, 1); compare(item.ai.installs, 0); verify(!item.visible)
    }
}
