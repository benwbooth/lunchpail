import QtQuick

// Real, isolated local-provider navigation. No microphone, launches or writes.
Item {
    id: probe
    required property var app
    required property var library
    required property var assistant
    required property var speech
    required property var settingsDialog
    required property var gameToolDialog
    property int step: 0
    property bool capturing: false
    property string selectedTitle: ""
    property double closingStarted: 0
    function fail(reason) { console.error("LUNCHPAIL_DESKTOP_CONVERSATION_FAILED " + reason); Qt.exit(2) }
    function normalized(text) { return text.toLowerCase().replace(/[^a-z0-9]/g, "") }
    function checkReply() {
        const reply = JSON.parse(assistant.result_json)
        if (reply.error || !reply.message) { fail(reply.message || assistant.status); return false }
        return true
    }
    function capture(suffix) {
        capturing = true
        const surface = suffix === "settings" ? settingsDialog.contentItem
            : suffix === "game-tools" ? gameToolDialog.contentItem : app.desktopAssistantPanel
        if (!surface.grabToImage(function(image) {
            if (!image.saveToFile(probe.app.argumentValue("--screenshot-output") + "-desktop-" + suffix + ".png")) { probe.fail("Screenshot failed"); return }
            probe.capturing = false; probe.step++
        })) fail("Capture did not start")
    }
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (probe.speech.listening) { probe.fail("Microphone opened during a typed test"); return }
            if (probe.app.couchModeActive) { probe.fail("Normal navigation switched to Couch mode"); return }
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.step === 0) {
                const config = JSON.parse(probe.assistant.config_json)
                if (config.provider !== "ollama" || !config.profiles.ollama.endpoint.startsWith("http://127.0.0.1:") || config.spoken_replies) {
                    probe.fail("Requires isolated silent local-provider profile"); return
                }
                probe.app.visibility = 2; probe.app.width = 1440; probe.app.height = 1000
                probe.app.desktopAssistantPanel.open("Search for Super Mario Bros, and select the first result without launching it.")
                probe.app.desktopAssistantPanel.searchPanel.submit(); probe.step++
            } else if (probe.step === 1) {
                if (probe.assistant.busy) return
                if (!probe.checkReply()) return
                if (probe.normalized(probe.app.assistantQuery) !== "supermariobros" || probe.library.filtered_count < 1
                        || probe.library.row_for_game(probe.app.selectedGameId) < 0) {
                    probe.fail("Agent did not filter/select the real desktop library: query=" + probe.app.assistantQuery
                        + " selection=" + probe.app.selectedGameId + " reply=" + JSON.parse(probe.assistant.result_json).message); return
                }
                probe.selectedTitle = probe.library.display_title_for_game(probe.app.selectedGameId)
                probe.capture("search")
            } else if (probe.step === 2) {
                probe.app.desktopAssistantPanel.open("What game is selected? Quote its complete exact title.")
                probe.app.desktopAssistantPanel.searchPanel.submit(); probe.step++
            } else if (probe.step === 3) {
                if (probe.assistant.busy) return
                if (!probe.checkReply()) return
                if (!probe.normalized(JSON.parse(probe.assistant.result_json).message).includes(probe.normalized(probe.selectedTitle))) {
                    probe.fail("Follow-up did not use the real selection"); return
                }
                if (JSON.parse(probe.assistant.history_json).length !== 4) { probe.fail("Conversation history was lost"); return }
                probe.capture("followup")
            } else if (probe.step === 4) {
                probe.app.desktopAssistantPanel.open("Open Local AI and voice settings. Do not change any settings.")
                probe.app.desktopAssistantPanel.searchPanel.submit(); probe.step++
            } else if (probe.step === 5) {
                if (probe.assistant.busy) return
                if (!probe.checkReply()) return
                if (!probe.app.assistantScreenContext().settings_open) { probe.fail("Settings did not open"); return }
                probe.capture("settings")
            } else if (probe.step === 6) {
                probe.app.desktopAssistantPanel.open("Close settings using navigate back. Stay in normal mode.")
                probe.app.desktopAssistantPanel.searchPanel.submit(); probe.step++
            } else if (probe.step === 7) {
                if (probe.assistant.busy) return
                if (!probe.checkReply()) return
                if (probe.app.assistantScreenContext().settings_open) { probe.fail("Settings did not close"); return }
                probe.app.width = 1100; probe.app.height = 740; probe.step++
            } else if (probe.step === 8) {
                const row = probe.library.row_for_game(probe.app.selectedGameId)
                const expected = probe.library.game_id_for_row(Math.min(row + 1, probe.library.filtered_count - 1))
                probe.app.assistantNavigate("right")
                if (probe.app.selectedGameId !== expected) { probe.fail("Desktop directional navigation did not select the real next row"); return }
                probe.capture("compact")
            } else if (probe.step === 9) {
                const id = probe.app.selectedGameId
                probe.app.assistantShowDetails({id: id, title: probe.library.display_title_for_game(id), platform: probe.library.platform_for_game(id),
                    local: probe.library.local_for_game(id), downloadable: probe.library.downloadable_for_game(id)})
                probe.step++
            } else if (probe.step === 10) {
                probe.app.openCouchGameTool("media")
                if (probe.app.assistantScreenContext().game_tool !== "media") return
                probe.step++
            } else if (probe.step === 11) probe.capture("game-tools")
            else if (probe.step === 12) {
                probe.app.assistantNavigate("back")
                probe.closingStarted = Date.now()
                probe.step++
            } else if (probe.step === 13 && probe.app.assistantScreenContext().game_tool) {
                // Popup.visible stays true through its exit transition.
                if (Date.now() - probe.closingStarted > 3000) probe.fail("Game tools did not close")
            } else {
                console.log("LUNCHPAIL_DESKTOP_CONVERSATION_READY provider=ollama mode=normal search=real selection=real followup=verified settings=open-close microphone=off launches=blocked")
                Qt.quit()
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: probe.fail("Timeout at step " + probe.step) }
}
