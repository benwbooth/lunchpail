import QtQuick

// Opt-in native regression: use a copied state/media profile. Never launches games.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    property int step: 0
    property bool capturing: false
    property string lastSource: ""
    property int stableTicks: 0
    property bool progressCaptured: false
    readonly property string firstGame: "2d6cb4b2-a219-4c40-9b31-ac466a77e88c"
    readonly property string nextGame: app.argumentValue("--media-probe-game") || "9697a5eb-e0b4-4f24-8d43-672701414ee7"
    readonly property string platform: "Nintendo Entertainment System"
    Component.onCompleted: { view.sfxEnabled = false; view.windowActive = false }
    function fail(message) { console.error("LUNCHPAIL_COUCH_MEDIA_FAILED " + message); Qt.exit(2) }
    function capture(name) {
        capturing = true
        view.grabToImage(result => {
            const prefix = app.argumentValue("--screenshot-output")
            if (prefix && !result.saveToFile(prefix + "-" + name + ".png")) { fail("capture " + name); return }
            console.log("LUNCHPAIL_COUCH_MEDIA_CAPTURE " + name + " game=" + view.selectedGameId + " source=" + view.previewVideoUrl)
            capturing = false
        })
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.view.active && !probe.view.platformWheelOpen) {
                const source = probe.view.previewVideoUrl.toString()
                if (source.indexOf("/platforms/") >= 0) { probe.fail("system video leaked into game browser"); return }
                if (probe.view.systemVideoPreview.playing) { probe.fail("hidden system video still playing"); return }
            }
            if (probe.step === 0) {
                probe.app.selectCouchPlatform(probe.platform)
                probe.library.save_couch_view_style("wheel")
                probe.step = 1
            } else if (probe.step === 1) {
                if (!probe.view.focusGameById(probe.firstGame) || probe.view.selectedGameId !== probe.firstGame) return
                if (!probe.view.gameVideoPreview.playing) return
                probe.lastSource = probe.view.previewVideoUrl.toString()
                probe.capture("first-game"); probe.step = 2
            } else if (probe.step === 2) {
                probe.view.openPlatformWheel(); probe.step = 3
            } else if (probe.step === 3) {
                if (!probe.view.systemVideoPreview.playing) return
                probe.capture("platform"); probe.step = 4
            } else if (probe.step === 4) {
                probe.view.closePlatformWheel()
                if (!probe.view.focusGameById(probe.nextGame)) { probe.fail("second game unavailable"); return }
                probe.step = 5
            } else if (probe.step === 5) {
                if (probe.view.selectedGameId !== probe.nextGame || probe.view.entryPending) return
                if (probe.view.previewVideoUrl.toString() === probe.lastSource) { probe.fail("old game video survived selection"); return }
                probe.capture("next-game-loading"); probe.step = 6
            } else if (probe.step === 6) {
                const status = JSON.parse(probe.library.couch_theme_status_json || "{}")
                if (status.key && status.key !== "game:" + probe.nextGame) { probe.fail("wrong theme progress identity"); return }
                const queue = probe.library.automatic_video_state(probe.nextGame)
                console.log("LUNCHPAIL_COUCH_MEDIA_PROGRESS game=" + probe.nextGame + " video=" + queue + " percent=" + probe.library.media_active_progress + " theme=" + status.phase + " theme_percent=" + status.progress)
                if (!probe.progressCaptured && queue === "downloading" && probe.library.media_active_progress > 0
                        && probe.library.media_active_progress < 100) {
                    probe.progressCaptured = true; probe.capture("next-game-download"); return
                }
                if (!probe.view.gameVideoPreview.playing || probe.view.gameVideoPreview.position < 500) return
                if (++probe.stableTicks < 3) return
                probe.capture("next-game-ready"); probe.step = 7
            } else if (probe.step === 7) {
                console.log("LUNCHPAIL_COUCH_MEDIA_READY selected_video=pass system_isolation=pass progress_identity=pass")
                Qt.quit()
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: probe.fail("timeout step " + probe.step) }
}
