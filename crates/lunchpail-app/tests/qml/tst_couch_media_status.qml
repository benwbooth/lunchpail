import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchMediaStatus"
    when: windowShown
    Component {
        id: component
        Lunchpail.CouchMediaStatus {
            width: 600
            gameId: "mario"
            library: QtObject {
                property int media_pending_count: 1
                property string media_active_title: "Mario"
                property int media_active_progress: 43
                property bool media_setup_required: false
                property int media_revision: 0
                property string state: "downloading"
                property string message: "Downloading Mario"
                function automatic_video_state(game) { return game === "mario" ? state : "queued" }
                function automatic_video_message(game) { return game === "mario" ? message : "Queued" }
            }
        }
    }
    function status(properties) { const value = createTemporaryObject(component, test, properties || {}); verify(value); return value }

    function test_percentage_and_pending_are_visible() {
        const item = status()
        verify(item.summary.indexOf("43%") >= 0)
        compare(item.progress, 43)
        verify(item.busy)
        item.library.media_active_progress = -1
        compare(item.summary, "Finding game video…")
        verify(findChild(item, "couchMediaProgress").indeterminate)
    }
    function test_new_selection_never_shows_previous_download_progress() {
        const item = status()
        item.gameId = "zelda"
        compare(item.summary, "Game video queued…")
        compare(item.progress, -1)
        item.library.media_active_progress = 91
        compare(item.progress, -1)
        verify(item.summary.indexOf("91") < 0)
    }
    function test_theme_progress_does_not_hide_playing_gameplay() {
        const item = status({videoKind: "gameplay", themePhase: "downloading", themeProgress: 62})
        verify(item.summary.indexOf("GAMEPLAY VIDEO") >= 0)
        verify(item.summary.indexOf("62%") >= 0)
        compare(item.progress, 62)
        item.themePhase = "unavailable"
        compare(item.summary, "GAMEPLAY VIDEO")
        verify(!item.busy)
    }
    function test_missing_account_missing_video_and_failure_are_not_loading_forever() {
        const item = status({themePhase: "unavailable"})
        item.library.state = "setup-required"
        verify(item.summary.indexOf("EmuMovies setup") >= 0)
        verify(!item.busy)
        item.library.state = "unavailable"
        compare(item.summary, "No matching game video · artwork shown")
        item.library.state = "automatic"
        item.library.message = "EmuMovies download failed temporarily"
        verify(item.summary.indexOf("failed") >= 0)
        verify(!item.busy)
        item.playbackError = "decoder error"
        compare(item.summary, "Video could not play · artwork shown")
    }
    function test_ready_media_has_no_progress_bar() {
        const item = status({videoKind: "theme", themePhase: "ready"})
        compare(item.summary, "GAME THEME")
        verify(!item.busy)
        verify(!findChild(item, "couchMediaProgress").visible)
    }
}
