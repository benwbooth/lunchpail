import QtQuick

// Isolated-profile integration check; never opens a microphone or downloads games.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var speech
    property int step: -1
    property int fullCount: 0
    property bool capturing: false
    function fail(reason) { console.error("LUNCHPAIL_COUCH_SEARCH_FAILED " + reason); Qt.exit(2) }
    function capture(name) {
        capturing = true
        view.grabToImage(function(result) {
            const path = app.argumentValue("--screenshot-output") + "-" + name + ".png"
            if (!result.saveToFile(path)) { fail("capture " + name); return }
            console.log("LUNCHPAIL_COUCH_SEARCH_CAPTURE " + name + " count=" + library.filtered_count)
            capturing = false; step++
        }, Qt.size(app.width, app.height))
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.loading
                    || probe.library.filtering || !probe.view.active) return
            if (probe.speech.busy || probe.speech.listening) { probe.fail("microphone was activated without a request"); return }
            if (probe.step === -1) {
                probe.app.selectedPlatform = "Nintendo Entertainment System"
                probe.view.searchRequested("")
                probe.library.apply_filter("", probe.app.selectedPlatform, "")
                probe.step++
            } else if (probe.step === 0) {
                if (!probe.view.feedbackReady) return
                probe.app.width = 1920; probe.app.height = 1080
                probe.fullCount = probe.library.filtered_count
                const key = { key: Qt.Key_M, text: "m", modifiers: Qt.NoModifier, accepted: false }
                probe.view.handleKey(key)
                if (!key.accepted || !probe.view.searchOpen || probe.view.searchText !== "m") { probe.fail("type to search"); return }
                probe.view.searchPanel.queryEdited("Mario")
                probe.step++
            } else if (probe.step === 1) {
                if (probe.view.searchText !== "Mario" || probe.library.filtered_count >= probe.fullCount
                        || probe.library.filtered_count <= 0) { probe.fail("library did not filter"); return }
                probe.view.searchPanel.open("Mario")
                probe.capture("search-1080p")
            } else if (probe.step === 2) {
                probe.app.width = 1280; probe.app.height = 720
                probe.step++
            } else if (probe.step === 3) {
                probe.capture("search-720p")
            } else if (probe.step === 4) {
                probe.view.handleNavigation("back")
                if (probe.view.searchOpen || probe.view.searchText !== "Mario") { probe.fail("back must retain results"); return }
                probe.view.handleNavigation("back")
                if (!probe.view.active || probe.view.searchText !== "") { probe.fail("second back must clear search before exit"); return }
                probe.step++
            } else if (probe.step === 5) {
                if (probe.library.filtered_count !== probe.fullCount) { probe.fail("clear did not restore shelf"); return }
                probe.view.openOverlay("menu")
                probe.view.activateMenuAction(8)
                if (!probe.view.searchOpen) { probe.fail("controller search entry"); return }
                probe.view.searchPanel.open("Super Mario Brothers")
                probe.view.searchPanel.queryEdited("Super Mario Brothers")
                probe.step++
            } else if (probe.step === 6) {
                if (probe.library.filtered_count <= 0 || probe.library.filtered_count >= probe.fullCount) {
                    probe.fail("spoken title alias did not filter"); return
                }
                probe.capture("voice-query")
            } else if (probe.step === 7) {
                probe.view.closeSearch()
                console.log("LUNCHPAIL_COUCH_SEARCH_READY typing=true filtering=true spoken_alias=true controller=true microphone=off sounds=loaded")
                Qt.quit()
            }
        }
    }
    Timer { interval: 120000; running: true; onTriggered: probe.fail("timeout at step " + probe.step) }
}
