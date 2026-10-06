import QtQuick

// Opt-in full-scene regression probe, run with isolated application state and
// QtTest available. It sends real Qt pointer events; it never clicks or launches.
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
    function capture(suffix) {
        capturing = true
        const path = app.screenshotOutput.replace(/\.png$/, "-hover-" + label + "-" + suffix + ".png")
        if (!view.grabToImage(function(result) {
            if (path && !result.saveToFile(path)) probe.fail("capture failed")
            probe.capturing = false
        }, Qt.size(app.width, app.height))) fail("readback rejected")
    }
    Connections {
        target: probe.view
        function onWheelBrowseOnlyChanged() { if (probe.checking) ++probe.transitions }
    }
    FrameAnimation {
        running: probe.checking
        onTriggered: {
            ++probe.frames
            if (probe.view.wheelBrowseOnly || probe.transitions !== 0) probe.fail("toolbar/scrim flickered")
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
                const header = probe.find(view, probe.platform ? "couchPlatformHeader" : "couchHeaderActions")
                if (!header) return probe.fail("missing toolbar")
                probe.controls = header.children.filter(child => child.hovered !== undefined && child.text !== undefined)
                if (probe.controls.length !== (probe.platform ? 1 : 4)) return probe.fail("missing toolbar buttons")
                probe.move(view, view.width * 0.3, 12)
                probe.tick = 0; probe.control = 0; probe.frames = 0
                probe.stage = 2
            } else if (probe.stage === 2) {
                const button = probe.controls[probe.control]
                probe.move(button, button.width * (0.25 + 0.01 * probe.tick), button.height / 2)
                if (view.wheelBrowseOnly || !button.hovered || !button.visible)
                    return probe.fail("button lost hover control=" + probe.control + " tick=" + probe.tick)
                if (!probe.video.playing || probe.video.source.toString() !== probe.source)
                    return probe.fail("hover interrupted background playback")
                probe.checking = true
                if (++probe.tick < 24) return
                // Also park on each button, including its tooltip delay.
                probe.stage = 3; probe.tick = 0
            } else if (probe.stage === 3) {
                if (!probe.controls[probe.control].hovered) return probe.fail("stationary hover lost")
                if (++probe.tick < 16) return
                if (++probe.control < probe.controls.length) { probe.tick = 0; probe.stage = 2; return }
                probe.checking = false
                if (probe.transitions !== 0 || probe.frames < 90) return probe.fail("unstable or unrendered hover")
                console.log("LUNCHPAIL_COUCH_HOVER_PASS " + probe.label + " controls=" + probe.controls.length
                            + " frames=" + probe.frames + " visibility_changes=" + probe.transitions)
                probe.capture("controls")
                probe.stage = 4
            } else if (probe.stage === 4) {
                probe.move(view, view.width * 0.3, view.height * 0.7)
                if (!view.wheelBrowseOnly) return probe.fail("toolbar failed to hide after exit")
                probe.capture("browse")
                probe.stage = 5
            } else if (probe.stage === 5) {
                if (++probe.scene >= 4) {
                    console.log("LUNCHPAIL_COUCH_HOVER_READY game=pass platform=pass resolutions=1080p,720p")
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
