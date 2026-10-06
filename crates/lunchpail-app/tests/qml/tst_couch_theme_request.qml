import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchThemeRequest"
    when: windowShown
    Component {
        id: component
        Lunchpail.CouchThemeRequest {
            delay: 50
            library: QtObject {
                property string couch_theme_status_json: "{}"
                property var requests: []
                property int cancels: 0
                property var videoRequests: []
                function cancel_couch_theme() { cancels++; couch_theme_status_json = "{}" }
                function request_game_video(game) { videoRequests = videoRequests.concat([game]) }
                function request_couch_theme(game, platform) { requests = requests.concat([{game: game, platform: platform}]) }
            }
        }
    }
    function controller() { const item = createTemporaryObject(component, test); verify(item); return item }
    function test_inactive_does_not_fetch() {
        const item = controller(); item.gameId = "mario"; wait(100)
        compare(item.library.requests.length, 0)
    }
    function test_rapid_scroll_only_fetches_latest() {
        const item = controller(); item.active = true; item.gameId = "mario"
        item.gameId = "zelda"; item.gameId = "faxanadu"
        tryCompare(item.library, "requests", [{game: "faxanadu", platform: ""}])
        compare(item.library.videoRequests, [])
    }
    function test_platform_supersedes_game_and_back_restores_it() {
        const item = controller(); item.gameId = "mario"; item.active = true
        item.platform = "Nintendo Entertainment System"
        tryCompare(item.library, "requests", [{game: "", platform: "Nintendo Entertainment System"}])
        compare(item.library.videoRequests.length, 0)
        item.platform = ""
        tryCompare(item.library, "requests", [{game: "", platform: "Nintendo Entertainment System"}, {game: "mario", platform: ""}])
        compare(item.library.videoRequests, [])
    }
    function test_deactivation_cancels_pending_and_ignores_late_status() {
        const item = controller(); item.gameId = "mario"; item.active = true
        item.active = false; wait(100); compare(item.library.requests.length, 0)
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", status: "ready"})
        compare(item.status, "")
    }
    function test_status_is_selection_scoped_and_repeat_selection_does_not_restart() {
        const item = controller(); item.gameId = "mario"; item.active = true
        tryCompare(item.library, "requests", [{game: "mario", platform: ""}])
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", status: "ready"})
        compare(item.status, "ready")
        const count = item.library.cancels; item.gameId = "mario"; wait(100)
        compare(item.library.cancels, count); compare(item.library.requests.length, 1)
        item.platform = "Sega Genesis"; compare(item.status, "")
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", status: "late"})
        compare(item.status, "")
    }
    function test_progress_belongs_only_to_the_selected_game() {
        const item = controller(); item.gameId = "mario"; item.active = true
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", status: "Downloading", phase: "downloading", progress: 42})
        compare(item.phase, "downloading"); compare(item.progress, 42)
        item.gameId = "zelda"
        compare(item.phase, ""); compare(item.progress, -1); verify(item.pending)
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", status: "Late progress", phase: "downloading", progress: 91})
        compare(item.phase, ""); compare(item.progress, -1)
    }

    function test_cached_theme_wins_without_fetching_theme_or_gameplay() {
        const item = controller()
        item.themeVideoUrl = "file:///theme-video.mp4"
        item.gameplayVideoUrl = "file:///video.mp4"
        item.gameId = "mario"; item.active = true
        compare(item.previewVideoUrl.toString(), "file:///theme-video.mp4")
        compare(item.videoKind, "theme")
        wait(100)
        compare(item.library.requests, [])
        compare(item.library.videoRequests, [])
    }

    function test_cached_gameplay_waits_for_theme_lookup_and_theme_publication() {
        const item = controller()
        item.gameplayVideoUrl = "file:///video.mp4"
        item.gameId = "mario"; item.active = true
        compare(item.previewVideoUrl.toString(), "")
        tryCompare(item.library, "requests", [{game: "mario", platform: ""}])
        for (const phase of ["queued", "finding", "downloading", "ready"]) {
            item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", phase: phase})
            compare(item.previewVideoUrl.toString(), "")
            compare(item.videoKind, "")
        }
        item.themeVideoUrl = "file:///theme-video.mp4"
        compare(item.previewVideoUrl.toString(), "file:///theme-video.mp4")
        compare(item.videoKind, "theme")
        compare(item.library.videoRequests, [])
    }

    function test_gameplay_download_is_only_a_fallback_data() {
        return [{tag: "missing-theme", phase: "unavailable"},
                {tag: "missing-account", phase: "setup-required"},
                {tag: "network-error", phase: "error"}]
    }

    function test_gameplay_download_is_only_a_fallback(data) {
        const item = controller(); item.gameId = "mario"; item.active = true
        tryCompare(item.library, "requests", [{game: "mario", platform: ""}])
        compare(item.library.videoRequests, [])
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", phase: data.phase})
        tryCompare(item.library, "videoRequests", ["mario"])
        item.requestGameplayFallback()
        compare(item.library.videoRequests, ["mario"])
        item.gameplayVideoUrl = "file:///video.mp4"
        compare(item.previewVideoUrl.toString(), "file:///video.mp4")
        compare(item.videoKind, "gameplay")
        item.active = false
        compare(item.previewVideoUrl.toString(), "")
    }

    function test_cached_gameplay_fallback_does_not_download_again() {
        const item = controller(); item.gameId = "mario"; item.active = true
        item.gameplayVideoUrl = "file:///video.mp4"
        tryCompare(item.library, "requests", [{game: "mario", platform: ""}])
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", phase: "unavailable"})
        compare(item.previewVideoUrl.toString(), "file:///video.mp4")
        wait(100)
        compare(item.library.videoRequests, [])
        item.themeVideoUrl = "file:///theme-video.mp4"
        compare(item.previewVideoUrl.toString(), "file:///theme-video.mp4")
    }

    function test_late_failure_cannot_start_fallback_for_a_new_selection() {
        const item = controller(); item.gameId = "mario"; item.active = true
        tryCompare(item.library, "requests", [{game: "mario", platform: ""}])
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", phase: "unavailable"})
        item.gameId = "zelda"
        wait(100)
        compare(item.library.videoRequests, [])
        item.library.couch_theme_status_json = JSON.stringify({key: "game:mario", phase: "error"})
        wait(100)
        compare(item.library.videoRequests, [])
        item.platform = "NES"
        item.library.couch_theme_status_json = JSON.stringify({key: "platform:NES", phase: "unavailable"})
        wait(100)
        compare(item.library.videoRequests, [])
    }
}
