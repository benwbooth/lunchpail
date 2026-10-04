import QtQuick

// Opt-in, read-only UI exercise. Use an isolated --state-database: selecting
// presentation styles persists preferences, but this never launches a game.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var details
    required property var toolsPage
    required property var systemPage
    required property var boxPage
    required property var videoPage
    required property var videoOutput
    required property var videoPlayer
    property int step: -1
    property bool capturing: false
    property int waits: 0
    readonly property var styles: ["wheel", "shelf", "wall", "album"]
    readonly property var sections: ["launch", "display", "mods", "achievements", "files", "media", "artwork", "themes", "activity", "collections", "related", "catalog"]
    readonly property int toolEnd: 9 + sections.length

    function fail(message) { console.error("LUNCHPAIL_COUCH_POLISH_FAILED " + message); Qt.exit(2) }
    function capture(name) {
        capturing = true
        const prefix = app.argumentValue("--screenshot-output")
        const target = videoPage.visible ? videoPage.contentItem
                     : boxPage.visible ? boxPage.contentItem
                     : systemPage.visible ? systemPage.contentItem
                     : toolsPage.visible ? toolsPage.contentItem : view
        const started = target.grabToImage(function(result) {
            if (prefix && !result.saveToFile(prefix + "-" + name + ".png")) { fail("screenshot " + name); return }
            console.log("LUNCHPAIL_COUCH_POLISH_CAPTURE " + name + " game=" + view.selectedGameId + " size=" + app.width + "x" + app.height)
            capturing = false
            step++
            advance()
        }, Qt.size(app.width, app.height))
        if (!started) fail("could not capture " + name)
    }
    function advance() {
        if (step < 4) library.save_couch_view_style(styles[step])
        else if (step === 4) view.requestDetails()
        else if (step < 9) view.detailsPage.chooseTab(step - 4)
        else if (step < toolEnd) app.openCouchGameTool(sections[step - 9])
        else if (step === toolEnd) { toolsPage.close(); app.width = 1280; app.height = 720; view.detailsPage.chooseTab(1) }
        else if (step === toolEnd + 1) app.openCouchGameTool("media")
        else if (step === toolEnd + 2) { toolsPage.close(); view.closeOverlay(); app.width = 3440; app.height = 1440; library.save_couch_view_style("wall") }
        else if (step === toolEnd + 3) { app.width = 1920; app.height = 1080; view.openPlatformWheel() }
        else if (step === toolEnd + 4) view.systemMediaRequested("Nintendo Entertainment System")
        else if (step === toolEnd + 5) { systemPage.close(); view.closePlatformWheel(); app.openCouchGameTool("box3d") }
        else if (step === toolEnd + 6) { boxPage.close(); app.openCouchGameTool("theme-video") }
        else if (step === toolEnd + 7) {
            videoPage.close()
            console.log("LUNCHPAIL_COUCH_POLISH_READY captures=" + step + " selected=" + view.selectedGameId)
            Qt.quit()
        }
    }
    Timer {
        interval: 1100; running: true; repeat: true
        onTriggered: {
            if (probe.capturing) return
            if (!probe.library.ready || probe.library.filtering || !probe.view.active) {
                if (++probe.waits > 150) probe.fail("selection timed out")
                return
            }
            if (probe.step === -1) {
                probe.app.width = 1920; probe.app.height = 1080
                const target = "9697a5eb-e0b4-4f24-8d43-672701414ee7"
                if (!probe.view.focusGameById(target) || probe.view.selectedGameId !== target) return
                const preview = JSON.parse(probe.library.couch_preview_json || "{}")
                if (preview.game_id !== target || !preview.theme_video_url) return
                probe.step = 0; probe.advance(); return
            }
            if (!probe.view.selectedGameId) {
                if (++probe.waits > 150) probe.fail("no selected game")
                return
            }
            if (probe.step >= 4 && (probe.details.loading || !probe.view.detailsCurrent)) return
            if (probe.step < 4) {
                if (probe.step < 2 && (!probe.view.gameVideoPreview.playing
                                      || probe.view.gameVideoPreview.position < 8000)) return
                probe.capture(probe.styles[probe.step])
            }
            else if (probe.step < 9) {
                if (!probe.view.detailsPage) { probe.fail("missing full-screen details page"); return }
                probe.capture("details-" + (probe.step - 4))
            } else if (probe.step < probe.toolEnd) {
                if (!probe.toolsPage.visible || probe.app.couchWorkspace !== "") { probe.fail("tool escaped couch page"); return }
                probe.capture("tools-" + probe.sections[probe.step - 9])
            } else if (probe.step === probe.toolEnd) probe.capture("720p-details")
            else if (probe.step === probe.toolEnd + 1) probe.capture("720p-media")
            else if (probe.step === probe.toolEnd + 2) probe.capture("ultrawide-wall")
            else if (probe.step === probe.toolEnd + 3) {
                if (!probe.view.systemVideoPreview.playing || probe.view.systemVideoPreview.position < 8000) return
                probe.capture("platforms")
            }
            else if (probe.step === probe.toolEnd + 4) probe.capture("system-media")
            else if (probe.step === probe.toolEnd + 5) probe.capture("box3d")
            else if (probe.step === probe.toolEnd + 6) {
                if (!probe.videoPage.visible) { probe.fail("cached theme did not open"); return }
                if (probe.videoPlayer.duration <= 0 || probe.videoPlayer.position < 8000) return
                probe.capture("theme-fullscreen")
            }
        }
    }
    Timer { interval: 240000; running: true; onTriggered: probe.fail("timeout at step " + probe.step) }
}
