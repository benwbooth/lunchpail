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
    property var phrases: ["let's play some super mario brothers", "open up super mario brothers", "play Super Mario Bros. on NES"]
    property var calls: []
    property string launchId: ""
    property string backgroundId: ""
    property double started: 0
    property double routedMs: 0
    function fail(message) { console.error("LUNCHPAIL_LOCAL_COMMAND_FAILED " + message); Qt.exit(2) }
    function request(text) {
        calls = []; launchId = ""; started = Date.now(); routedMs = 0
        if (couch) view.acceptVoiceRequest(text)
        else desktop.acceptVoiceRequest(text)
    }
    Connections {
        target: probe.assistant
        function onTool_requested(id, name, argumentsJson) {
            probe.calls = probe.calls.concat([name])
            if (name === "play_game") {
                const args = JSON.parse(argumentsJson)
                probe.launchId = args.game_id || ""
                probe.routedMs = Date.now() - probe.started
            }
        }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (probe.speech.listening || probe.voice.speaking) { probe.fail("Unexpected microphone or speech playback"); return }
            if (!probe.library.ready || probe.library.loading || probe.library.filtering || probe.assistant.busy
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
                probe.app.assistantBrowse("Faxanadu", "Nintendo Entertainment System", "all")
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
                if (probe.calls.join(",") !== "get_context,resolve_game,play_game") { probe.fail("Unexpected routing: " + probe.calls); return }
                const title = probe.library.display_title_for_game(probe.launchId)
                if (title !== "Super Mario Bros." || probe.launchId === probe.backgroundId) { probe.fail("Wrong game: " + title); return }
                if (probe.routedMs > 5000) { probe.fail("Simple command took " + probe.routedMs + " ms"); return }
                console.log("LUNCHPAIL_LOCAL_COMMAND_ROUTED mode=" + (probe.couch ? "couch" : "normal")
                    + " selected=Faxanadu phrase=" + probe.phrases[probe.phrase] + " title=" + title
                    + " id=" + probe.launchId + " elapsed_ms=" + probe.routedMs)
                probe.assistant.clear()
                probe.phrase++
                if (probe.phrase < probe.phrases.length) { probe.step = 1; return }
                if (probe.couch) {
                    console.log("LUNCHPAIL_LOCAL_COMMAND_READY modes=normal,couch commands=6 inference=none microphone=off speech=off launches=blocked")
                    Qt.quit(); return
                }
                probe.desktop.close(); probe.app.enterCouchMode()
                probe.couch = true; probe.phrase = 0; probe.step = 1
            }
        }
    }
    Timer { interval: 120000; running: true; onTriggered: probe.fail("Timed out at step " + probe.step) }
}
