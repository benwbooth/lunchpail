import QtQuick

// Native integration probe: use an isolated profile and a local provider.
// Exercises real library navigation, QObjects and captions; never launches a
// game, enables the microphone, stores credentials or installs a model.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var assistant
    required property var speech
    required property var settingsDialog
    property int step: 0
    property bool capturing: false
    function normalized(text) { return text.toLowerCase().replace(/[^a-z0-9]/g, "") }
    function fail(reason) { console.error("LUNCHPAIL_CONVERSATION_FAILED " + reason); Qt.exit(2) }
    function capture(item, suffix) {
        capturing = true
        item.grabToImage(function(image) {
            if (!image.saveToFile(probe.app.argumentValue("--screenshot-output") + "-" + suffix + ".png")) { probe.fail("Could not save screenshot"); return }
            console.log("LUNCHPAIL_CONVERSATION_CAPTURE " + suffix)
            probe.capturing = false; probe.step++
        })
    }
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (probe.speech.listening) { probe.fail("Microphone opened during a typed test"); return }
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.step === 0) {
                const config = JSON.parse(probe.assistant.config_json)
                if (config.provider !== "ollama" || !config.profiles.ollama.endpoint.startsWith("http://127.0.0.1:") || config.spoken_replies) {
                    probe.fail("Requires an isolated, silent local-fixture provider profile"); return
                }
                probe.app.enterCouchMode(); probe.app.visibility = 2
                probe.app.width = 1920; probe.app.height = 1080; probe.step++
            } else if (probe.step === 1) {
                if (!probe.view.inputEnabled || !probe.view.visible) return
                probe.view.openSearch("search for super mario bros", false)
                if (!probe.view.searchPanel.askMode) { probe.fail("Conversation is not the default"); return }
                probe.view.searchPanel.submit(); probe.step++
            } else if (probe.step === 2) {
                if (probe.assistant.busy) return
                const result = JSON.parse(probe.assistant.result_json)
                if (result.error || !result.message) { probe.fail(result.message || probe.assistant.status); return }
                if (probe.normalized(probe.view.searchText) !== "supermariobros" || probe.library.filtered_count < 1) {
                    probe.fail("Agent did not update the real browser: query=" + probe.view.searchText + " reply=" + result.message); return
                }
                if (JSON.parse(probe.assistant.history_json).length !== 2) { probe.fail("Missing player/assistant transcript"); return }
                probe.capture(probe.view, "search-captions-1080p")
            } else if (probe.step === 3) {
                probe.view.openSearch("what game is selected? Please quote its complete exact title.", false); probe.view.searchPanel.submit(); probe.step++
            } else if (probe.step === 4) {
                if (probe.assistant.busy) return
                const result = JSON.parse(probe.assistant.result_json)
                if (result.error || !probe.normalized(result.message).includes(probe.normalized(probe.view.selectedTitle))) {
                    probe.fail("Follow-up lost the real selection: selected=" + probe.view.selectedTitle + " reply=" + result.message); return
                }
                if (JSON.parse(probe.assistant.history_json).length !== 4) { probe.fail("Follow-up lost conversation history"); return }
                probe.capture(probe.view, "conversation-1080p")
            } else if (probe.step === 5) {
                probe.app.width = 1280; probe.app.height = 720; probe.step++
            } else if (probe.step === 6) {
                probe.capture(probe.view, "conversation-720p")
            } else if (probe.step === 7) {
                probe.view.closeSearch(); probe.app.openSettingsFor("local-ai"); probe.step++
            } else if (probe.step === 8) {
                probe.app.positionRequestedSettingsSection(); probe.step++
            } else if (probe.step === 9) {
                probe.capture(probe.settingsDialog.contentItem, "settings")
            } else {
                console.log("LUNCHPAIL_CONVERSATION_READY provider=ollama model=" + JSON.parse(probe.assistant.config_json).profiles.ollama.model
                    + " transport=real-http navigation=real followup=verified microphone=off launches=blocked")
                Qt.quit()
            }
        }
    }
    Timer { interval: 90000; running: true; onTriggered: probe.fail("Timeout at step " + probe.step) }
}
