import QtQuick

// Native integration regression: real Action 52 metadata, real keyboard Escape,
// and real application dialogs. Opt-in and isolated state; never queues a ROM.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var details
    required property var gameTools
    required property var settings
    required property var downloads
    property var keys: null
    property int stage: 0
    property int section: 0
    property double started: 0
    property bool capturing: false
    property bool dispatching: false
    readonly property string game: "6d9c34f9-df88-4aaf-9462-3617899039e3"
    readonly property string platform: "Nintendo Entertainment System"
    readonly property var sections: ["launch", "display", "mods", "achievements", "files", "media", "artwork", "themes", "activity", "collections", "related", "catalog"]
    function fail(message) { console.error("LUNCHPAIL_COUCH_JOURNEY_FAILED stage=" + stage + " " + message); Qt.exit(2) }
    function pressEscape() {
        dispatching = true
        console.log("LUNCHPAIL_COUCH_JOURNEY_ESCAPE stage=" + stage + " active=" + app.active
                    + " enabled=" + view.inputEnabled + " focus=" + app.activeFocusItem)
        if (!keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)) fail("key event rejected")
        dispatching = false
    }
    function capture(name) {
        capturing = true
        view.grabToImage(function(result) {
            if (!result.saveToFile(app.argumentValue("--screenshot-output").replace(/\.png$/, "-" + name + ".png"))) fail("capture")
            capturing = false
        })
    }
    Component.onCompleted: keys = Qt.createQmlObject('import QtTest 1.2; TestEvent {}', probe, "JourneyKeys")
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || probe.dispatching || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.stage === 0) {
                probe.app.width = 1920; probe.app.height = 1080
                probe.app.selectedGameId = probe.game
                probe.app.enterCouchMode()
                probe.view.sfxEnabled = false
                probe.view.beginGameHandoff(probe.game, probe.platform)
                probe.stage = 1
            } else if (probe.stage === 1) {
                if (probe.view.entryPending || probe.view.selectedGameId !== probe.game) {
                    probe.view.focusGameById(probe.game); return
                }
                probe.started = Date.now()
                probe.view.requestDetails(); probe.stage = 2
            } else if (probe.stage === 2 || probe.stage === 4) {
                console.log("LUNCHPAIL_COUCH_JOURNEY_DETAILS game=" + probe.details.game_id + " selected=" + probe.view.selectedGameId + " loading=" + probe.details.loading + " panel=" + probe.details.panel_open)
                if (!probe.view.detailsCurrent || probe.details.loading) return
                if (probe.details.title !== "Action 52" || !probe.details.description) return probe.fail("metadata missing")
                console.log("LUNCHPAIL_COUCH_JOURNEY_LOADED stage=" + probe.stage + " ms=" + (Date.now() - probe.started))
                if (probe.stage === 2) { probe.capture("action52-details"); probe.stage = 3 }
                else { probe.pressEscape(); probe.stage = 5 }
            } else if (probe.stage === 3) {
                // Cancelled request retains identity: reopening must reload.
                probe.details.close_panel()
                probe.view.closeOverlay()
                probe.started = Date.now(); probe.view.requestDetails(); probe.stage = 4
            } else if (probe.stage === 5) {
                if (probe.view.overlayOpen || !probe.app.couchModeActive)
                    return probe.fail("details Escape overlay=" + probe.view.overlayOpen
                                      + " couch=" + probe.app.couchModeActive + " focus=" + probe.app.activeFocusItem
                                      + " enabled=" + probe.view.inputEnabled)
                probe.app.openCouchGameTool(probe.sections[probe.section]); probe.stage = 6
            } else if (probe.stage === 6) {
                if (!probe.gameTools.visible) return probe.fail("game tool did not open")
                probe.pressEscape(); probe.stage = 7
            } else if (probe.stage === 7) {
                if (probe.gameTools.visible || !probe.app.couchModeActive) return probe.fail("tool Escape " + probe.sections[probe.section])
                if (++probe.section < probe.sections.length) probe.stage = 5
                else { probe.app.openCouchGameTool("metadata"); probe.stage = 20 }
            } else if (probe.stage === 20) {
                if (!probe.details.metadata_open) return probe.fail("metadata not open")
                probe.pressEscape(); probe.stage = 21
            } else if (probe.stage === 21) {
                if (probe.details.metadata_open) return probe.fail("metadata Escape")
                probe.app.openSettingsFor("general"); probe.stage = 22
            } else if (probe.stage === 22) {
                probe.app.openCouchGameTool("controllers"); probe.stage = 23
            } else if (probe.stage === 23) {
                probe.pressEscape(); probe.stage = 8
            } else if (probe.stage === 8) {
                if (!probe.settings.visible) return probe.fail("settings not open")
                probe.pressEscape(); probe.stage = 9
            } else if (probe.stage === 9) {
                if (probe.settings.visible) return probe.fail("settings Escape")
                probe.downloads.open(); probe.stage = 10
            } else if (probe.stage === 10) {
                probe.pressEscape(); probe.stage = 11
            } else if (probe.stage === 11) {
                if (probe.downloads.visible) return probe.fail("downloads Escape")
                probe.details.close_panel()
                probe.view.activateAction(0); probe.stage = 12
            } else if (probe.stage === 12) {
                if (probe.details.loading) return
                if (!probe.view.downloadOverlayOpen) return probe.fail("main action did not open installation")
                probe.capture("action52-install"); probe.stage = 24
            } else if (probe.stage === 24) {
                probe.pressEscape(); probe.stage = 13
            } else if (probe.stage === 13) {
                if (probe.view.downloadOverlayOpen) return probe.fail("installation Escape")
                probe.pressEscape(); probe.stage = 14
            } else if (probe.stage === 14) {
                if (!probe.view.platformWheelOpen || !probe.app.couchModeActive) return probe.fail("game wheel did not go to platform wheel")
                probe.pressEscape(); probe.stage = 15
            } else if (probe.stage === 15) {
                if (probe.app.couchModeActive) return probe.fail("platform Escape did not exit")
                console.log("LUNCHPAIL_COUCH_JOURNEY_READY Action52=loaded reopened=loaded keyboard_escape=pass tool_sections=12 metadata=pass nested_controllers=pass settings=pass downloads=pass install=pass wheel_hierarchy=pass queued=none")
                Qt.quit()
            }
        }
    }
    Timer { interval: 150000; running: true; onTriggered: probe.fail("timeout") }
}
