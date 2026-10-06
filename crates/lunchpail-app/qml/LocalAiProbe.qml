import QtQuick

// Run with an isolated profile containing preverified test models. Exercises
// real QObjects and native inference; never opens the physical microphone.
Item {
    id: probe
    required property var app
    required property var view
    required property var library
    required property var ai
    required property var assistant
    required property var speech
    required property var settingsDialog
    property int step: 0
    property bool capturing: false
    function fail(reason) { console.error("LUNCHPAIL_LOCAL_AI_FAILED " + reason); Qt.exit(2) }
    function capture(item, name) {
        capturing = true
        item.grabToImage(function(result) {
            if (!result.saveToFile(probe.app.argumentValue("--screenshot-output") + "-" + name + ".png")) { probe.fail("screenshot " + name); return }
            console.log("LUNCHPAIL_LOCAL_AI_CAPTURE " + name)
            probe.capturing = false; probe.step++
        })
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.speech.listening) { probe.fail("microphone activated without consent"); return }
            if (probe.step === 0) {
                if (!probe.ai.assistant_ready || !probe.ai.speech_ready) { probe.fail("test models missing"); return }
                probe.app.width = 1920; probe.app.height = 1080
                probe.ai.select_assistant(probe.ai.assistant_model)
                probe.app.openSettingsFor("local-ai")
                probe.step++
            } else if (probe.step === 1) {
                if (probe.ai.busy) return
                if (!probe.ai.assistant_ready || !probe.ai.speech_ready) { probe.fail(probe.ai.status); return }
                probe.ai.detect_hardware(); probe.step++
            } else if (probe.step === 2) {
                if (probe.ai.busy) return
                console.log("LUNCHPAIL_LOCAL_AI_HARDWARE " + probe.ai.hardware)
                probe.app.positionRequestedSettingsSection()
                probe.step++
            } else if (probe.step === 3) {
                probe.capture(probe.settingsDialog.contentItem, "settings")
            } else if (probe.step === 4) {
                probe.settingsDialog.close()
                probe.step++
            } else if (probe.step === 5) {
                probe.app.enterCouchMode()
                probe.app.visibility = 2 // Windowed, so both test sizes are exact.
                probe.app.width = 1920; probe.app.height = 1080
                probe.step++
            } else if (probe.step === 6) {
                if (!probe.view.inputEnabled || !probe.view.visible) return
                probe.view.openSearch("", false)
                if (!probe.view.searchPanel.askMode) probe.view.searchPanel.toggleMode()
                probe.view.searchPanel.open("Find me a good SNES JRPG with an English translation patch.")
                probe.step++
            } else if (probe.step === 7) {
                if (!probe.view.searchOpen) { probe.fail("search closed before submission"); return }
                probe.view.searchPanel.submit()
                probe.step++
            } else if (probe.step === 8) {
                if (probe.assistant.busy) return
                const result = JSON.parse(probe.assistant.result_json || "{}")
                if (result.error || !result.message || JSON.parse(probe.assistant.history_json).length < 2) { probe.fail(probe.assistant.status); return }
                console.log("LUNCHPAIL_LOCAL_AI_ANSWER " + JSON.stringify(result))
                probe.capture(probe.view, "answer-1080p")
            } else if (probe.step === 9) {
                probe.app.width = 1280; probe.app.height = 720; probe.step++
            } else if (probe.step === 10) {
                probe.capture(probe.view, "answer-720p")
            } else if (probe.step === 11) {
                probe.view.searchPanel.handleNavigation("back")
                if (probe.view.searchOpen) { probe.fail("controller conversation navigation"); return }
                console.log("LUNCHPAIL_LOCAL_AI_READY models=verified inference=real controller=conversation microphone=off")
                Qt.quit()
            }
        }
    }
    Timer { interval: 300000; running: true; onTriggered: probe.fail("timeout at step " + probe.step) }
}
