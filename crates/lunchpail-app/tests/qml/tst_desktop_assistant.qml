import QtQuick
import QtQuick.Controls as Controls
import QtMultimedia
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "DesktopAssistant"
    when: windowShown
    visible: true; width: 1000; height: 740
    readonly property var overlay: Controls.Overlay.overlay
    property var audioPane: null
    property bool previewMuted: true
    VideoOutput { id: previewOutput; width: 320; height: 180 }
    Lunchpail.RetryingMediaPlayer {
        id: preview
        activeAudioTrack: -1; audioOutput: null; videoOutput: previewOutput
        loops: MediaPlayer.Infinite
    }
    Lunchpail.PreviewAudioCompanion {
        id: previewSound
        videoSource: preview.source; videoPosition: preview.position
        previewPlaying: preview.playbackState === MediaPlayer.PlayingState
        unmuted: !test.previewMuted && !!test.audioPane && !test.audioPane.audioSuppressedForVoice
        volume: 0
    }
    function cleanup() {
        previewMuted = true
        audioPane = null
        preview.stop(); preview.source = ""
    }
    Component {
        id: popupComponent
        Controls.Dialog {
            parent: Controls.Overlay.overlay
            modal: true; width: 900; height: 650
            title: "Settings fixture"
        }
    }
    Component {
        id: component
        Lunchpail.DesktopAssistant {
            width: 1000; height: 740
            assistant: QtObject {
                property string config_json: JSON.stringify({captions:true,wake_word:false})
                property string history_json: "[]"
                property string result_json: "{}"
                property string status: "Ready"
                property bool ready: true
                property bool busy: false
                property string question: ""
                function ask(text) { question = text; busy = true }
                function cancel() { busy = false }
                function clear() { history_json = "[]" }
                function refresh() {}
            }
            speech: QtObject {
                property bool busy: false
                property bool ready: true
                property bool listening: false
                property bool hands_free: false
                property bool awake: false
                property bool faulted: false
                property string transcript: ""
                property string status: "Voice ready"
                signal completed(string text)
                signal search_requested(string text)
                function start() { busy = true; listening = true }
                function start_hands_free() { hands_free = true; start() }
                // Match CouchSpeechModel::cancel: close capture before clearing its mode.
                function cancel() { busy = false; listening = false; hands_free = false; awake = false }
                function stop() { listening = false }
                function poll() {}
                function refresh() { ready = true }
            }
            speechOutput: QtObject {
                property bool speaking: false
                function stop() { speaking = false }
            }
            ai: QtObject {
                property bool hands_free: false
                property bool speech_ready: true
                property bool assistant_ready: false
                property bool busy: false
                property string speech_model: "sherpa-zipformer-en"
                property string assistant_model: ""
                property string models_json: "[]"
                property string status: "Ready"
                property real progress: 0
                property int installs: 0
                signal operation_finished(bool success)
                function enable_hands_free(value) { hands_free = value }
                function install_for(assistant) { installs++; busy = true }
                function cancel() { busy = false }
            }
        }
    }
    function pane() { const p = createTemporaryObject(component, test); verify(p); return p }
    SignalSpy { id: settingsRequests; signalName: "settingsRequested" }
    function test_missing_assistant_never_opens_microphone_or_redirects_a_phrase() {
        const p = pane(); p.assistant.ready = false
        settingsRequests.target = p; settingsRequests.clear()
        p.ai.hands_free = true // A preference saved by the old speech-only flow.
        compare(p.handsFreeAllowed, false); compare(p.speech.listening, false)
        compare(p.handsFreeLabel, "Set up mic")
        compare(p.handsFreePauseReason, "Assistant setup needed")
        p.speech.search_requested("open up super mario bros")
        compare(settingsRequests.count, 0); compare(p.assistant.question, "")
        p.toggleHandsFree()
        verify(p.handsFreeInstallDialog.visible); verify(p.handsFreeInstallDialog.assistantModel)
        compare(p.ai.hands_free, false); compare(p.speech.listening, false)
        compare(p.ai.installs, 0)
        p.toggleHandsFree(); verify(!p.handsFreeInstallDialog.visible)
    }
    function test_request_survives_readiness_race_and_waits_for_explicit_send() {
        const p = pane(); p.assistant.ready = false
        p.acceptVoiceRequest("open up super mario bros")
        verify(p.opened); compare(p.speech.listening, false)
        compare(p.searchPanel.preservedRequest, "open up super mario bros")
        p.close(); p.open("")
        compare(findChild(p, "couchSearchField").text, "open up super mario bros")
        p.assistant.ready = true; p.handsFreeSetupController.cancel()
        compare(p.assistant.question, "")
        p.searchPanel.submit()
        compare(p.assistant.question, "open up super mario bros")
        compare(p.searchPanel.preservedRequest, "")
    }
    function test_pause_reasons_distinguish_focus_and_reply_without_blocking_menus() {
        const p = pane(); p.ai.hands_free = true; p.open("")
        p.windowActive = false
        compare(p.handsFreePauseReason, "Lunchpail is not focused")
        verify(p.handsFreeHint.indexOf(p.handsFreePauseReason) >= 0)
        p.windowActive = true; p.inputBlocked = true
        compare(p.handsFreePauseReason, ""); compare(p.speech.listening, true)
        p.inputBlocked = false; p.assistant.busy = true
        compare(p.handsFreePauseReason, "Processing your request")
        p.assistant.busy = false; p.speechOutput.speaking = true
        compare(p.handsFreePauseReason, "Speaking a reply")
    }
    function test_compact_panel_is_conversation_only_and_sends_same_backend() {
        const p = pane(); p.open("find Mario")
        compare(p.opened, true); compare(p.searchPanel.askMode, true)
        compare(p.searchPanel.baseActionCount, 3)
        p.searchPanel.toggleMode(); compare(p.searchPanel.askMode, true)
        p.searchPanel.submit(); compare(p.assistant.question, "find Mario")
        compare(findChild(p, "couchSearchField").text, "")
        p.close(); compare(p.opened, false); compare(p.assistant.busy, true)
    }
    function test_mic_suspends_on_background_or_mode_switch_and_resumes_on_focus() {
        const p = pane(); p.open(""); p.searchPanel.microphone()
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, false)
        p.windowActive = false; compare(p.speech.listening, false)
        p.windowActive = true; compare(p.speech.listening, true); p.active = false
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
    }
    function test_mic_is_opt_in_and_suspends_for_games_and_replies_not_dialogs() {
        const p = pane(); compare(p.handsFreeAllowed, false)
        p.ai.hands_free = true; compare(p.handsFreeAllowed, true)
        compare(p.speech.listening, true)
        p.inputBlocked = true; compare(p.handsFreeAllowed, true); compare(p.speech.listening, true)
        p.inputBlocked = false; p.gameRunning = true; compare(p.speech.listening, false)
        p.gameRunning = false; p.speechOutput.speaking = true
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, true)
        p.speechOutput.speaking = false; compare(p.handsFreeAllowed, false)
        p.coolingDown = false; compare(p.handsFreeAllowed, true)
        p.assistant.busy = true; compare(p.speech.listening, false)
    }
    function test_voice_request_uses_shared_history_and_stops_capture() {
        const p = pane(); p.ai.hands_free = true
        p.speech.search_requested("play the selected game")
        compare(p.assistant.question, "play the selected game")
        compare(p.speech.listening, false); compare(p.assistant.busy, true)
    }
    function test_typing_and_closing_do_not_interrupt_automatic_listening() {
        const p = pane(); p.ai.hands_free = true
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, false)
        p.open(""); keyClick(Qt.Key_M)
        compare(findChild(p, "couchSearchField").text, "m")
        compare(p.speech.listening, true)
        p.close(); compare(p.speech.listening, true)
        p.open(""); p.searchPanel.microphone()
        compare(p.ai.hands_free, false); compare(p.speech.listening, false)
        keyClick(Qt.Key_T); compare(findChild(p, "couchSearchField").text, "t")
    }
    function test_actual_speech_and_replies_duck_preview_audio_not_an_idle_microphone() {
        const p = pane()
        p.open(""); p.searchPanel.microphone()
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, false)
        p.speech.awake = true; compare(p.audioSuppressedForVoice, true)
        p.speech.awake = false; compare(p.audioSuppressedForVoice, false)
        p.searchPanel.microphone()
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
        p.speechOutput.speaking = true; compare(p.audioSuppressedForVoice, true)
        p.speechOutput.speaking = false; compare(p.audioSuppressedForVoice, false)
    }
    function test_wake_word_listener_remains_available_during_preview() {
        const p = pane()
        p.assistant.config_json = JSON.stringify({captions:true,wake_word:true})
        p.ai.hands_free = true
        compare(p.handsFreeAllowed, true); compare(p.speech.listening, true)
        compare(p.audioSuppressedForVoice, false)
        p.speech.awake = true; compare(p.audioSuppressedForVoice, true)
        p.speech.awake = false; compare(p.audioSuppressedForVoice, false)
        // The backend marks actual utterances in either wake-word mode.
        p.assistant.config_json = JSON.stringify({captions:true,wake_word:false})
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, false)
        p.speech.awake = true; compare(p.audioSuppressedForVoice, true)
        p.speech.awake = false; compare(p.audioSuppressedForVoice, false)
    }
    function test_real_video_unmute_with_open_mic_survives_focus_and_repeated_toggles() {
        const p = pane(); audioPane = p
        preview.source = Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
        preview.play()
        tryVerify(function() { return preview.position > 500 && preview.hasAudio }, 5000)
        for (let i = 0; i < 3; ++i) {
            const before = preview.position
            previewMuted = false
            tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
            verify(previewSound.player.hasAudio)
            p.ai.hands_free = true
            compare(previewSound.audioSource, preview.source)
            compare(p.speech.listening, true)
            p.windowActive = false
            compare(previewSound.player.playbackState, MediaPlayer.PlayingState)
            p.windowActive = true
            compare(p.speech.listening, true); compare(previewSound.audioSource, preview.source)
            compare(previewSound.player.playbackState, MediaPlayer.PlayingState)
            p.speech.awake = true
            compare(previewSound.audioSource.toString(), "")
            compare(previewMuted, false, "Voice activity must not change the saved mute preference")
            p.speech.awake = false
            tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
            wait(150); verify(preview.position >= before, "Microphone toggle restarted the video")
            p.ai.hands_free = false
            tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
            previewMuted = true
        }
        previewMuted = false
        tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        preview.pause()
        p.ai.hands_free = true
        compare(p.speech.listening, true)
        compare(previewSound.audioSource.toString(), "")
        compare(preview.playbackState, MediaPlayer.PausedState)
        const pausedPosition = preview.position
        p.speech.awake = true; p.speech.awake = false
        p.windowActive = false; p.windowActive = true
        wait(150)
        compare(preview.position, pausedPosition)
        compare(preview.playbackState, MediaPlayer.PausedState)
        compare(previewMuted, false)
        preview.play()
        tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        compare(p.speech.listening, true)
        preview.source = ""
        compare(p.speech.listening, true)
        compare(p.ai.hands_free, true)
    }
    function test_single_visible_microphone_button_toggles_without_settings() {
        const p = pane(); p.open("")
        const button = p.microphoneButton; verify(button.visible)
        compare(button.text, "Mic off")
        button.clicked(); compare(p.ai.hands_free, true); compare(p.speech.listening, true)
        compare(button.text, "Mic on"); compare(p.ai.installs, 0)
        p.windowActive = false
        compare(button.text, "Mic on"); verify(button.highlighted)
        button.clicked(); compare(p.ai.hands_free, false); compare(p.speech.listening, false)
        compare(button.text, "Mic off")
    }
    function test_missing_model_requires_consent_and_repeat_toggle_cancels_it() {
        const p = pane(); p.ai.speech_ready = false
        p.toggleHandsFree()
        verify(p.handsFreeInstallDialog.visible)
        compare(p.ai.hands_free, false); compare(p.ai.installs, 0)
        p.toggleHandsFree()
        verify(!p.handsFreeInstallDialog.visible)
        compare(p.ai.hands_free, false); compare(p.speech.listening, false)
    }
    function test_cancel_pending_hands_free_install_cannot_enable_mic_later() {
        const p = pane(); p.ai.speech_ready = false
        p.toggleHandsFree(); p.handsFreeInstallDialog.install()
        compare(p.ai.installs, 1)
        p.toggleHandsFree()
        compare(p.ai.busy, false); compare(p.ai.hands_free, false)
        p.ai.speech_ready = true; p.ai.operation_finished(true)
        compare(p.ai.hands_free, false); compare(p.speech.listening, false)
    }
    function test_verified_voice_install_enables_hands_free_after_consent() {
        const p = pane(); p.ai.speech_ready = false; p.speech.faulted = true
        p.toggleHandsFree(); p.handsFreeInstallDialog.install()
        compare(p.ai.hands_free, false)
        p.ai.speech_ready = true; p.ai.busy = false; p.ai.operation_finished(true)
        tryCompare(p.ai, "hands_free", true); compare(p.speech.listening, true)
        compare(p.speech.faulted, false)
    }
    function test_captions_and_transcript_keep_literal_text() {
        const p = pane(); p.open("")
        p.assistant.history_json = JSON.stringify([{role:"user",content:"<b>literal</b>"},{role:"assistant",content:"Selected Mario."}])
        compare(p.searchPanel.conversation.length, 2)
        compare(findChild(p, "conversationTranscript").count, 2)
        p.close(); compare(p.assistant.history_json.indexOf("Selected Mario.") > 0, true)
    }
    function test_conversation_remains_mouse_accessible_above_modal_workflow() {
        const p = pane(); p.parent = test.overlay; p.z = 19000; p.open("")
        const popup = createTemporaryObject(popupComponent, test); verify(popup)
        popup.open(); tryCompare(popup, "opened", true)
        const field = findChild(p, "couchSearchField")
        mouseClick(field, 20, 20); tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_H); compare(field.text, "h")
        popup.close(); p.close()
    }
}
