import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchPrimaryAction"
    Component {
        id: actionComponent
        Lunchpail.CouchPrimaryAction {
            current: true
            details: QtObject {
                property bool loading: false
                property bool game_running: false
                property bool session_stopping: false
                property bool launch_busy: false
                property bool download_busy: false
                property bool can_launch: false
            }
        }
    }
    SignalSpy { id: requested; signalName: "requested" }
    function test_install_changes_to_play_only_when_ready() {
        const action = createTemporaryObject(actionComponent, this, {downloadable: true})
        requested.target = action; requested.clear()
        compare(action.label, "Install")
        verify(action.hint.indexOf("confirm the download") >= 0)
        action.activate()
        compare(requested.signalArguments[0][0], "install")
        action.downloadState = "DOWNLOADING"; action.downloadProgress = 0.42
        compare(action.label, "View installation")
        compare(action.progress, 0.42)
        verify(action.hint.indexOf("42%") >= 0)
        action.activate()
        compare(requested.signalArguments[1][0], "download")
        action.downloadState = "IMPORTED"; action.local = true
        compare(action.label, "Set up play")
        action.activate()
        compare(requested.signalArguments[2][0], "setup")
        action.details.can_launch = true
        compare(action.label, "Play")
        compare(action.hint, "Installed and ready to play")
        action.activate()
        compare(requested.signalArguments[3][0], "play")
    }
    function test_pending_states_cannot_launch_or_queue_again() {
        const action = createTemporaryObject(actionComponent, this, {local: true})
        requested.target = action; requested.clear()
        action.details.can_launch = true
        action.current = false
        compare(action.kind, "loading"); verify(!action.enabled)
        action.activate()
        action.current = true; action.details.loading = true
        compare(action.kind, "loading"); action.activate()
        action.details.loading = false; action.details.download_busy = true
        compare(action.kind, "queueing"); verify(!action.enabled); action.activate()
        action.details.download_busy = false; action.details.game_running = true
        action.details.session_stopping = true
        compare(action.label, "Stopping…"); verify(!action.enabled); action.activate()
        compare(requested.count, 0)
    }
    function test_running_and_preparing_keep_existing_controls() {
        const action = createTemporaryObject(actionComponent, this, {local: true})
        requested.target = action; requested.clear()
        action.details.can_launch = true; action.details.launch_busy = true
        compare(action.label, "Cancel preparation"); action.activate()
        compare(requested.signalArguments[0][0], "cancel")
        action.details.game_running = true
        compare(action.label, "Stop emulator"); action.activate()
        compare(requested.signalArguments[1][0], "stop")
    }
    function test_download_recovery_and_cancelled_install() {
        const action = createTemporaryObject(actionComponent, this, {downloadable: true, downloadState: "FAILED"})
        compare(action.label, "Fix installation")
        verify(action.enabled)
        action.downloadState = "PAUSED"
        verify(action.hint.indexOf("resume") >= 0)
        action.downloadState = "COMPLETE"
        verify(action.hint.indexOf("import status") >= 0)
        action.downloadState = "CANCELLED"
        compare(action.label, "Install")
        action.downloadState = "DOWNLOADING"; action.downloadProgress = 2
        compare(action.progress, 1)
        action.downloadProgress = -1
        compare(action.progress, 0)
    }
    function test_missing_files_are_not_mislabeled_play_or_install() {
        const action = createTemporaryObject(actionComponent, this)
        requested.target = action; requested.clear()
        compare(action.label, "Add game files"); action.activate()
        compare(requested.signalArguments[0][0], "files")
    }
}
