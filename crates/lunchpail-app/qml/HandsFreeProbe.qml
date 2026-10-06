import QtQuick
import QtQuick.Controls

// Explicit diagnostic for an isolated profile with no AI models selected.
// Never install a model, open a microphone, call a provider or launch a game.
Item {
    id: probe
    required property var app
    required property var desktop
    required property var view
    required property var library
    required property var ai
    required property var assistant
    required property var speech
    required property var inputGuard
    required property var toggleButton
    property int step: 0
    property bool capturing: false
    readonly property string request: "open up super mario bros"
    function fail(message) { console.error("LUNCHPAIL_HANDS_FREE_FAILED step=" + step + " " + message); Qt.exit(2) }
    function capture(item, name) {
        capturing = true
        item.grabToImage(function(result) {
            if (!result.saveToFile(probe.app.argumentValue("--screenshot-output") + "-" + name + ".png")) {
                probe.fail("screenshot " + name); return
            }
            probe.capturing = false; probe.step++
        })
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (probe.speech.listening || probe.ai.busy || probe.assistant.busy) {
                probe.fail("unexpected microphone, download or provider activity"); return
            }
            if (probe.capturing || !probe.library.ready || probe.library.loading || probe.library.filtering) return
            if (probe.step === 0) {
                if (probe.assistant.ready || probe.ai.assistant_model || probe.ai.speech_model) {
                    probe.fail("use an isolated profile with assistant and speech disabled"); return
                }
                probe.app.width = 1040; probe.app.height = 900
                probe.ai.enable_hands_free(true) // Reproduce the old, incomplete saved preference.
                probe.step++
            } else if (probe.step === 1) {
                if (probe.desktop.handsFreeAllowed || probe.desktop.handsFreeLabel !== "Hands-free · Setup") {
                    probe.fail("incomplete setup enabled capture"); return
                }
                probe.toggleButton.ToolTip.visible = true
                probe.step++
            } else if (probe.step === 2) {
                if (probe.inputGuard.blocked) { probe.fail("header tooltip blocked input"); return }
                probe.toggleButton.ToolTip.visible = false
                probe.desktop.toggleHandsFree()
                probe.step++
            } else if (probe.step === 3) {
                const dialog = probe.desktop.handsFreeInstallDialog
                if (!dialog.visible || !dialog.assistantModel || probe.ai.hands_free) {
                    probe.fail("normal mode did not require assistant consent"); return
                }
                probe.capture(dialog.contentItem, "normal-setup")
            } else if (probe.step === 4) {
                probe.desktop.handsFreeSetupController.cancel()
                probe.desktop.acceptVoiceRequest(probe.request)
                probe.step++
            } else if (probe.step === 5) {
                probe.desktop.handsFreeSetupController.cancel()
                probe.desktop.close(); probe.desktop.open("")
                if (probe.desktop.searchPanel.preservedRequest !== probe.request) {
                    probe.fail("normal mode discarded the request"); return
                }
                probe.capture(probe.desktop.searchPanel, "normal-draft")
            } else if (probe.step === 6) {
                probe.desktop.close()
                probe.app.enterCouchMode()
                probe.app.visibility = 2
                probe.app.width = 1280; probe.app.height = 720
                probe.step++
            } else if (probe.step === 7) {
                if (!probe.view.inputEnabled || !probe.view.visible) return
                probe.view.toggleHandsFree()
                probe.step++
            } else if (probe.step === 8) {
                const dialog = probe.view.handsFreeSetupController.installDialog
                if (!dialog.visible || !dialog.assistantModel || probe.ai.hands_free) {
                    probe.fail("Couch mode did not require assistant consent"); return
                }
                probe.capture(dialog.contentItem, "couch-setup")
            } else if (probe.step === 9) {
                probe.view.handsFreeSetupController.cancel()
                probe.step++
            } else if (probe.step === 10) {
                if (!probe.view.inputEnabled) return
                probe.view.acceptVoiceRequest(probe.request)
                probe.step++
            } else if (probe.step === 11) {
                probe.view.handsFreeSetupController.cancel()
                probe.step++
            } else if (probe.step === 12) {
                if (!probe.view.inputEnabled) return
                probe.view.closeSearch(); probe.view.openSearch("", false)
                if (probe.view.searchPanel.preservedRequest !== probe.request || !probe.view.searchOpen) {
                    probe.fail("Couch mode discarded the request"); return
                }
                probe.capture(probe.view.searchPanel, "couch-draft")
            } else {
                console.log("LUNCHPAIL_HANDS_FREE_READY setup=normal,couch tooltip=nonblocking drafts=preserved microphone=off")
                Qt.quit()
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: probe.fail("timeout") }
}
