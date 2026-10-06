import QtQuick

// Opt-in full-scene regression probe, run with isolated application state and
// QtTest available. It sends real Qt pointer events and exercises preview
// pause/resume only; it never launches a game.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    property var events: null
    property int stage: 0
    property int scene: 0
    property int control: 0
    property int tick: 0
    property int transitions: 0
    property int frames: 0
    property var controls: []
    property var header: null
    property var persistentGroups: []
    property var mediaControls: null
    property bool checking: false
    property bool capturing: false
    property string source: ""
    readonly property bool platform: scene % 2 === 1
    readonly property var video: platform ? view.systemVideoPreview : view.gameVideoPreview
    readonly property string label: (platform ? "platform" : "game") + "-" + (scene < 2 ? "1080p" : "720p")
    readonly property string mario: "9697a5eb-e0b4-4f24-8d43-672701414ee7"

    function fail(message) { console.error("LUNCHPAIL_COUCH_HOVER_FAILED " + label + " " + message); Qt.exit(2) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (let child of item.children || []) {
            const match = find(child, name)
            if (match) return match
        }
        return null
    }
    function move(item, x, y) {
        if (!events.mouseMove(item, x, y, 0, Qt.NoButton, Qt.NoModifier)) fail("pointer event rejected")
    }
    function click(item) {
        if (!events.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0))
            fail("preview click rejected")
    }
    function controlsVisible() {
        return header && header.visible && controls.every(item => item.visible)
               && persistentGroups.every(item => item && item.visible)
    }
    function capture(suffix) {
        capturing = true
        const path = app.screenshotOutput.replace(/\.png$/, "-hover-" + label + "-" + suffix + ".png")
        if (!view.grabToImage(function(result) {
            if (path && !result.saveToFile(path)) probe.fail("capture failed")
            probe.capturing = false
        }, Qt.size(app.width, app.height))) fail("readback rejected")
    }
    Connections {
        target: probe.header
        function onVisibleChanged() { if (probe.checking) ++probe.transitions }
    }
    FrameAnimation {
        running: probe.checking
        onTriggered: {
            ++probe.frames
            if (!probe.controlsVisible() || probe.transitions !== 0) probe.fail("controls hid or flickered")
        }
    }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.loading
                    || probe.library.filtering || !probe.view.active) return
            const view = probe.view
            if (probe.stage === 0) {
                probe.events = Qt.createQmlObject('import QtTest 1.2; TestEvent {}', probe)
                probe.app.width = 1920; probe.app.height = 1080
                probe.library.save_couch_view_style("wheel")
                view.sfxEnabled = false; view.navigationZone = 2
                view.beginGameHandoff(probe.mario, "Nintendo Entertainment System")
                view.focusGameById(probe.mario)
                probe.stage = 1
            } else if (probe.stage === 1) {
                if (view.entryPending || view.selectedGameId !== probe.mario) return
                if (!probe.video.playing || probe.video.position < 8000) return
                probe.source = probe.video.source.toString()
                probe.header = probe.find(view, probe.platform ? "couchPlatformHeader" : "couchHeaderActions")
                if (!probe.header) return probe.fail("missing toolbar")
                probe.controls = probe.header.children.filter(child => child.hovered !== undefined && child.text !== undefined)
                if (probe.controls.length !== (probe.platform ? 1 : 4)) return probe.fail("missing toolbar buttons")
                probe.mediaControls = probe.find(view, "couchBackgroundVideoControls")
                probe.persistentGroups = probe.platform ? []
                    : [probe.find(view, "couchCategories"), probe.find(view, "couchPrimaryActions"), probe.mediaControls]
                // Start below the top edge: controls must be present before
                // the user has ever hovered a toolbar.
                probe.move(view, view.width * 0.3, view.height * 0.7)
                if (!probe.controlsVisible()) return probe.fail("controls hidden on entry")
                probe.tick = 0; probe.control = 0; probe.frames = 0
                probe.transitions = 0; probe.checking = true
                probe.stage = 2
            } else if (probe.stage === 2) {
                const button = probe.controls[probe.control]
                probe.move(button, button.width * (0.25 + 0.01 * probe.tick), button.height / 2)
                if (!probe.controlsVisible() || !button.hovered)
                    return probe.fail("button lost hover control=" + probe.control + " tick=" + probe.tick)
                if (!probe.video.playing || probe.video.source.toString() !== probe.source)
                    return probe.fail("hover interrupted background playback")
                if (++probe.tick < 24) return
                // Also park on each button, including its tooltip delay.
                probe.stage = 3; probe.tick = 0
            } else if (probe.stage === 3) {
                if (!probe.controls[probe.control].hovered) return probe.fail("stationary hover lost")
                if (++probe.tick < 16) return
                if (++probe.control < probe.controls.length) { probe.tick = 0; probe.stage = 2; return }
                probe.capture("controls")
                probe.stage = 4; probe.tick = 0
            } else if (probe.stage === 4) {
                probe.move(view, view.width * 0.3, view.height * 0.7)
                if (!probe.controlsVisible()) return probe.fail("controls hid after leaving top edge")
                if (++probe.tick < 20) return
                if (!probe.platform) {
                    const pause = probe.mediaControls.children[0]
                    probe.move(pause, pause.width / 2, pause.height / 2)
                    if (!pause.hovered) return probe.fail("bottom preview button is not reachable")
                    probe.click(pause)
                    probe.stage = 6; probe.tick = 0
                } else probe.stage = 7
            } else if (probe.stage === 6) {
                if (!probe.video.paused) return probe.fail("bottom preview button failed to pause")
                if (++probe.tick < 10) return
                probe.click(probe.mediaControls.children[0])
                if (probe.video.paused) return probe.fail("bottom preview button failed to resume")
                probe.stage = 7
            } else if (probe.stage === 7) {
                if (!probe.video.playing) return
                if (probe.video.source.toString() !== probe.source) return probe.fail("pointer changed preview source")
                probe.checking = false
                if (probe.transitions !== 0 || probe.frames < 90) return probe.fail("unstable or unrendered controls")
                console.log("LUNCHPAIL_COUCH_HOVER_PASS " + probe.label + " controls=" + probe.controls.length
                            + " frames=" + probe.frames + " visibility_changes=" + probe.transitions
                            + " pointer_exit=visible preview_buttons=" + (probe.platform ? "n/a" : "pass"))
                probe.capture("pointer-away")
                probe.stage = 5
            } else if (probe.stage === 5) {
                if (++probe.scene >= 4) {
                    console.log("LUNCHPAIL_COUCH_HOVER_READY game=pass platform=pass auto_hide=off resolutions=1080p,720p")
                    Qt.quit(); return
                }
                if (probe.scene === 2) { probe.app.width = 1280; probe.app.height = 720 }
                if (probe.platform) { view.openPlatformWheel(); view.focusPlatform("Nintendo Entertainment System") }
                else view.closePlatformWheel()
                probe.stage = 1
            }
        }
    }
    Timer { interval: 150000; running: true; onTriggered: probe.fail("timeout at stage " + probe.stage) }
}
