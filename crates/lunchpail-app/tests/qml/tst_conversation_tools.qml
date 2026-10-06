import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "ConversationTools"
    when: windowShown
    Component {
        id: component
        Lunchpail.CouchAssistantController {
            app: QtObject {
                property bool couchModeActive: true
                property string desktopMediaScope: "details"
                readonly property string activeVideoAudioScope: couchModeActive ? "couch" : desktopMediaScope
                property string selectedGameId: "mario"
                property bool confirmation: false
                property bool filterPending: false
                property string opened: ""
                property string assistantQuery: "Desktop Mario"
                property int launches: 0
                property bool canSelect: true
                property string browsedCollection: ""
                function assistantSelectGame(game) { if (!canSelect) return false; selectedGameId = game.id; return true }
                function assistantShowDetails(game) { opened = "details:" + game.id }
                function assistantLaunchGame(game) { launches++; opened = "launch:" + game.id }
                function assistantNavigate(action) { opened = "navigate:" + action }
                function assistantOpenPanel(panel) { opened = "panel:" + panel }
                function assistantControlMedia(action) { opened = "media:" + action; return {status:"updated"} }
                function enterCouchMode() { couchModeActive = true }
                function exitCouchMode() { couchModeActive = false }
                function assistantScreenContext() { return {confirmation_open: confirmation, filtering: filterPending} }
                function assistantBrowse(query, platform, shelf, collection) { opened = "browse:" + query + ":" + platform + ":" + shelf; browsedCollection = collection || "" }
                function openSettingsFor(section) { opened = "settings:" + section }
                function couchTool(panel) { opened = "panel:" + panel }
                function openCouchGameTool(section) { opened = "game:" + section }
                function assistantFullscreen(action) { opened = action }
            }
            view: QtObject {
                property string selectedGameId: "mario"
                property string searchText: "Mario"
                property bool platformWheelOpen: false
                property bool launchStatusOverlayOpen: false
                property int launches: 0
                property int closes: 0
                property int detailRequests: 0
                property var gameVideoPreview: ({paused: false, playing: true})
                property var systemVideoPreview: ({paused: false, playing: true})
                function closeSearch() { closes++ }
                function focusGameById(id) { selectedGameId = id; return true }
                function beginGameHandoff(id, platform) { selectedGameId = id }
                function requestDetails() { detailRequests++ }
                function launchRequested() { launches++ }
                function openPlatformWheel() { platformWheelOpen = true }
                function openCollectionWheel() {}
                function handleNavigation(action) {}
            }
            library: QtObject {
                property bool filtering: false
                property int filtered_count: 2
                property bool installed: true
                property bool favorite: false
                property bool favoritePending: false
                property string favorite_message: "Save failed"
                property bool collection_busy: false
                property string collection_message: "Save failed"
                property int collection_count: 1
                property bool collectionExists: true
                property bool member: false
                property string couch_view_style: "wheel"
                property string view_mode: "grid"
                function choose_view_mode(mode) { view_mode = mode }
                property bool couch_music_enabled: true
                property int couch_music_volume: 45
                function conversation_games_json() { return JSON.stringify([{id:"mario",title:"Super Mario Bros.",platform:"NES"}]) }
                function conversation_resolve_game_json(title, platform) { return JSON.stringify({games:[{id:"mario",title:"Super Mario Bros.",platform:"NES"}],total_matches:1}) }
                function display_title_for_game(id) { return id === "mario" ? "Super Mario Bros." : "" }
                function platform_for_game(id) { return "NES" }
                function local_for_game(id) { return installed }
                function downloadable_for_game(id) { return !installed }
                function row_for_game(id) { return id === "mario" ? 0 : -1 }
                function is_favorite(id) { return favorite }
                function favorite_pending(id) { return favoritePending }
                function set_favorite(id, value) { favoritePending = true; favorite = value }
                function collection_id_at(i) { return "collection" }
                function collection_name_at(i) { return "Favorites" }
                function collection_description_at(i) { return "Test" }
                function collection_kind_at(i) { return "manual" }
                function collection_game_count_at(i) { return 1 }
                function collection_exists(id) { return collectionExists && id === "collection" }
                function collection_contains(id, game) { return member }
                function delete_collection(id) { collectionExists = false; collection_count = 0 }
                function set_collection_membership(id, game, value) { member = value }
                function save_couch_view_style(style) { couch_view_style = style; return true }
                function save_couch_audio_settings(enabled, volume) { couch_music_enabled = enabled; couch_music_volume = volume; return true }
            }
            details: QtObject {
                property bool game_running: false
                property bool launch_busy: false
                property bool loading: false
                property bool launch_discovery_busy: false
                property string game_id: "mario"
                property string session_title: "Super Mario Bros."
                property string launch_status: ""
                property int stops: 0
                function stop_emulator() { stops++; game_running = false }
            }
            assistant: QtObject {
                property bool busy: true
                property string config_json: JSON.stringify({spoken_replies:true,captions:true,wake_word:false,voice_rate:0,voice_volume:0.85})
                property string history_json: "[]"
                property int turn_number: 1
                property var replies: []
                signal tool_requested(string id, string name, string arguments)
                function complete_tool(id, result) { replies = replies.concat([{id:id,result:JSON.parse(result)}]) }
                function configure(value) { config_json = value }
            }
            ai: QtObject {
                property bool hands_free: false
                property bool speech_ready: true
                function enable_hands_free(value) { hands_free = value }
            }
            feedbackSettings: QtObject {
                property bool soundsEnabled: true
                property real soundVolume: 0.22
                function sync() {}
            }
            videoPreferences: QtObject {
                property bool couchMuted: false
                property bool gridMuted: true
                property bool detailsMuted: true
                function muted(scope) { return this[scope + "Muted"] }
                function setMuted(scope, value) { this[scope + "Muted"] = value }
            }
        }
    }
    function controller() { const c = createTemporaryObject(component, test); verify(c); return c }
    function call(c, name, args) {
        if (name === "play_game" && args === undefined) args = {game_id:"mario"}
        c.assistant.tool_requested("call-" + c.assistant.replies.length, name, JSON.stringify(args || {}))
    }
    function result(c) { return c.assistant.replies[c.assistant.replies.length - 1].result }
    function finish(c) { c.waiting.started -= 400; c.pollAction() }
    function test_context_returns_real_selection_and_bounded_results() {
        const c = controller(); call(c, "get_context")
        compare(result(c).selected_game.id, "mario")
        compare(result(c).games[0].title, "Super Mario Bros.")
        compare(result(c).game_running, false)
    }
    function test_natural_search_tool_waits_for_debounced_filter() {
        const c = controller(); c.app.filterPending = true
        call(c, "browse_library", {query:"super mario bros",platform:"",shelf:"all"})
        compare(c.app.opened, "browse:super mario bros::all")
        finish(c); compare(c.assistant.replies.length, 0)
        c.app.filterPending = false; c.pollAction()
        compare(result(c).total_results, 2)
        compare(c.view.launches, 0)
    }
    function test_play_uses_explicit_game_and_normal_workflow_not_optimistic_success() {
        const c = controller(); call(c, "play_game", {game_id:"mario"})
        compare(c.view.launches, 1); compare(c.view.closes, 1)
        finish(c); compare(c.assistant.replies.length, 0)
        c.details.game_running = true; c.pollAction()
        compare(result(c).status, "running"); compare(result(c).game.id, "mario")
    }
    function test_empty_id_never_launches_the_highlighted_game() {
        for (const couch of [false, true]) {
            const c = controller(); c.app.couchModeActive = couch
            call(c, "play_game", {})
            verify(!!result(c).error); compare(c.view.launches, 0); compare(c.app.launches, 0)
            call(c, "play_game", {game_id:" "})
            verify(!!result(c).error); compare(c.view.launches, 0); compare(c.app.launches, 0)
        }
    }
    function test_exact_resolution_does_not_change_selection_or_launch() {
        const c = controller()
        call(c, "resolve_game", {title:"super mario brothers",platform:""})
        compare(result(c).games[0].id, "mario"); compare(result(c).total_matches, 1)
        compare(c.view.launches, 0); compare(c.app.launches, 0); compare(c.app.opened, "")
    }
    function test_diagnostic_checks_explicit_target_before_blocking_launch() {
        const c = controller(); c.readOnlyProbe = true
        c.app.selectedGameId = "faxanadu"; c.view.selectedGameId = "faxanadu"
        call(c, "play_game", {game_id:"mario"})
        compare(result(c).status, "launch_blocked"); compare(result(c).game.id, "mario")
        compare(c.view.launches, 0); compare(c.app.launches, 0)
        compare(c.view.selectedGameId, "faxanadu"); compare(c.app.selectedGameId, "faxanadu")
    }
    function test_launch_confirmation_is_not_running() {
        const c = controller(); call(c, "play_game")
        c.app.confirmation = true; finish(c)
        compare(result(c).status, "user_action_required")
        compare(c.details.game_running, false)
    }
    function test_missing_game_opens_setup_without_download_or_launch() {
        const c = controller(); c.library.installed = false; call(c, "play_game")
        compare(c.view.launches, 0); compare(c.view.detailRequests, 1)
        compare(result(c).status, "setup_required")
    }
    function test_running_game_is_never_toggled_off_by_play() {
        const c = controller(); c.details.game_running = true; call(c, "play_game")
        verify(!!result(c).error); compare(c.details.stops, 0); compare(c.view.launches, 0)
    }
    function test_confirmation_cannot_be_self_approved_and_decline_does_nothing() {
        const c = controller(); c.details.game_running = true
        call(c, "stop_game"); compare(result(c).status, "confirmation_required")
        call(c, "confirm_action", {approve:true}); verify(!!result(c).error); compare(c.details.stops, 0)
        c.assistant.turn_number++; call(c, "confirm_action", {approve:false})
        compare(result(c).status, "declined"); compare(c.details.stops, 0)
    }
    function test_later_confirmation_stops_through_existing_save_exit_handler() {
        const c = controller(); c.details.game_running = true; call(c, "stop_game")
        c.assistant.turn_number++; call(c, "confirm_action", {approve:true}); finish(c)
        compare(c.details.stops, 1); compare(result(c).status, "stopped")
    }
    function test_favorite_waits_for_persistence() {
        const c = controller(); call(c, "set_favorite", {favorite:true}); finish(c)
        compare(c.assistant.replies.length, 0)
        c.library.favoritePending = false; c.pollAction()
        compare(result(c).status, "saved"); compare(result(c).favorite, true)
    }
    function test_separate_video_modes_are_preserved() {
        const c = controller(); call(c, "control_media", {name:"mute"})
        compare(c.videoPreferences.couchMuted, true); compare(c.videoPreferences.gridMuted, true); compare(c.videoPreferences.detailsMuted, true)
        call(c, "control_media", {name:"unmute"})
        compare(c.videoPreferences.couchMuted, false); compare(c.videoPreferences.gridMuted, true); compare(c.videoPreferences.detailsMuted, true)
    }
    function test_microphone_enable_requires_later_confirmation() {
        const c = controller(); call(c, "set_preference", {name:"hands_free",value:true})
        compare(c.ai.hands_free, false); compare(result(c).status, "confirmation_required")
        c.assistant.turn_number++; call(c, "confirm_action", {approve:true})
        compare(c.ai.hands_free, true)
    }
    function test_settings_opening_does_not_claim_setup_completed() {
        const c = controller(); call(c, "open_settings", {name:"local-ai"})
        compare(c.app.opened, "settings:local-ai"); compare(result(c).status, "opened")
        verify(result(c).message.indexOf("not yet completed") >= 0)
    }
    function test_cancel_discards_pending_action_result_without_undoing_effects() {
        const c = controller(); call(c, "play_game"); c.assistant.busy = false
        compare(c.waiting, null); compare(c.assistant.replies.length, 0); compare(c.view.launches, 1)
    }
    function test_delete_collection_retains_game_and_requires_confirmation() {
        const c = controller(); call(c, "delete_collection", {collection_id:"collection"})
        compare(c.library.collectionExists, true)
        c.assistant.turn_number++; call(c, "confirm_action", {approve:true}); finish(c)
        compare(result(c).status, "deleted"); compare(c.library.installed, true)
    }
    function test_desktop_search_and_selection_never_enter_couch_mode() {
        const c = controller(); c.app.couchModeActive = false
        call(c, "browse_library", {query:"Mario",platform:"NES",shelf:"local"}); finish(c)
        compare(result(c).query, "Desktop Mario"); compare(c.app.couchModeActive, false)
        c.app.selectedGameId = ""
        call(c, "select_game", {game_id:"mario"}); finish(c)
        compare(result(c).status, "selected"); compare(c.app.selectedGameId, "mario")
        compare(c.view.closes, 0); compare(c.app.couchModeActive, false)
    }
    function test_desktop_hidden_selection_is_not_reported_as_success() {
        const c = controller(); c.app.couchModeActive = false; c.app.canSelect = false
        call(c, "select_game", {game_id:"mario"}); finish(c)
        verify(!!result(c).error)
    }
    function test_desktop_launch_uses_card_workflow_and_waits_for_actual_running_state() {
        const c = controller(); c.app.couchModeActive = false
        call(c, "play_game"); compare(c.app.launches, 1); compare(c.view.launches, 0)
        finish(c); compare(c.assistant.replies.length, 0)
        c.details.game_running = true; c.pollAction()
        compare(result(c).status, "running"); compare(c.app.couchModeActive, false)
    }
    function test_desktop_missing_game_opens_details_without_launch() {
        const c = controller(); c.app.couchModeActive = false; c.library.installed = false
        call(c, "play_game"); compare(c.app.opened, "details:mario")
        compare(result(c).status, "setup_required"); compare(c.app.launches, 0)
    }
    function test_desktop_navigation_panels_and_game_tools_use_shared_workflows() {
        const c = controller(); c.app.couchModeActive = false
        call(c, "navigate", {name:"back"}); compare(c.app.opened, "navigate:back")
        call(c, "open_panel", {name:"downloads"}); compare(c.app.opened, "panel:downloads")
        call(c, "open_game_tool", {name:"display"}); compare(c.app.opened, "details:mario")
        finish(c); compare(c.app.opened, "game:display"); compare(result(c).status, "opened")
        compare(c.app.couchModeActive, false)
    }
    function test_desktop_media_and_preferences_preserve_couch_mode_values() {
        const c = controller(); c.app.couchModeActive = false
        c.videoPreferences.couchMuted = true
        call(c, "control_media", {name:"pause"}); compare(c.app.opened, "media:pause")
        call(c, "set_preference", {name:"video_muted",value:false})
        compare(c.videoPreferences.detailsMuted, false); compare(c.videoPreferences.gridMuted, true); compare(c.videoPreferences.couchMuted, true)
        c.app.desktopMediaScope = "grid"
        call(c, "set_preference", {name:"video_muted",value:false})
        compare(c.videoPreferences.gridMuted, false); compare(c.videoPreferences.detailsMuted, false)
        call(c, "set_preference", {name:"video_muted",value:true})
        compare(c.videoPreferences.gridMuted, true); compare(c.videoPreferences.detailsMuted, false)
        call(c, "get_preferences")
        compare(result(c).video_audio_scope, "grid"); compare(result(c).video_muted, true)
        call(c, "set_preference", {name:"view_style",value:"list"})
        compare(c.library.view_mode, "list"); compare(c.library.couch_view_style, "wheel")
        call(c, "get_preferences"); compare(result(c).mode, "normal"); compare(result(c).view_style, "list")
        call(c, "set_preference", {name:"view_style",value:"wall"}); verify(!!result(c).error)
        compare(c.library.view_mode, "list"); compare(c.app.couchModeActive, false)
    }
    function test_only_explicit_mode_navigation_switches_modes() {
        const c = controller(); c.app.couchModeActive = false
        call(c, "navigate", {name:"couch_mode"}); compare(c.app.couchModeActive, true)
        call(c, "navigate", {name:"normal_mode"}); compare(c.app.couchModeActive, false)
    }
    function test_desktop_browse_collection_uses_real_id_and_rejects_missing_collection() {
        const c = controller(); c.app.couchModeActive = false
        call(c, "browse_library", {collection_id:"collection"}); finish(c)
        compare(c.app.browsedCollection, "collection"); compare(c.app.couchModeActive, false)
        call(c, "browse_library", {collection_id:"missing"})
        verify(!!result(c).error); compare(c.app.browsedCollection, "collection")
    }
}
