import QtQuick

// Opt-in integration check against the real catalog and shared voice/typed
// routing. The normal tool controller blocks every launch before any mutation.
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
    property int phrase: 0
    property bool couch: false
    property string faxId: ""
    property string backgroundId: ""
    property string launchId: ""
    property var calls: []
    property double started: 0
    readonly property var cases: [
        {text:"play facsinidu for NES", intent:"play", clear:true},
        {text:"no, I said faxanadoo", intent:"play"},
        {text:"fax in a do", intent:"play"},
        {text:"Faxanadu", intent:"play"},
        {text:"find facsinidu for NES", intent:"search", clear:true},
        {text:"no, I meant faxanadoo", intent:"search"},
        {text:"fax in a do", intent:"search"},
        {text:"play Faxanadu 2", intent:"none", clear:true},
        {text:"play facsinidu for SNES", intent:"none", clear:true}
    ]
    function fail(message) { console.error("LUNCHPAIL_TITLE_RECOVERY_FAILED mode=" + (couch ? "couch" : "normal") + " phrase=" + phrase + " " + message); Qt.exit(2) }
    Connections {
        target: probe.assistant
        function onTool_requested(id, name, argumentsJson) {
            probe.calls = probe.calls.concat([name])
            if (name === "play_game") probe.launchId = JSON.parse(argumentsJson).game_id
        }
    }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            if (probe.speech.listening || probe.voice.speaking) return probe.fail("microphone or voice enabled")
            if (!probe.library.ready || probe.library.loading || probe.library.filtering || probe.assistant.busy
                    || probe.app.assistantScreenContext().filtering) return
            if (probe.step === 0) {
                const config = JSON.parse(probe.assistant.config_json)
                if (config.provider !== "builtin" || config.spoken_replies || !probe.assistant.ready)
                    return probe.fail("requires isolated silent profile with a bundled model")
                probe.app.visibility = 2; probe.app.width = 1280; probe.app.height = 900
                const fax = JSON.parse(probe.library.conversation_resolve_game_json("Faxanadu", "NES"))
                const background = JSON.parse(probe.library.conversation_resolve_game_json("Super Mario Bros.", "NES"))
                probe.faxId = fax.preferred_game_id; probe.backgroundId = background.preferred_game_id
                if (!probe.faxId || !probe.backgroundId) return probe.fail("missing real catalog fixtures")
                for (const heard of ["facsinidu", "faxanadoo", "fax in a do"]) {
                    const result = JSON.parse(probe.library.conversation_match_game_json(heard, "NES", "[]", probe.backgroundId))
                    if (!result.auto_resolved || result.preferred_game_id !== probe.faxId)
                        return probe.fail("full catalog resolution " + heard + " " + JSON.stringify(result))
                }
                probe.step = 1
            } else if (probe.step === 1) {
                if (probe.cases[probe.phrase].clear) probe.assistant.clear()
                probe.app.assistantBrowse("Super Mario Bros.", "Nintendo Entertainment System", "all")
                probe.step = 2
            } else if (probe.step === 2) {
                if (probe.couch) probe.view.focusGameById(probe.backgroundId)
                else probe.app.assistantSelectGame({id:probe.backgroundId})
                probe.step = 3
            } else if (probe.step === 3) {
                const selected = probe.couch ? probe.view.selectedGameId : probe.app.selectedGameId
                if (selected !== probe.backgroundId) return probe.fail("unrelated selection fixture")
                probe.speech.vocabulary_requested()
                const hints = JSON.parse(probe.speech.vocabulary_json)
                if (hints.length > 32 || hints.indexOf("Super Mario Bros.") < 0) return probe.fail("live vocabulary missing selected title")
                probe.calls = []; probe.launchId = ""; probe.started = Date.now()
                const test = probe.cases[probe.phrase]
                if (probe.phrase === 4) {
                    if (probe.couch) { probe.view.openSearch(test.text, false); probe.view.searchPanel.submit() }
                    else { probe.desktop.open(test.text); probe.desktop.searchPanel.submit() }
                } else if (probe.couch) probe.view.acceptVoiceRequest(test.text)
                else probe.desktop.acceptVoiceRequest(test.text)
                probe.step = 4
            } else if (probe.step === 4) {
                const result = JSON.parse(probe.assistant.result_json)
                if (result.error || !result.message) return probe.fail("request failed " + JSON.stringify(result))
                const test = probe.cases[probe.phrase]
                if (test.intent === "play") {
                    if (probe.launchId !== probe.faxId || probe.calls.indexOf("resolve_game") < 0)
                        return probe.fail("wrong or missing launch target " + probe.launchId + " " + result.message)
                } else if (probe.launchId) return probe.fail("search/correction unexpectedly launched")
                if (test.intent === "search") {
                    const query = probe.couch ? probe.view.searchText : probe.app.assistantQuery
                    if (query.toLowerCase() !== "faxanadu" || probe.library.filtered_count < 1)
                        return probe.fail("search did not recover canonical title: " + query + " " + result.message)
                }
                console.log("LUNCHPAIL_TITLE_RECOVERY_CASE mode=" + (probe.couch ? "couch" : "normal")
                    + " input=" + test.text + " intent=" + test.intent + " ms=" + (Date.now() - probe.started)
                    + " reply=" + result.message)
                probe.phrase++
                if (probe.phrase < probe.cases.length) { probe.step = 1; return }
                if (!probe.couch) {
                    probe.desktop.close(); probe.app.enterCouchMode(); probe.couch = true; probe.phrase = 0; probe.step = 1
                } else {
                    console.log("LUNCHPAIL_TITLE_RECOVERY_READY cases=18 modes=normal,couch repeated_corrections=pass exact_ids=pass unrelated_selection=pass vocabulary=pass sequels=pass explicit_platform=pass microphone=off launches=blocked")
                    Qt.quit()
                }
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: probe.fail("timeout stage=" + probe.step) }
}
