import QtQuick

// Opt-in native regression: use a copied state/media profile. Never launches games.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    property var audioControls: []
    property int step: 0
    property bool capturing: false
    property string lastSource: ""
    property int stableTicks: 0
    property bool progressCaptured: false
    property int themeViewIndex: 0
    readonly property bool themePriorityCheck: app.argumentValue("--preview-theme-priority") === "true"
    readonly property var themeViews: ["wall", "album", "shelf", "wheel"]
    readonly property string firstGame: "2d6cb4b2-a219-4c40-9b31-ac466a77e88c"
    readonly property string nextGame: app.argumentValue("--media-probe-game") || "9697a5eb-e0b4-4f24-8d43-672701414ee7"
    readonly property string platform: "Nintendo Entertainment System"
    Component.onCompleted: { view.sfxEnabled = false; view.windowActive = false }
    function fail(message) { console.error("LUNCHPAIL_COUCH_MEDIA_FAILED " + message); Qt.exit(2) }
    // Two native processes on the same copied profile: write starts with no
    // VideoAudio settings; read must restore the choices made by real controls.
    function checkAudioPreferences() {
        const phase = app.argumentValue("--video-audio-check")
        if (!phase) return true
        if (phase !== "write" && phase !== "read") { fail("unknown audio phase"); return false }
        const couchMuted = phase === "read"
        const detailsMuted = !couchMuted
        const gridMuted = app.gridVideoAudioMuted
        if (!app.couchModeActive || app.videoAudioMuted !== couchMuted
                || view.videoMuted !== couchMuted || view.gameVideoPreview.muted !== couchMuted) {
            fail("Couch audio restore/default " + phase); return false
        }
        app.exitCouchMode()
        if (app.detailsVideoAudioMuted !== detailsMuted || audioControls.length !== 2) {
            fail("normal audio restore/default " + phase); return false
        }
        for (const control of audioControls) {
            control.clicked()
            if (app.detailsVideoAudioMuted !== !detailsMuted || view.videoMuted !== couchMuted
                    || app.gridVideoAudioMuted !== gridMuted) {
                fail("normal speaker control or mode isolation"); return false
            }
            control.clicked()
        }
        app.enterCouchMode()
        if (app.videoAudioMuted !== couchMuted) { fail("Couch mode switch"); return false }
        view.videoMuteRequested()
        if (app.videoAudioMuted !== !couchMuted || view.gameVideoPreview.muted !== !couchMuted) {
            fail("Couch speaker control"); return false
        }
        app.exitCouchMode()
        if (app.detailsVideoAudioMuted !== detailsMuted || app.gridVideoAudioMuted !== gridMuted) {
            fail("Couch changed desktop preferences"); return false
        }
        app.enterCouchMode()
        // Write leaves both choices opposite their defaults; read restores
        // its original choices so it can be repeated without reseeding.
        if (phase === "read") view.videoMuteRequested()
        else {
            app.exitCouchMode()
            audioControls[0].clicked()
            app.enterCouchMode()
        }
        console.log("LUNCHPAIL_VIDEO_AUDIO_READY phase=" + phase
                    + " controls=pass mode_isolation=pass couch_muted=" + app.videoAudioMuted)
        return true
    }
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
                if (probe.themePriorityCheck
                        && (probe.view.browsing.theme_video_url
                            || probe.view.previewVideoUrl.toString() !== probe.view.browsing.video_url)) {
                    probe.fail("missing theme did not fall back to selected game video"); return
                }
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
                if (!probe.checkAudioPreferences()) return
                if (probe.themePriorityCheck) {
                    probe.library.save_couch_view_style(probe.themeViews[0])
                    probe.step = 8
                    return
                }
                console.log("LUNCHPAIL_COUCH_MEDIA_READY selected_video=pass system_isolation=pass progress_identity=pass")
                Qt.quit()
            } else if (probe.step === 8) {
                if (!probe.view.gameVideoPreview.playing || probe.view.gameVideoPreview.position < 100) return
                if (!probe.view.browsing.theme_video_url || !probe.view.browsing.video_url
                        || probe.view.previewVideoUrl.toString() !== probe.view.browsing.theme_video_url) {
                    probe.fail("animated theme did not beat cached gameplay in " + probe.themeViews[probe.themeViewIndex]); return
                }
                console.log("LUNCHPAIL_COUCH_THEME_PRIORITY_READY view=" + probe.themeViews[probe.themeViewIndex]
                            + " source=" + probe.view.previewVideoUrl)
                if (++probe.themeViewIndex < probe.themeViews.length) {
                    probe.library.save_couch_view_style(probe.themeViews[probe.themeViewIndex])
                    return
                }
                console.log("LUNCHPAIL_COUCH_MEDIA_READY selected_video=pass system_isolation=pass theme_priority=pass gameplay_fallback=pass")
                Qt.quit()
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: probe.fail("timeout step " + probe.step) }
}
