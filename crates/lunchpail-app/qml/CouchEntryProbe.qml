import QtQuick

// Explicit opt-in: isolated state/media only. No emulator or microphone is used.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var details
    property int step: 0
    property int stableTicks: 0
    property int cue: 0
    property bool capturing: false
    readonly property string gameId: "2d6cb4b2-a219-4c40-9b31-ac466a77e88c"
    readonly property string platform: "Nintendo Entertainment System"
    readonly property var cues: ["move", "wheel", "wall", "flow", "focus", "confirm", "back", "switch", "enter", "launch"]
    function fail(message) { console.error("LUNCHPAIL_COUCH_ENTRY_FAILED " + message); Qt.exit(2) }
    function checkSelection() {
        if (!view.active || view.entryPending || !view.gameBrowser.currentItem) return false
        if (view.selectedGameId !== gameId || view.gameBrowser.currentItem.gameId !== gameId
                || view.selectedPlatform !== platform || app.selectedPlatform !== platform
                || library.current_platform !== platform) {
            fail("identity or platform changed at step " + step + ": " + view.selectedGameId + " / " + app.selectedPlatform)
            return false
        }
        return true
    }
    Connections {
        target: probe.view
        function onSelectedGameIdChanged() {
            console.log("LUNCHPAIL_COUCH_ENTRY_SELECTION step=" + probe.step + " game=" + probe.view.selectedGameId + " pending=" + probe.view.entryPending)
        }
    }
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.filtering) return
            if (probe.step === 0) {
                probe.library.save_couch_state("platform", "Super Nintendo Entertainment System")
                probe.app.selectCouchPlatform("Sega Genesis")
                probe.step = 1
            } else if (probe.step === 1) {
                if (probe.library.couch_state_saving) return
                probe.app.openGame(probe.gameId, 1283, "Faxanadu", probe.platform, false, true)
                probe.step = 2
            } else if (probe.step === 2) {
                if (probe.details.loading || probe.details.game_id !== probe.gameId || !probe.details.panel_open) return
                // A stale grid selection must not win over the open details page.
                probe.app.selectedGameId = "9697a5eb-e0b4-4f24-8d43-672701414ee7"
                probe.app.enterCouchMode()
                probe.step = 3
            } else if (probe.step === 3) {
                if (!probe.checkSelection() || ++probe.stableTicks < 4) return
                if (probe.library.couch_platform !== probe.platform) { probe.fail("platform was not persisted"); return }
                probe.capturing = true
                probe.view.grabToImage(function(result) {
                    const prefix = probe.app.argumentValue("--screenshot-output")
                    if (prefix && !result.saveToFile(prefix + "-faxanadu.png")) { probe.fail("capture"); return }
                    probe.capturing = false; probe.view.openPlatformWheel(); probe.step = 4
                })
            } else if (probe.step === 4) {
                if (!probe.view.platformBrowser.currentItem) return
                if (probe.view.platformBrowser.currentItem.platformName !== probe.platform) { probe.fail("platform picker lost the game system"); return }
                probe.view.closePlatformWheel(); probe.step = 5
            } else if (probe.step === 5) {
                if (!probe.view.feedbackReady) return
                if (probe.cue < probe.cues.length) {
                    const kind = probe.cues[probe.cue++]
                    if (!probe.view.soundFeedback.play(kind)) { probe.fail("sound " + kind + " did not play"); return }
                    return
                }
                probe.view.sfxEnabled = false
                if (probe.view.soundFeedback.play("confirm")) { probe.fail("sound ignored mute"); return }
                probe.view.sfxEnabled = true
                probe.app.exitCouchMode()
                probe.details.close_panel()
                probe.app.selectCouchPlatform("Sega Genesis")
                probe.step = 6
            } else if (probe.step === 6) {
                probe.app.selectedGameId = probe.gameId
                probe.app.enterCouchMode(); probe.step = 7; probe.stableTicks = 0
            } else if (probe.step === 7) {
                if (!probe.checkSelection() || ++probe.stableTicks < 3) return
                if (probe.library.loading) return
                probe.app.exitCouchMode()
                if (probe.view.soundFeedback.play("confirm")) { probe.fail("inactive sound played"); return }
                console.log("LUNCHPAIL_COUCH_ENTRY_READY game=Faxanadu platform=NES details_priority=pass grid_entry=pass cues=" + probe.cues.length + " muted=pass emulator=off microphone=off")
                Qt.quit()
            }
        }
    }
    Timer { interval: 150000; running: true; onTriggered: probe.fail("timeout step " + probe.step) }
}
