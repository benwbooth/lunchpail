import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchVideoPreview"
    when: windowShown
    Component {
        id: previewComponent
        Lunchpail.CouchVideoPreview { width: 640; height: 406 }
    }
    function test_muting_does_not_reset_pause_intent() {
        const preview = createTemporaryObject(previewComponent, this)
        preview.paused = true
        preview.muted = false
        compare(preview.paused, true)
        preview.muted = true
        compare(preview.paused, true)
        compare(preview.playing, false)
    }
    function test_new_selection_resets_pause_without_loading_when_inactive() {
        const preview = createTemporaryObject(previewComponent, this)
        preview.paused = true
        preview.source = "file:///a-preview-that-is-not-opened.mp4"
        compare(preview.paused, false)
        wait(100)
        compare(preview.errorMessage, "")
        compare(preview.playing, false)
        compare(preview.position, 0)
    }
    function test_real_video_continues_when_unmuted() {
        const preview = createTemporaryObject(previewComponent, this)
        preview.source = Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
        preview.active = true
        tryVerify(function() { return preview.playing && preview.position > 1000 }, 5000)
        const before = preview.position
        preview.muted = false
        wait(400)
        verify(preview.playing)
        verify(preview.position >= before)
        compare(preview.errorMessage, "")
        preview.muted = true
        preview.paused = true
        tryCompare(preview, "playing", false)
        const pausedPosition = preview.position
        preview.muted = false
        wait(200)
        verify(preview.paused)
        verify(!preview.playing)
        compare(preview.position, pausedPosition)
    }
    function test_leaving_preview_clears_frame_and_stops_playback() {
        const preview = createTemporaryObject(previewComponent, this)
        preview.source = Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
        preview.active = true
        tryVerify(function() { return preview.playing && preview.position > 100 }, 5000)
        preview.paused = true
        preview.active = false
        tryCompare(preview, "playing", false)
        preview.source = ""
        compare(preview.paused, false)
        compare(preview.errorMessage, "")
        compare(preview.source.toString(), "")
    }
}
