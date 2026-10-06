import QtQuick

// Opt-in, isolated-state integration probe. Never launches a game.
Item {
    id: probe
    required property var app
    required property var library
    required property var details
    required property var view
    property int stage: 0
    property int tick: 0
    property int style: 0
    property var samples: []
    property string originalDetailsId: ""
    property var styles: ["wheel", "shelf", "wall", "album"]
    property var toolSections: ["display", "mods", "achievements", "files"]
    property int toolIndex: 0
    readonly property bool wheelCheck: app.argumentValue("--hyperspin-wheel-check") === "true"
    readonly property bool hoverCheck: app.argumentValue("--couch-hover-check") === "true"
    Loader {
        active: probe.hoverCheck
        sourceComponent: CouchHoverProbe { app: probe.app; view: probe.view; library: probe.library }
    }
    property bool capturing: false
    readonly property string mario: "9697a5eb-e0b4-4f24-8d43-672701414ee7"
    function fail(message) { console.error("LUNCHPAIL_COUCH_SMOOTHNESS_FAILED " + message); Qt.exit(2) }
    function capture(suffix) {
        if (!app.screenshotOutput) { console.log("LUNCHPAIL_COUCH_CAPTURE_SKIPPED no output path"); return }
        const path = app.screenshotOutput.replace(/\.png$/, "-" + suffix + ".png")
        capturing = true
        const started = view.grabToImage(function(result) {
            if (!result.saveToFile(path)) probe.fail("Could not save " + path)
            else console.log("LUNCHPAIL_COUCH_CAPTURED " + path)
            probe.capturing = false
        }, Qt.size(app.width, app.height))
        if (!started) fail("Could not capture " + suffix)
    }
    FrameAnimation {
        running: probe.stage === 1 || [203, 205, 207].indexOf(probe.stage) >= 0
        onTriggered: probe.samples.push(frameTime * 1000)
    }
    function reportWheelFrames(label) {
        const sorted = samples.slice().sort((a, b) => a - b)
        if (sorted.length < 180) { fail("Too few frame samples: " + label); return false }
        const p95 = sorted[Math.floor(sorted.length * 0.95)]
        const max = sorted[sorted.length - 1]
        const overBudget = sorted.filter(ms => ms > 33.34).length
        console.log("LUNCHPAIL_HYPERSPIN_FRAME_TIMES " + label + " size=" + app.width + "x" + app.height
                    + " count=" + sorted.length + " p50_ms=" + sorted[Math.floor(sorted.length * 0.5)].toFixed(3)
                    + " p95_ms=" + p95.toFixed(3) + " p99_ms=" + sorted[Math.floor(sorted.length * 0.99)].toFixed(3)
                    + " max_ms=" + max.toFixed(3) + " over_33ms=" + overBudget)
        samples = []
        if (p95 > 20 || max > 50) { fail("60fps frame budget exceeded in " + label); return false }
        return true
    }
    function wheelTick() {
        if (capturing) return
        if (stage === 0) {
            app.width = 1920; app.height = 1080
            view.sfxEnabled = false; view.navigationZone = 2
            // The progressive catalog can report ready before its full-model
            // identity handoff has settled. This is an explicit new selection.
            view.beginGameHandoff(mario, "Nintendo Entertainment System")
            if (!view.focusGameById(mario)) return
            stage = 200
        } else if (stage === 200) {
            if (view.entryPending || view.selectedGameId !== mario) return
            if (!view.gameVideoPreview.playing || view.gameVideoPreview.position < 1200) return
            // Couch UI scaling changes logical dimensions, not screen coverage.
            if (view.gameBrowser.width < view.width * 0.40 || view.gameBrowser.height < view.height * 0.95)
                return fail("Wheel does not occupy the full-height right edge")
            capture("hyperspin-game-1080p")
            tick = 0; stage = 201
        } else if (stage === 201) {
            // Prewarm texture uploads and first movement; exclude readback.
            view.moveShelf(tick < 12 ? 1 : -1)
            if (++tick < 24) return
            tick = 0; samples = []; stage = 203
        } else if (stage === 203) {
            view.moveShelf(tick < 40 ? 1 : -1)
            if (++tick < 80) return
            if (!reportWheelFrames("game-scroll")) return
            view.focusGameById(mario); tick = 0; stage = 204
        } else if (stage === 204) {
            if (!view.gameVideoPreview.playing || view.gameVideoPreview.position < 1000) return
            if (++tick < 10) return
            samples = []; tick = 0; stage = 205
        } else if (stage === 205) {
            if (!view.gameVideoPreview.playing) return fail("Theme video stopped")
            if (++tick < 60) return
            if (!reportWheelFrames("animated-theme")) return
            view.openPlatformWheel(); view.focusPlatform("Nintendo Entertainment System")
            stage = 206; tick = 0
        } else if (stage === 206) {
            if (!view.systemVideoPreview.playing || view.systemVideoPreview.position < 1200) return
            capture("hyperspin-platform-1080p"); stage = 202; tick = 0
        } else if (stage === 202) {
            view.movePlatformWheel(tick < 12 ? 1 : -1)
            if (++tick < 24) return
            samples = []; tick = 0; stage = 207
        } else if (stage === 207) {
            view.movePlatformWheel(tick < 40 ? 1 : -1)
            if (++tick < 80) return
            if (!reportWheelFrames("platform-scroll")) return
            view.closePlatformWheel(); view.focusGameById(mario)
            app.width = 1280; app.height = 720
            tick = 0; stage = 208
        } else if (stage === 208) {
            if (!view.gameVideoPreview.playing || view.gameVideoPreview.position < 1200) return
            capture("hyperspin-game-720p"); stage = 209
        } else if (stage === 209) {
            console.log("LUNCHPAIL_HYPERSPIN_READY game_wheel=pass platform_wheel=pass animated_theme=pass frame_budget=pass")
            Qt.quit()
        }
    }
    Timer {
        interval: probe.wheelCheck ? 100 : 200; repeat: true; running: !probe.hoverCheck
        onTriggered: {
            if (!probe.library.ready || probe.library.loading || probe.library.filtering || !probe.view.active) return
            if (probe.wheelCheck) { probe.wheelTick(); return }
            if (probe.stage === 0) {
                if (!probe.view.selectedGameId || !probe.view.browsing.description) return
                probe.originalDetailsId = probe.details.game_id
                probe.capture("wheel")
                probe.stage = 10
                probe.tick = 0
            } else if (probe.stage === 10) {
                // Readback for a screenshot is not part of normal browsing.
                if (++probe.tick < 5) return
                probe.stage = 1
                probe.tick = 0
            } else if (probe.stage === 1) {
                if (probe.details.game_id !== probe.originalDetailsId)
                    return probe.fail("Browsing loaded full game details")
                probe.view.moveShelf(probe.tick < 8 ? 1 : -1)
                if (++probe.tick < 16) return
                const sorted = probe.samples.slice().sort((a, b) => a - b)
                console.log("LUNCHPAIL_COUCH_FRAME_TIMES " + probe.styles[probe.style]
                            + " count=" + sorted.length + " p95_ms=" + sorted[Math.floor(sorted.length * 0.95)]
                            + " max_ms=" + sorted[sorted.length - 1])
                probe.samples = []
                probe.tick = 0
                if (++probe.style < probe.styles.length) {
                    probe.library.save_couch_view_style(probe.styles[probe.style])
                } else {
                    probe.stage = 2
                    probe.library.save_couch_view_style("wheel")
                    probe.view.focusGameById("9697a5eb-e0b4-4f24-8d43-672701414ee7")
                }
            } else if (probe.stage === 2) {
                if (++probe.tick < 5) return
                probe.capture("logo-wheel")
                probe.stage = 20
                probe.tick = 0
            } else if (probe.stage === 20) {
                if (++probe.tick < 3) return
                probe.view.requestDetails()
                probe.stage = 3
                probe.tick = 0
            } else if (probe.stage === 3) {
                if (probe.details.loading || !probe.view.detailsCurrent) return
                if (++probe.tick < 5) return
                if (!probe.view.overlayOpen || probe.app.couchWorkspace)
                    return probe.fail("Details did not open in the native couch page")
                probe.capture("details")
                probe.stage = 4
                probe.tick = 0
            } else if (probe.stage === 4) {
                if (probe.tick === 1) probe.view.handleNavigation("page_right")
                if (++probe.tick < 3) return
                probe.capture("tools")
                probe.stage = 5
                probe.tick = 0
            } else if (probe.stage === 5) {
                if (probe.tick === 0) probe.app.openCouchGameTool(probe.toolSections[probe.toolIndex])
                if (++probe.tick < 5) return
                probe.app.closeCouchGameTool()
                probe.tick = 0
                if (++probe.toolIndex < probe.toolSections.length) return
                console.log("LUNCHPAIL_COUCH_SMOOTHNESS_READY previews=" + probe.view.browsing.description.length
                            + " title=" + probe.details.title)
                Qt.quit()
            }
        }
    }
    Timer { interval: probe.wheelCheck ? 120000 : 60000; running: !probe.hoverCheck; onTriggered: probe.fail("Timed out at stage " + probe.stage) }
}
