import QtQuick

// Explicit opt-in probe; use an isolated state database and media directory.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    property int step: -1
    property bool capturing: false
    property string gameId: "9697a5eb-e0b4-4f24-8d43-672701414ee7"
    readonly property var styles: ["wheel", "shelf", "wall", "album"]
    function fail(message) { console.error("LUNCHPAIL_COUCH_VIEWS_FAILED " + message); Qt.exit(2) }
    function advance() {
        if (step === 16) {
            view.closePlatformWheel()
            view.openSearch("Find a Mario game", false)
            view.searchPanel.askMode = true
            view.searchPanel.submit()
            if (!view.installDialog.visible || view.ai.busy || view.speech.listening) { fail("first-use model confirmation did not gate installation"); return }
            return
        }
        const platforms = step % 8 >= 4
        app.width = step >= 8 ? 1280 : 1920
        app.height = step >= 8 ? 720 : 1080
        if (platforms) { view.openPlatformWheel(); view.focusPlatform("Nintendo Entertainment System") }
        else view.closePlatformWheel()
        if (step % 4 === 0) library.save_couch_view_style(styles[0])
        else if (platforms) view.handleNavigation("menu")
        else view.handleKey({key: Qt.Key_V, modifiers: Qt.ControlModifier, text: "v", accepted: false})
        if (library.couch_view_style !== styles[step % 4]) fail("view shortcut failed")
    }
    Timer {
        interval: 900; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.filtering || !probe.view.active) return
            if (probe.step === -1) {
                if (!probe.view.focusGameById(probe.gameId) || probe.view.selectedGameId !== probe.gameId) return
                const preview = JSON.parse(probe.library.couch_preview_json || "{}")
                if (preview.game_id !== probe.gameId || !preview.theme_video_url) return
                probe.step = 0; probe.advance(); return
            }
            if (probe.step === 16) {
                probe.capturing = true
                probe.view.installDialog.contentItem.grabToImage(function(result) {
                    result.saveToFile(probe.app.argumentValue("--screenshot-output") + "-install.png")
                    probe.view.installDialog.decline()
                    if (probe.view.ai.busy || probe.view.speech.listening) { probe.fail("No started model or microphone"); return }
                    if (!probe.view.searchOpen) { probe.fail("installation dialog discarded the original search"); return }
                    probe.step = 17; probe.capturing = false
                })
                return
            }
            if (probe.step === 17) {
                if (!probe.view.inputEnabled || probe.view.installDialog.visible) return
                if (!probe.view.searchPanel.inputFocused) { probe.fail("installation dialog did not restore query focus"); return }
                probe.view.closeSearch()
                probe.view.openPlatformWheel()
                probe.view.handleKey({key: Qt.Key_M, modifiers: Qt.NoModifier, text: "m", accepted: false})
                if (!probe.view.searchOpen || probe.view.platformWheelOpen || probe.view.searchPanel.askMode) { probe.fail("typing did not open literal search from platforms"); return }
                console.log("LUNCHPAIL_COUCH_VIEWS_READY games=4 platforms=4 sizes=1080p,720p video=background typing=literal model_confirmation=no microphone=off")
                Qt.quit(); return
            }
            const platforms = probe.step % 8 >= 4
            const browser = platforms ? probe.view.platformBrowser : probe.view.gameBrowser
            const video = platforms ? probe.view.systemVideoPreview : probe.view.gameVideoPreview
            if (!browser.currentItem) return
            if (!platforms && probe.view.selectedGameId !== probe.gameId) { probe.fail("game changed with layout"); return }
            if (platforms && browser.currentItem.platformName !== "Nintendo Entertainment System") { probe.fail("platform changed with layout"); return }
            if (!video.visible || !video.playing || video.position < 8000) return
            if (!video.backgroundMode || video.width !== probe.view.width || video.height !== probe.view.height) { probe.fail("video is not a full background"); return }
            const position = video.mapToItem(probe.view, 0, 0)
            if (position.x < 0 || position.y < 0 || position.x + video.width > probe.view.width + 1
                    || position.y + video.height > probe.view.height + 1) { probe.fail("preview outside viewport"); return }
            if (platforms) {
                const viewport = video.parent.parent
                const within = video.mapToItem(viewport, 0, 0)
                if (within.y < 0 || within.y + video.height > viewport.height + 1) {
                    probe.fail("platform video clipped by presentation pane"); return
                }
            }
            const name = (platforms ? "platforms-" : "games-") + probe.styles[probe.step % 4] + (probe.step >= 8 ? "-720p" : "-1080p")
            probe.capturing = true
            probe.view.grabToImage(function(result) {
                const prefix = probe.app.argumentValue("--screenshot-output")
                if (prefix && !result.saveToFile(prefix + "-" + name + ".png")) { probe.fail("capture " + name); return }
                console.log("LUNCHPAIL_COUCH_VIEWS_CAPTURE " + name + " video_position=" + video.position)
                probe.capturing = false; probe.step++; probe.advance()
            }, Qt.size(probe.app.width, probe.app.height))
        }
    }
    Timer { interval: 150000; running: true; onTriggered: probe.fail("timeout step " + probe.step) }
}
