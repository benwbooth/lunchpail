import QtQuick

// An installed built-in model, real catalog and real post-transcription path.
// The shared router is in readOnlyProbe mode: launch attempts are observed but
// rejected before any emulator, download or persistent mutation can start.
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
    property bool clarified: false
    property var calls: []
    property string launchId: ""
    function fail(message) { console.error("LUNCHPAIL_LOCAL_COMMAND_FAILED " + message); Qt.exit(2) }
    function request(text) {
        calls = []; launchId = ""
        if (couch) view.acceptVoiceRequest(text)
        else desktop.acceptVoiceRequest(text)
    }
    Connections {
        target: probe.assistant
        function onTool_requested(id, name, argumentsJson) {
            probe.calls = probe.calls.concat([name])
            if (name === "play_game") {
                const args = JSON.parse(argumentsJson)
                probe.launchId = args.game_id || (probe.couch ? probe.view.selectedGameId : probe.app.selectedGameId)
            }
        }
    }
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (probe.speech.listening || probe.voice.speaking) { probe.fail("Unexpected microphone or speech playback"); return }
            if (!probe.library.ready || probe.library.loading || probe.library.filtering || probe.assistant.busy) return
            if (probe.step === 0) {
                const config = JSON.parse(probe.assistant.config_json)
                if (config.provider !== "builtin" || config.spoken_replies || !probe.assistant.ready) {
                    probe.fail("Requires isolated silent profile with an installed bundled model"); return
                }
                probe.app.visibility = 2; probe.app.width = 1280; probe.app.height = 900
                probe.request("open up super mario brothers")
                probe.step = 1
            } else if (probe.step === 1) {
                const result = JSON.parse(probe.assistant.result_json)
                console.log("LUNCHPAIL_LOCAL_COMMAND_REPLY mode=" + (probe.couch ? "couch" : "normal") + " " + JSON.stringify(result))
                if (result.error || !result.message || result.message.toLowerCase() === "open up super mario brothers") {
                    probe.fail("Command was echoed or failed: " + result.message); return
                }
                if (probe.calls[0] !== "get_context") { probe.fail("Context was not read first"); return }
                if (!probe.launchId) {
                    if (probe.clarified || probe.calls.indexOf("browse_library") < 0) {
                        probe.fail("No launch routing after title resolution: " + result.message); return
                    }
                    probe.clarified = true
                    probe.request("The original Super Mario Bros. on Nintendo Entertainment System. Open that game.")
                    return
                }
                const title = probe.library.display_title_for_game(probe.launchId)
                if (title !== "Super Mario Bros.") { probe.fail("Wrong game: " + title); return }
                console.log("LUNCHPAIL_LOCAL_COMMAND_ROUTED mode=" + (probe.couch ? "couch" : "normal") + " title=" + title + " id=" + probe.launchId)
                if (probe.couch) {
                    console.log("LUNCHPAIL_LOCAL_COMMAND_READY modes=normal,couch model=builtin microphone=off speech=off launches=blocked")
                    Qt.quit(); return
                }
                probe.assistant.clear(); probe.desktop.close(); probe.app.enterCouchMode()
                probe.couch = true; probe.clarified = false; probe.step = 2
            } else if (probe.step === 2 && probe.view.inputEnabled) {
                probe.request("open up super mario brothers")
                probe.step = 1
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: probe.fail("Timed out at step " + probe.step) }
}
