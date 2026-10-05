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
                function cancel_couch_theme() { cancels++; couch_theme_status_json = "{}" }
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
    }
    function test_platform_supersedes_game_and_back_restores_it() {
        const item = controller(); item.gameId = "mario"; item.active = true
        item.platform = "Nintendo Entertainment System"
        tryCompare(item.library, "requests", [{game: "", platform: "Nintendo Entertainment System"}])
        item.platform = ""
        tryCompare(item.library, "requests", [{game: "", platform: "Nintendo Entertainment System"}, {game: "mario", platform: ""}])
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
}
