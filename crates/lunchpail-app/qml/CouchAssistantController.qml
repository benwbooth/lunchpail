pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: controller
    required property var app
    required property var view
    required property var library
    required property var details
    required property var assistant
    required property var ai
    required property var feedbackSettings
    required property var videoPreferences
    property bool readOnlyProbe: false
    property var pendingConfirmation: null
    property var waiting: null
    readonly property var config: JSON.parse(assistant.config_json || "{}")

    function selected(id) {
        id = id || (app.couchModeActive ? view.selectedGameId : app.selectedGameId)
        if (!id || !library.display_title_for_game(id)) throw new Error("No valid game is selected. Search and choose a game first.")
        return {id: id, title: library.display_title_for_game(id), platform: library.platform_for_game(id),
            local: library.local_for_game(id), downloadable: library.downloadable_for_game(id), favorite: library.is_favorite(id)}
    }
    function collections() {
        const rows = []
        for (let i = 0; i < library.collection_count; ++i)
            rows.push({id: library.collection_id_at(i), name: library.collection_name_at(i),
                description: library.collection_description_at(i), kind: library.collection_kind_at(i), count: library.collection_game_count_at(i)})
        return rows
    }
    function context() {
        if (pendingConfirmation && Date.now() > pendingConfirmation.expires) pendingConfirmation = null
        let game = null
        try { game = selected("") } catch (_) {}
        return {screen: app.assistantScreenContext(), selected_game: game, games: JSON.parse(library.conversation_games_json()),
            total_results: library.filtered_count, filtering: library.filtering, query: app.couchModeActive ? view.searchText : app.assistantQuery,
            game_running: details.game_running, session_title: details.session_title, launch_busy: details.launch_busy,
            launch_status: details.launch_status, pending_confirmation: pendingConfirmation ? pendingConfirmation.question : null}
    }
    function preferences() {
        return {mode: app.couchModeActive ? "couch" : "normal",
            view_style: app.couchModeActive ? library.couch_view_style : library.view_mode,
            video_muted: app.couchModeActive ? videoPreferences.couchMuted : videoPreferences.normalMuted,
            navigation_sounds: feedbackSettings.soundsEnabled, navigation_volume: feedbackSettings.soundVolume,
            music_enabled: library.couch_music_enabled, music_volume: library.couch_music_volume,
            spoken_replies: config.spoken_replies, captions: config.captions, wake_word: config.wake_word,
            hands_free: ai.hands_free, voice_rate: config.voice_rate, voice_volume: config.voice_volume}
    }
    function complete(id, result) {
        if (readOnlyProbe) console.log("LUNCHPAIL_CONVERSATION_TOOL_RESULT " + id + " " + JSON.stringify({
            status: result.status, error: result.error, query: result.query, game: result.game || result.selected_game}))
        assistant.complete_tool(id, JSON.stringify(result))
    }
    function defer(id, kind, extra) {
        waiting = Object.assign({id: id, kind: kind, started: Date.now()}, extra || {})
        actionPoll.restart()
    }
    function askConfirmation(id, name, args, question) {
        pendingConfirmation = {name: name, arguments: args, question: question, turn: assistant.turn_number, expires: Date.now() + 120000}
        complete(id, {status: "confirmation_required", question: question, instruction: "Ask the user and wait for their next reply. Do not call confirm_action in this turn."})
    }
    function focusGame(game) {
        if (app.couchModeActive) view.closeSearch()
        if (library.row_for_game(game.id) < 0) app.assistantBrowse("", game.platform, "all")
        if (app.couchModeActive) {
            view.beginGameHandoff(game.id, game.platform)
            view.focusGameById(game.id)
        } else app.assistantSelectGame(game)
    }
    function execute(id, name, args, confirmed) {
        if (readOnlyProbe) console.log("LUNCHPAIL_CONVERSATION_TOOL " + name + " " + JSON.stringify(args))
        if (readOnlyProbe && ["get_context", "browse_library", "select_game", "get_preferences", "get_collections", "open_settings", "navigate"].indexOf(name) < 0)
            throw new Error("This diagnostic only permits read-only navigation, never launch or saved changes")
        if (waiting) throw new Error("Another app action is still pending")
        switch (name) {
        case "get_context": complete(id, context()); break
        case "browse_library":
            if (app.couchModeActive) view.closeSearch()
            if (args.collection_id && !library.collection_exists(args.collection_id)) throw new Error("Collection no longer exists; read get_collections for current IDs")
            app.assistantBrowse(args.query || "", args.platform || "", args.shelf || "all", args.collection_id || "")
            defer(id, "browse"); break
        case "select_game": {
            const game = selected(args.game_id)
            focusGame(game); defer(id, "select", {game: game}); break
        }
        case "play_game": {
            if (details.game_running) throw new Error("A game is already running. Ask the user whether to stop it first.")
            if (details.launch_busy) throw new Error("A launch is already in progress. Check its status instead of launching again.")
            const game = selected(args.game_id)
            focusGame(game)
            if (!game.local) {
                if (app.couchModeActive) view.requestDetails()
                else app.assistantShowDetails(game)
                complete(id, {status: "setup_required", game: game, message: "Game is not installed. Opened its details; download/import needs the user's choice."})
            } else {
                // The normal root workflow handles save-cloud, resume choice,
                // missing firmware, emulator installation and launch errors.
                if (app.couchModeActive) {
                    view.launchStatusOverlayOpen = true
                    view.launchRequested()
                } else app.assistantLaunchGame(game)
                defer(id, "launch", {game: game})
            }
            break
        }
        case "stop_game":
            if (!details.game_running) { complete(id, {status: "not_running"}); break }
            if (!confirmed) { askConfirmation(id, name, args, "Stop the running game? Unsaved progress could be lost."); break }
            details.stop_emulator(); defer(id, "stop"); break
        case "navigate":
            if (app.couchModeActive) view.closeSearch()
            if (args.name === "normal_mode") app.exitCouchMode()
            else if (args.name === "couch_mode") app.enterCouchMode()
            else if (!app.couchModeActive || args.name === "back") app.assistantNavigate(args.name)
            else if (args.name === "platforms") view.openPlatformWheel()
            else if (args.name === "collections") view.openCollectionWheel()
            else view.handleNavigation(args.name)
            complete(id, {status: "navigated", action: args.name, context: context()}); break
        case "open_settings":
            if (app.couchModeActive) view.closeSearch()
            app.openSettingsFor(args.name === "general" ? "" : args.name)
            complete(id, {status: "opened", section: args.name, message: "Settings opened. Setup is not yet completed; enter credentials privately in the fields."}); break
        case "open_panel":
            if (app.couchModeActive) view.closeSearch()
            app.assistantOpenPanel(args.name)
            complete(id, {status: "opened", panel: args.name, message: "Workflow opened; no claim of completion."}); break
        case "open_game_tool": {
            const game = selected("")
            if (app.couchModeActive) { view.closeSearch(); view.requestDetails() }
            else app.assistantShowDetails(game)
            defer(id, "game_tool", {game: game, section: args.name}); break
        }
        case "control_media": {
            if (!app.couchModeActive) { complete(id, app.assistantControlMedia(args.name)); break }
            const player = view.platformWheelOpen ? view.systemVideoPreview : view.gameVideoPreview
            if (args.name === "mute" || args.name === "unmute") {
                const muted = args.name === "mute"
                if (videoPreferences.couchMuted !== muted) videoPreferences.toggle(true)
            } else if (args.name === "play" || args.name === "pause") player.paused = args.name === "pause"
            else app.assistantFullscreen(args.name)
            complete(id, {status: "updated", muted: videoPreferences.couchMuted, paused: player.paused, playing: player.playing}); break
        }
        case "set_favorite": {
            const game = selected(args.game_id)
            library.set_favorite(game.id, args.favorite)
            defer(id, "favorite", {game: game, favorite: args.favorite}); break
        }
        case "get_preferences": complete(id, preferences()); break
        case "set_preference": {
            if (args.name === "hands_free" && args.value && !confirmed) {
                askConfirmation(id, name, args, "Enable hands-free listening while Lunchpail is focused, in normal and Couch modes? The microphone will listen locally; transcribed requests go to your chosen AI provider.")
                break
            }
            if (args.name === "view_style") {
                if (app.couchModeActive) {
                    if (["wheel", "shelf", "wall", "album"].indexOf(args.value) < 0) throw new Error("Couch mode supports wheel, shelf, wall or album")
                    if (!library.save_couch_view_style(args.value)) throw new Error("Could not save the view style")
                } else {
                    if (["grid", "list"].indexOf(args.value) < 0) throw new Error("Normal mode supports grid or list")
                    library.choose_view_mode(args.value)
                }
            } else if (args.name === "video_muted") {
                const muted = app.couchModeActive ? videoPreferences.couchMuted : videoPreferences.normalMuted
                if (muted !== args.value) videoPreferences.toggle(app.couchModeActive)
            } else if (args.name === "navigation_sounds") { feedbackSettings.soundsEnabled = args.value; feedbackSettings.sync() }
            else if (args.name === "navigation_volume") { feedbackSettings.soundVolume = args.value; feedbackSettings.sync() }
            else if (args.name === "music_enabled" || args.name === "music_volume") {
                if (!library.save_couch_audio_settings(args.name === "music_enabled" ? args.value : library.couch_music_enabled,
                    args.name === "music_volume" ? args.value : library.couch_music_volume)) throw new Error("Could not save music preferences")
            } else if (args.name === "hands_free") {
                if (args.value && !ai.speech_ready) throw new Error("Install a speech recognition model in AI & voice settings first")
                ai.enable_hands_free(args.value)
            } else {
                const next = JSON.parse(assistant.config_json)
                next[args.name] = args.value
                assistant.configure(JSON.stringify(next))
            }
            complete(id, {status: "updated", preferences: preferences()}); break
        }
        case "get_collections": complete(id, {collections: collections()}); break
        case "save_collection": {
            if (library.collection_busy) throw new Error("A collection save is already pending")
            if (!args.name || !args.name.trim()) throw new Error("A collection name is required")
            const before = collections().map(c => c.id)
            if (args.collection_id) {
                if (!library.collection_exists(args.collection_id)) throw new Error("Collection no longer exists")
                library.update_collection(args.collection_id, args.name, args.description || "")
            } else library.create_collection(args.name, args.description || "")
            defer(id, "collection_save", {collection_id: args.collection_id || "", name: args.name, before: before}); break
        }
        case "delete_collection":
            if (!args.collection_id || !library.collection_exists(args.collection_id)) throw new Error("Choose an existing collection ID")
            if (!confirmed) { askConfirmation(id, name, args, "Delete this collection? The games themselves will be kept."); break }
            library.delete_collection(args.collection_id)
            defer(id, "collection_delete", {collection_id: args.collection_id}); break
        case "set_collection_membership": {
            if (!library.collection_exists(args.collection_id)) throw new Error("Collection no longer exists")
            const collection = collections().find(c => c.id === args.collection_id)
            if (collection.kind !== "manual") throw new Error("Smart collections use rules. Open their settings to change membership.")
            const game = selected(args.game_id)
            library.set_collection_membership(args.collection_id, game.id, args.included)
            defer(id, "membership", {collection_id: args.collection_id, game: game, included: args.included}); break
        }
        case "confirm_action": {
            const action = pendingConfirmation
            if (!action || action.expires < Date.now()) { pendingConfirmation = null; throw new Error("No pending confirmation") }
            if (action.turn >= assistant.turn_number) throw new Error("Wait for the user's answer on a later turn")
            pendingConfirmation = null
            if (!args.approve) complete(id, {status: "declined"})
            else execute(id, action.name, action.arguments, true)
            break
        }
        default: throw new Error("Unsupported app capability")
        }
    }
    function pollAction() {
        const action = waiting
        if (!action) return
        if (!assistant.busy) { waiting = null; return }
        let result = null
        const elapsed = Date.now() - action.started
        if (elapsed < 180) return
        if (action.kind === "browse" && !library.filtering && !app.assistantScreenContext().filtering) result = context()
        else if (action.kind === "select" && !library.filtering && !app.assistantScreenContext().filtering) {
            const found = app.couchModeActive ? view.focusGameById(action.game.id) : app.assistantSelectGame(action.game)
            result = found ? {status: "selected", game: action.game} : {error: "Game is hidden by the active filters"}
        } else if (action.kind === "launch") {
            if (details.game_running) result = {status: "running", game: action.game, session_title: details.session_title}
            else if (app.assistantScreenContext().confirmation_open) result = {status: "user_action_required", message: "A save/resume or setup dialog needs your choice. The game is not running yet."}
            else if (elapsed > 3500 && !details.launch_busy && !details.loading && !details.launch_discovery_busy
                     && !app.assistantScreenContext().launch_pending) result = {status: "not_running", message: details.launch_status || "Launch did not start. Check the app's setup prompt."}
        } else if (action.kind === "stop" && !details.game_running) result = {status: "stopped"}
        else if (action.kind === "favorite" && !library.favorite_pending(action.game.id)) result = library.is_favorite(action.game.id) === action.favorite
            ? {status: "saved", game_id: action.game.id, favorite: action.favorite} : {error: library.favorite_message || "Favorite could not be saved"}
        else if (action.kind === "game_tool" && !details.loading && details.game_id === action.game.id) {
            app.openCouchGameTool(action.section); result = {status: "opened", section: action.section, game: action.game}
        } else if (action.kind.indexOf("collection_") === 0 && !library.collection_busy) {
            const rows = collections()
            if (action.kind === "collection_delete") result = !library.collection_exists(action.collection_id)
                ? {status: "deleted", collection_id: action.collection_id} : {error: library.collection_message}
            else {
                const row = rows.find(c => action.collection_id ? c.id === action.collection_id && c.name === action.name : action.before.indexOf(c.id) < 0 && c.name === action.name)
                result = row ? {status: "saved", collection: row} : {error: library.collection_message || "Collection save failed"}
            }
        } else if (action.kind === "membership" && !library.collection_busy) result = library.collection_contains(action.collection_id, action.game.id) === action.included
            ? {status: "saved", included: action.included} : {error: library.collection_message || "Membership save failed"}
        if (!result && elapsed > 60000) result = {status: "pending", message: "Action has not completed yet. Check the screen before retrying.", context: context()}
        if (result) { waiting = null; complete(action.id, result) }
    }
    Timer { id: actionPoll; interval: 80; repeat: true; running: !!controller.waiting; onTriggered: controller.pollAction() }
    Connections {
        target: controller.assistant
        function onTool_requested(id, name, argumentsJson) {
            if (!controller.assistant.busy) return
            try { controller.execute(id, name, JSON.parse(argumentsJson), false) }
            catch (error) { controller.complete(id, {error: error.message}) }
        }
        function onBusyChanged() { if (!controller.assistant.busy) controller.waiting = null }
        function onHistory_jsonChanged() { if (controller.assistant.history_json === "[]") controller.pendingConfirmation = null }
    }
}
