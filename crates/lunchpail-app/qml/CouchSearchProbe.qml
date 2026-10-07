import QtQuick

// Real keyboard/catalog integration in an isolated profile. No microphone,
// assistant request, download, or emulator is started by this probe.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var speech
    property int step: -1
    property int fullCount: 0
    property int platformCount: 0
    property int assistantTurn: 0
    property bool capturing: false
    property var events: null
    Component.onCompleted: events = Qt.createQmlObject('import QtTest 1.2; TestEvent {}', probe, "BrowseKeys")
    function fail(reason) {
        console.error("LUNCHPAIL_COUCH_SEARCH_FAILED step=" + step + " " + reason
                      + " platformOpen=" + view.platformWheelOpen + " filterFocus=" + view.filterPanel.inputFocused
                      + " focus=" + app.activeFocusItem + " query=" + view.browseQuery)
        Qt.exit(2)
    }
    function key(code) { events.keyClick(code, Qt.NoModifier, 0) }
    function findItem(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = findItem(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function capture(name) {
        capturing = true
        view.grabToImage(function(result) {
            const path = app.argumentValue("--screenshot-output") + "-" + name + ".png"
            if (!result.saveToFile(path)) { fail("capture " + name); return }
            console.log("LUNCHPAIL_COUCH_SEARCH_CAPTURE " + name + " games=" + library.filtered_count
                        + " platforms=" + library.filtered_platform_count)
            capturing = false; step++
        }, Qt.size(app.width, app.height))
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.loading
                    || probe.library.filtering || !probe.view.active) return
            if (probe.speech.busy || probe.speech.listening) { probe.fail("microphone activated"); return }
            if (probe.step >= 0 && probe.view.assistant.turn_number !== probe.assistantTurn) {
                probe.fail("typing or opening a panel invoked the assistant"); return
            }
            if (probe.step === -1) {
                probe.assistantTurn = probe.view.assistant.turn_number
                probe.app.selectedPlatform = "Nintendo Entertainment System"
                probe.view.searchRequested("")
                probe.view.platformSearchRequested("")
                probe.library.apply_filter("", probe.app.selectedPlatform, "")
                probe.app.width = 1920; probe.app.height = 1080
                probe.app.requestActivate()
                probe.step++
            } else if (probe.step === 0) {
                if (!probe.view.feedbackReady) return
                probe.fullCount = probe.library.filtered_count
                probe.platformCount = probe.library.platform_count
                probe.view.openPlatformWheel()
                probe.key(Qt.Key_S); probe.key(Qt.Key_N); probe.key(Qt.Key_E); probe.key(Qt.Key_S)
                if (probe.view.searchOpen || !probe.view.platformWheelOpen
                        || probe.library.platform_search !== "snes" || !probe.view.filterPanel.inputFocused) {
                    probe.fail("platform type-to-filter/focus"); return
                }
                probe.step++
            } else if (probe.step === 1) {
                if (probe.library.filtered_platform_count <= 0 || probe.library.filtered_platform_count >= probe.platformCount
                        || probe.library.filtered_count !== probe.fullCount || probe.view.searchText !== "") {
                    probe.fail("platform filter changed game list or failed to narrow systems"); return
                }
                probe.capture("platform-filter-1080p")
            } else if (probe.step === 2) {
                probe.key(Qt.Key_Return)
                if (probe.view.filterPanel.inputFocused || !probe.view.platformWheelOpen) { probe.fail("enter activated platform"); return }
                probe.key(Qt.Key_Space)
                const field = probe.findItem(probe.view.searchPanel, "couchSearchField")
                if (!probe.view.searchOpen || !probe.view.platformWheelOpen || !field || field.text !== "") {
                    probe.fail("space did not open blank assistant over platforms"); return
                }
                probe.key(Qt.Key_H); probe.key(Qt.Key_I)
                if (field.text !== "hi" || probe.library.platform_search !== "snes") { probe.fail("assistant typing filtered systems"); return }
                probe.key(Qt.Key_Escape)
                if (probe.view.searchOpen || !probe.view.platformWheelOpen || probe.library.platform_search !== "snes") {
                    probe.fail("assistant close lost platform context"); return
                }
                const selectedPlatform = probe.library.filtered_platform_name_at(0)
                if (!probe.view.platformBrowser.currentItem
                        || probe.view.platformBrowser.currentItem.platformName !== selectedPlatform) {
                    probe.fail("filtered platform artwork/identity"); return
                }
                probe.view.choosePlatform(0)
                if (probe.app.selectedPlatform !== selectedPlatform || probe.view.platformWheelOpen) {
                    probe.fail("filtered platform selection used an unfiltered index"); return
                }
                probe.view.openPlatformWheel()
                probe.view.openFilter("no-such-platform-987654321")
                probe.step++
            } else if (probe.step === 3) {
                if (probe.library.filtered_platform_count !== 0 || !probe.view.platformWheelOpen) { probe.fail("empty platform results"); return }
                probe.key(Qt.Key_Escape)
                probe.key(Qt.Key_Escape)
                if (!probe.view.active || !probe.view.platformWheelOpen || probe.library.platform_search !== "") {
                    probe.fail("escape did not clear empty platform filter before exit"); return
                }
                probe.step++
            } else if (probe.step === 4) {
                if (probe.library.filtered_platform_count !== probe.platformCount) { probe.fail("platform restore"); return }
                probe.view.choosePlatform(probe.view.platformIndexForName("Nintendo Entertainment System"))
                probe.view.searchRequested("")
                probe.step++
            } else if (probe.step === 5) {
                if (probe.view.platformWheelOpen || probe.library.current_platform !== "Nintendo Entertainment System") {
                    probe.fail("platform selection"); return
                }
                probe.view.forceActiveFocus()
                probe.key(Qt.Key_M); probe.key(Qt.Key_A); probe.key(Qt.Key_R); probe.key(Qt.Key_I); probe.key(Qt.Key_O)
                if (probe.view.searchOpen || probe.view.searchText !== "mario" || !probe.view.filterPanel.inputFocused) {
                    probe.fail("game type-to-filter/focus"); return
                }
                probe.step++
            } else if (probe.step === 6) {
                if (probe.library.filtered_count <= 0 || probe.library.filtered_count >= probe.fullCount) {
                    probe.fail("game filter did not narrow current shelf"); return
                }
                probe.capture("game-filter-1080p")
            } else if (probe.step === 7) {
                probe.view.openFilter("super")
                probe.key(Qt.Key_Space); probe.key(Qt.Key_M)
                if (probe.view.searchOpen || probe.view.searchText !== "super m") { probe.fail("space inside game query"); return }
                probe.app.width = 1280; probe.app.height = 720
                probe.step++
            } else if (probe.step === 8) {
                if (probe.library.filtered_count <= 0 || probe.library.filtered_count >= probe.fullCount) { probe.fail("multiword filter"); return }
                probe.capture("game-filter-720p")
            } else if (probe.step === 9) {
                probe.key(Qt.Key_Return)
                if (probe.view.filterPanel.inputFocused || probe.view.overlayOpen || probe.view.downloadOverlayOpen) {
                    probe.fail("enter activated game"); return
                }
                probe.key(Qt.Key_Space)
                if (!probe.view.searchOpen || probe.view.searchText !== "super m"
                        || probe.findItem(probe.view.searchPanel, "couchSearchField").text !== "") {
                    probe.fail("space with retained game filter"); return
                }
                probe.capture("assistant-720p")
            } else if (probe.step === 10) {
                probe.key(Qt.Key_Escape)
                if (probe.view.searchOpen || probe.view.searchText !== "super m") { probe.fail("assistant lost game filter"); return }
                probe.key(Qt.Key_Escape)
                if (probe.view.searchText !== "" || probe.view.platformWheelOpen) { probe.fail("game filter clear before back"); return }
                probe.step++
            } else if (probe.step === 11) {
                if (probe.library.filtered_count !== probe.fullCount) { probe.fail("game shelf restore"); return }
                probe.view.openOverlay("menu")
                probe.view.activateMenuAction(8)
                if (probe.view.searchOpen || !probe.view.filterPanel.inputFocused) { probe.fail("menu filter entry"); return }
                probe.view.filterPanel.finish()
                probe.view.openPlatformWheel()
                // Simulate only the controller's qualified-utterance signal.
                // Its idle/mute/wake gating is covered separately by QtTest.
                probe.findItem(probe.view, "couchHandsFreeController").commandStarted()
                if (!probe.view.searchOpen || !probe.view.platformWheelOpen) { probe.fail("qualified voice did not open assistant"); return }
                probe.key(Qt.Key_Escape)
                if (!probe.view.platformWheelOpen) { probe.fail("voice panel lost browser"); return }
                console.log("LUNCHPAIL_COUCH_SEARCH_READY platform_filter=true game_filter=true empty_results=true multiword=true space_assistant=true voice_ui=simulated keyboard=native microphone=off assistant_requests=0")
                Qt.quit()
            }
        }
    }
    Timer { interval: 120000; running: true; onTriggered: probe.fail("timeout") }
}
