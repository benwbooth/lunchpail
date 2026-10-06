import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: testCase
    name: "CouchDownloadScreen"
    when: windowShown

    Component {
        id: hostComponent

        Item {
            width: 1920
            height: 1200

            QtObject {
                id: detailsState
                property int detail_revision: 1
                property bool torrent_loading: false
                property string message: "3 candidates ranked"
                property bool download_busy: false
                property bool can_launch: false
                property bool local: false
                property bool loading: false
                property bool launch_discovery_busy: false
                property bool download_preflight_busy: false
                property bool download_preflight_ready: false
                property bool download_preflight_terminal: false
                property string download_preflight_action: ""
                property string download_preflight_status: "Checking storage"
                property string download_preflight_mode: "139 KiB exact file"
                property string download_preflight_storage: "Enough space"
                property string download_preflight_destination: "/roms/Faxanadu.zip"
                property int selectedIndex: -1
                property int inspectedIndex: -1
                property int queuedIndex: -1
                property int candidateCount: 3

                function download_candidate_count() { return candidateCount }
                function download_candidate_source_at(index) {
                    return index < 2 ? "No-Intro · Nintendo Entertainment System"
                                     : "FinalBurn Neo"
                }
                function download_candidate_name_at(index) {
                    return ["Faxanadu (USA) (Rev 1).zip",
                            "Faxanadu (Europe).zip",
                            "nes/faxanadu.zip"][index]
                }
                function download_candidate_detail_at(index) {
                    return index === 0 ? "BEST MATCH · USA · 139 KiB"
                                       : "Exact title match"
                }
                function select_download_candidate(index) {
                    selectedIndex = index
                    return index
                }
                function inspect_download(index) { inspectedIndex = index }
                function queue_file(index) {
                    queuedIndex = index
                    message = "Faxanadu was added to Downloads."
                    download_busy = true
                }
            }

            QtObject {
                id: queueState
                property int revision: 0
                property string state: ""
                property real progress: 0
                property string resumed: ""
                property string retried: ""
                function job_index_for_game(id) { return id === "faxanadu" && state ? 2 : -1 }
                function job_id_at(index) { return index === 2 ? "exact-job" : "wrong-job" }
                function job_state_at(index) { return state }
                function job_detail_at(index) { return "Selected download · " + state }
                function job_progress_at(index) { return progress }
                function job_can_resume(index) { return state === "PAUSED" }
                function job_can_retry(index) { return state === "FAILED" }
                function resume_job(index) { resumed = job_id_at(index) }
                function retry_job(id) { retried = id }
                function refresh() { revision++ }
            }

            Lunchpail.CouchDownloadScreen {
                id: downloadScreen
                anchors.fill: parent
                details: detailsState
                downloadQueue: queueState
                gameId: "faxanadu"
                active: true
                gameTitle: "Faxanadu"
                platformName: "Nintendo Entertainment System"
                coverUrl: ""
                heroUrl: ""
            }

            SignalSpy {
                id: configureSpy
                target: downloadScreen
                signalName: "configureRequested"
            }

            SignalSpy {
                id: closeSpy
                target: downloadScreen
                signalName: "closeRequested"
            }

            SignalSpy {
                id: importSpy
                target: downloadScreen
                signalName: "importTorrentRequested"
            }
            SignalSpy { id: playSpy; target: downloadScreen; signalName: "playRequested" }
            SignalSpy { id: setupSpy; target: downloadScreen; signalName: "setupRequested" }

            property alias detailsState: detailsState
            property alias downloadScreen: downloadScreen
            property alias configureSpy: configureSpy
            property alias closeSpy: closeSpy
            property alias importSpy: importSpy
            property alias queueState: queueState
            property alias playSpy: playSpy
            property alias setupSpy: setupSpy
        }
    }

    function test_controller_flow_reviews_setup_and_queues_exact_candidate() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        compare(host.downloadScreen.candidateCount, 3)
        compare(host.downloadScreen.selectedCandidate, 0)

        verify(host.downloadScreen.handleNavigation("down"))
        compare(host.downloadScreen.selectedCandidate, 1)
        verify(host.downloadScreen.handleNavigation("accept"))
        compare(host.downloadScreen.phase, "review")
        compare(host.detailsState.selectedIndex, 1)
        compare(host.detailsState.inspectedIndex, 1)

        host.detailsState.download_preflight_action = "configure_qbittorrent"
        host.downloadScreen.activateReview()
        compare(host.configureSpy.count, 1)

        host.detailsState.download_preflight_action = ""
        host.detailsState.download_preflight_ready = true
        host.downloadScreen.activateReview()
        compare(host.detailsState.queuedIndex, 1)
        compare(host.downloadScreen.phase, "queue")

        host.detailsState.download_busy = false
        tryCompare(host.downloadScreen, "phase", "result")
        host.queueState.state = "DOWNLOADING"
        host.queueState.progress = 0.42
        host.queueState.revision++
        compare(host.downloadScreen.job.index, 2)
        compare(host.downloadScreen.actionLabel, "Downloading… 42%")
        verify(!host.downloadScreen.actionEnabled)
        verify(host.downloadScreen.handleNavigation("accept"))
        compare(host.closeSpy.count, 0)
        host.queueState.state = "IMPORTED"; host.queueState.revision++
        host.detailsState.local = true
        host.detailsState.launch_discovery_busy = true
        compare(host.downloadScreen.actionLabel, "Checking play setup…")
        verify(!host.downloadScreen.actionEnabled)
        host.detailsState.launch_discovery_busy = false
        compare(host.downloadScreen.actionLabel, "Finish play setup")
        host.downloadScreen.activateReview()
        compare(host.setupSpy.count, 1)
        host.detailsState.can_launch = true
        compare(host.downloadScreen.actionLabel, "Play now")
        verify(host.downloadScreen.handleNavigation("accept"))
        compare(host.playSpy.count, 1)
        compare(host.closeSpy.count, 0)
    }

    function test_resume_retry_and_reopen_stay_on_the_selected_game() {
        const host = createTemporaryObject(hostComponent, testCase)
        host.queueState.state = "PAUSED"; host.queueState.revision++
        host.downloadScreen.resetForGame()
        compare(host.downloadScreen.phase, "result")
        compare(host.downloadScreen.actionLabel, "Resume download")
        host.downloadScreen.activateReview()
        compare(host.queueState.resumed, "exact-job")
        host.queueState.state = "FAILED"; host.queueState.revision++
        compare(host.downloadScreen.actionLabel, "Retry installation")
        host.downloadScreen.activateReview()
        compare(host.queueState.retried, "exact-job")
        host.downloadScreen.gameId = "different-game"
        host.downloadScreen.resetForGame()
        compare(host.downloadScreen.phase, "candidates")
        compare(host.downloadScreen.job, null)
    }

    function test_back_is_available_while_queueing_without_cancelling_download() {
        const host = createTemporaryObject(hostComponent, testCase)
        host.downloadScreen.beginReview()
        host.detailsState.download_preflight_ready = true
        host.downloadScreen.activateReview()
        compare(host.downloadScreen.phase, "queue")
        verify(host.downloadScreen.handleNavigation("back"))
        compare(host.closeSpy.count, 1)
        verify(host.detailsState.download_busy)
    }

    function test_manual_download_returns_to_the_same_installation() {
        const host = createTemporaryObject(hostComponent, testCase)
        compare(host.downloadScreen.phase, "candidates")
        host.queueState.state = "DOWNLOADING"; host.queueState.revision++
        tryCompare(host.downloadScreen, "phase", "result")
        compare(host.downloadScreen.job.id, "exact-job")
    }

    function test_missing_imported_files_and_cancelled_jobs_allow_a_new_selection() {
        const host = createTemporaryObject(hostComponent, testCase)
        for (const state of ["IMPORTED", "CANCELLED"]) {
            host.queueState.state = state; host.queueState.revision++
            host.downloadScreen.resetForGame()
            compare(host.downloadScreen.phase, "candidates")
        }
    }

    function test_reopening_while_adding_download_stays_in_progress() {
        const host = createTemporaryObject(hostComponent, testCase)
        host.detailsState.download_busy = true
        host.downloadScreen.resetForGame()
        compare(host.downloadScreen.phase, "queue")
        verify(host.downloadScreen.queuePending)
        host.downloadScreen.active = false
        host.detailsState.download_busy = false
        tryCompare(host.downloadScreen, "phase", "result")
        verify(!host.downloadScreen.activeFocus)
    }

    function test_back_from_review_keeps_the_ranked_list_in_couch_mode() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        host.downloadScreen.beginReview()
        compare(host.downloadScreen.phase, "review")
        verify(host.downloadScreen.handleNavigation("back"))
        compare(host.downloadScreen.phase, "candidates")
        compare(host.closeSpy.count, 0)
        verify(host.downloadScreen.handleNavigation("back"))
        compare(host.closeSpy.count, 1)
    }

    function test_terminal_block_never_retries_or_queues() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        host.downloadScreen.beginReview()
        compare(host.downloadScreen.phase, "review")
        compare(host.detailsState.inspectedIndex, 0)

        // Already installed: the action turns into a terminal label and
        // activating it neither re-checks nor queues.
        host.detailsState.download_preflight_ready = false
        host.detailsState.download_preflight_terminal = true
        host.detailsState.download_preflight_status = "The exact destination already exists."
        compare(host.downloadScreen.actionLabel, "Already in library")
        host.detailsState.inspectedIndex = -1
        host.downloadScreen.activateReview()
        compare(host.detailsState.inspectedIndex, -1)
        compare(host.detailsState.queuedIndex, -1)
        compare(host.downloadScreen.phase, "review")

        // Transient blocks still retry the check.
        host.detailsState.download_preflight_terminal = false
        host.downloadScreen.activateReview()
        compare(host.detailsState.inspectedIndex, 0)
    }

    function test_empty_download_state_imports_a_torrent() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        host.detailsState.candidateCount = 0
        host.detailsState.detail_revision += 1
        tryCompare(host.downloadScreen, "candidateCount", 0)
        compare(host.downloadScreen.selectedCandidate, -1)
        verify(host.downloadScreen.handleNavigation("accept"))
        compare(host.importSpy.count, 1)

        host.detailsState.torrent_loading = true
        verify(host.downloadScreen.handleNavigation("accept"))
        compare(host.importSpy.count, 1)
    }
}
