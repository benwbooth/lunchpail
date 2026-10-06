import QtQuick

// Real catalog and post-transcription routing, with an unrelated game selected.
// The shared router blocks launch attempts before emulator/download mutations.
Item {
    id: probe
    required property var app
    required property var desktop
    required property var view
    required property var library
    required property var assistant
    required property var speech
    required property var voice
    property int step: 0
    property bool couch: false
    property int phrase: 0
    property var phrases: ["let's play some super mario brothers", "open up super mario brothers", "play Super Mario Bros. on NES", "SUPER MARIO BROTHERS", "take me to super mario brothers", "take me to super mario brothers", "let's play super mario bros", "just the original super mario bros for nes", "just the original N ES version", "take me to the original super mario brothers for N ES"]
    property var calls: []
    property string launchId: ""
    property string backgroundId: ""
    property string browseQuery: ""
    property bool capturing: false
    property bool finished: false
    property double started: 0
    property double routedMs: 0
    function fail(message) { console.error("LUNCHPAIL_LOCAL_COMMAND_FAILED " + message); Qt.exit(2) }
    function request(text) {
        calls = []; launchId = ""; browseQuery = ""; started = Date.now(); routedMs = 0
        if (phrase === 5) {
            if (couch) { view.openSearch(text, false); view.searchPanel.submit() }
            else { desktop.open(text); desktop.searchPanel.submit() }
        } else if (couch) view.acceptVoiceRequest(text)
        else desktop.acceptVoiceRequest(text)
    }
    function nextPhrase() {
        phrase++
        // Reproduce repeated-title and short platform follow-ups in one chat.
        if (phrase !== 7 && phrase !== 8) assistant.clear()
        if (phrase < phrases.length) { step = 1; return }
        if (couch) {
            finished = true
            console.log("LUNCHPAIL_LOCAL_COMMAND_READY modes=normal,couch phrases=20 input=voice,typed inference=none microphone=off speech=off launches=blocked")
            Qt.quit(); return
        }
        desktop.close(); app.enterCouchMode()
        couch = true; phrase = 0; step = 1
    }
    function finishSearch() {
        const output = app.argumentValue("--screenshot-output")
        if (phrase !== 5 || !output) { nextPhrase(); return }
        capturing = true
        const surface = couch ? view : desktop
        const started = surface.grabToImage(function(result) {
            if (!result.saveToFile(output + (probe.couch ? "-couch.png" : "-normal.png"))) {
                probe.fail("Could not capture unified assistant"); return
            }
            probe.capturing = false; probe.nextPhrase()
        })
        if (!started) fail("Could not start unified assistant capture")
    }
    function verifyAllGames() {
        const screen = app.assistantScreenContext()
        const expectedPlatform = phrase === 9 ? "Nintendo Entertainment System" : ""
        if (screen.shelf || screen.platform !== expectedPlatform || screen.collection_id) {
            fail("Search did not leave the previous Favorites/platform scope"); return false
        }
        const games = JSON.parse(library.conversation_games_json())
        if (!games.some(game => game.title === "Super Mario Bros." && game.platform === "Nintendo Entertainment System")) {
            fail("All Games search did not include the NES Mario result"); return false
        }
        return true
    }
    Connections {
        target: probe.assistant
        function onTool_requested(id, name, argumentsJson) {
            probe.calls = probe.calls.concat([name])
            if (name === "browse_library") probe.browseQuery = JSON.parse(argumentsJson).query
            if (name === "play_game") {
                const args = JSON.parse(argumentsJson)
                probe.launchId = args.game_id || ""
                probe.routedMs = Date.now() - probe.started
            }
        }
    }
    Timer {
        interval: 100; repeat: true; running: !probe.finished
        onTriggered: {
            if (probe.speech.listening || probe.voice.speaking) { probe.fail("Unexpected microphone or speech playback"); return }
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering || probe.assistant.busy
                    || probe.app.assistantScreenContext().filtering) return
            if (probe.step === 0) {
                const config = JSON.parse(probe.assistant.config_json)
                if (config.provider !== "builtin" || config.spoken_replies || !probe.assistant.ready) {
                    probe.fail("Requires isolated silent profile with an installed bundled model"); return
                }
                probe.app.visibility = 2; probe.app.width = 1280; probe.app.height = 900
                const background = JSON.parse(probe.library.conversation_resolve_game_json("Faxanadu", "NES"))
                if (background.total_matches !== 1) { probe.fail("Faxanadu background fixture is not unique"); return }
                probe.backgroundId = background.games[0].id
                probe.step = 1
            } else if (probe.step === 1) {
                if (probe.couch && !probe.view.inputEnabled) return
                probe.app.assistantBrowse("Faxanadu", "Nintendo Entertainment System", "favorites")
                probe.step = 2
            } else if (probe.step === 2) {
                if (probe.couch) probe.view.focusGameById(probe.backgroundId)
                else probe.app.assistantSelectGame({id:probe.backgroundId})
                probe.step = 3
            } else if (probe.step === 3) {
                const selected = probe.couch ? probe.view.selectedGameId : probe.app.selectedGameId
                if (selected !== probe.backgroundId) { probe.fail("Faxanadu was not selected before the command"); return }
                probe.request(probe.phrases[probe.phrase])
                probe.step = 4
            } else if (probe.step === 4) {
                const result = JSON.parse(probe.assistant.result_json)
                if (result.error || !result.message) { probe.fail("Command failed: " + result.message); return }
                if ((probe.phrase >= 3 && probe.phrase <= 5) || probe.phrase === 9) {
                    if (probe.launchId || probe.calls.join(",") !== "get_context,browse_library" || !probe.verifyAllGames()) {
                        probe.fail("Title request did not search All Games directly"); return
                    }
                    if (probe.browseQuery !== "super mario brothers") {
                        probe.fail("Request words leaked into the title filter: " + probe.browseQuery); return
                    }
                    const elapsed = Date.now() - probe.started
                    if (elapsed > 5000) { probe.fail("Search took " + elapsed + " ms"); return }
                    console.log("LUNCHPAIL_LOCAL_COMMAND_SEARCHED mode=" + (probe.couch ? "couch" : "normal")
                        + " input=" + (probe.phrase === 5 ? "typed" : "voice")
                        + " initial_scope=favorites phrase=" + probe.phrases[probe.phrase] + " all_games=true elapsed_ms=" + elapsed)
                    probe.finishSearch(); return
                }
                if (!probe.launchId) {
                    probe.fail("Expected a grounded default without a clarification: " + result.message); return
                }
                if (probe.calls.join(",") !== "get_context,resolve_game,play_game") { probe.fail("Unexpected routing: " + probe.calls); return }
                const title = probe.library.display_title_for_game(probe.launchId)
                if (title !== "Super Mario Bros." || probe.launchId === probe.backgroundId) { probe.fail("Wrong game: " + title); return }
                const nes = JSON.parse(probe.library.conversation_resolve_game_json("Super Mario Bros.", "NES"))
                if (probe.launchId !== nes.preferred_game_id) { probe.fail("Did not choose the original NES release: " + probe.launchId); return }
                if (probe.routedMs > 5000) { probe.fail("Simple command took " + probe.routedMs + " ms"); return }
                console.log("LUNCHPAIL_LOCAL_COMMAND_ROUTED mode=" + (probe.couch ? "couch" : "normal")
                    + " initial_selected=Faxanadu phrase=" + probe.phrases[probe.phrase] + " title=" + title
                    + " id=" + probe.launchId + " platform=NES clarified=false elapsed_ms=" + probe.routedMs)
                probe.nextPhrase()
            }
        }
    }
    Timer { interval: 180000; running: !probe.finished; onTriggered: probe.fail("Timed out at step " + probe.step) }
}
