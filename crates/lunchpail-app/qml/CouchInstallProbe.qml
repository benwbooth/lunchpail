import QtQuick

// Cold and warm wheel-to-install transitions against the real catalog.
// This opens the candidate page only: never queues files or starts an emulator.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var details
    required property var desktopContent
    required property var desktopDetails
    property int stage: 0
    property int scenario: 0
    property double started: 0
    property bool finishing: false
    property var events: null
    Component.onCompleted: events = Qt.createQmlObject('import QtTest 1.2; TestEvent {}', probe, "InstallMouse")
    function findItem(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = findItem(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function clickInstall() {
        const row = findItem(view, "couchPrimaryActions")
        if (!row) return false
        for (let i = 0; i < row.children.length; ++i) {
            const button = row.children[i]
            if (button.index === 0)
                return events.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        }
        return false
    }
    readonly property string platform: "Nintendo Entertainment System"
    readonly property var games: [
        "e2384ec5-91e0-41c1-aacf-7e092cfdb14e",
        "e2384ec5-91e0-41c1-aacf-7e092cfdb14e",
        "6d9c34f9-df88-4aaf-9462-3617899039e3",
        "e2384ec5-91e0-41c1-aacf-7e092cfdb14e"
    ]
    function state() {
        return "scenario=" + scenario + " stage=" + stage + " selected=" + view.selectedGameId
            + " details=" + details.game_id + " panel=" + details.panel_open + " loading=" + details.loading
            + " current=" + view.detailsCurrent + " pending=" + view.pendingPrimaryGameId
            + " overlay=" + view.overlayOpen + " install=" + view.downloadOverlayOpen
            + " retry=" + view.detailsRetryAvailable + " message=" + details.message
            + " enabled=" + view.inputEnabled + " focus=" + app.activeFocusItem + " rootSelected=" + app.selectedGameId
            + " shelfPlatform=" + library.current_platform + " entryPending=" + view.entryPending
            + " viewport=" + app.width + "x" + app.height
    }
    function finish(ok, message) {
        if (finishing) return
        finishing = true
        console.log((ok ? "LUNCHPAIL_COUCH_INSTALL_READY " : "LUNCHPAIL_COUCH_INSTALL_FAILED ") + message + " " + state())
        const path = app.argumentValue("--screenshot-output")
        if (!path) { Qt.exit(ok ? 0 : 2); return }
        view.grabToImage(function(image) {
            image.saveToFile(path)
            if (!ok) {
                probe.events.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
                console.log("LUNCHPAIL_COUCH_INSTALL_FAILED_ESCAPE " + probe.state())
            }
            Qt.exit(ok ? 0 : 2)
        })
    }
    Timer {
        interval: 250; repeat: true; running: !probe.finishing
        onTriggered: {
            if (!probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.stage === 0) {
                probe.details.close_panel()
                probe.app.selectedGameId = probe.games[probe.scenario]
                if (!probe.app.couchModeActive) probe.app.enterCouchMode()
                probe.view.sfxEnabled = false
                probe.view.beginGameHandoff(probe.games[probe.scenario], probe.platform)
                probe.started = Date.now()
                probe.stage = 1
            } else if (probe.stage === 1) {
                if (probe.view.entryPending || probe.view.selectedGameId !== probe.games[probe.scenario]) {
                    if (Date.now() - probe.started > 10000) return probe.finish(false, "game selection did not settle")
                    probe.view.focusGameById(probe.games[probe.scenario]); return
                }
                if (probe.desktopContent.enabled || probe.desktopDetails.enabled)
                    return probe.finish(false, "covered desktop still accepts input")
                probe.started = Date.now()
                console.log("LUNCHPAIL_COUCH_INSTALL_PRESS " + probe.state())
                if (!probe.clickInstall()) return probe.finish(false, "mouse click rejected")
                probe.stage = 2
            } else if (probe.stage === 2) {
                console.log("LUNCHPAIL_COUCH_INSTALL_WAIT " + probe.state())
                if (Date.now() - probe.started > 25000) return probe.finish(false, "wheel-to-install timed out")
                if (!probe.view.downloadOverlayOpen) return
                if (probe.details.game_id !== probe.games[probe.scenario] || !probe.view.detailsCurrent)
                    return probe.finish(false, "wrong game installation")
                if (probe.details.torrent_loading) return
                if (probe.details.download_candidate_count() === 0)
                    return probe.finish(false, "no download candidates")
                const firstSource = probe.details.download_candidate_source_at(0)
                if (firstSource.indexOf("No-Intro") < 0)
                    return probe.finish(false, "No-Intro was not preferred: " + firstSource)
                const firstBundle = probe.details.download_source_bundle_at(0)
                if (probe.details.bundle_title_at(firstBundle) !== firstSource)
                    return probe.finish(false, "desktop and couch source rankings disagree")
                console.log("LUNCHPAIL_COUCH_INSTALL_SOURCE scenario=" + probe.scenario
                    + " first=" + firstSource + " file=" + probe.details.download_candidate_name_at(0))
                console.log("LUNCHPAIL_COUCH_INSTALL_CASE scenario=" + probe.scenario + " ms=" + (Date.now() - probe.started))
                if (!probe.events.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)) return probe.finish(false, "Escape event rejected")
                probe.stage = 3
            } else if (probe.stage === 3) {
                if (probe.view.downloadOverlayOpen || probe.view.overlayOpen || !probe.app.couchModeActive)
                    return probe.finish(false, "Escape did not return to wheel")
                if (++probe.scenario === probe.games.length) {
                    probe.scenario--
                    probe.app.openCouchWorkspace("library")
                    probe.stage = 4
                    return
                }
                probe.stage = 0
            } else if (probe.stage === 4) {
                if (!probe.desktopContent.enabled || !probe.desktopDetails.enabled)
                    return probe.finish(false, "library workspace controls disabled")
                probe.app.openCouchWorkspace("game")
                probe.stage = 5
            } else if (probe.stage === 5) {
                if (probe.desktopContent.enabled || !probe.desktopDetails.enabled)
                    return probe.finish(false, "game workspace input isolation incorrect")
                probe.app.closeCouchWorkspace()
                probe.stage = 6
            } else if (probe.stage === 6) {
                if (probe.desktopContent.enabled || probe.desktopDetails.enabled)
                    return probe.finish(false, "returning to wheel did not disable desktop")
                return probe.finish(true, "mouse=pass cold=pass reopened=pass switched=pass returned=pass escape=pass workspaces=pass no_intro=pass queued=none")
            }
        }
    }
    Timer { interval: 150000; running: true; onTriggered: probe.finish(false, "probe timeout") }
}
