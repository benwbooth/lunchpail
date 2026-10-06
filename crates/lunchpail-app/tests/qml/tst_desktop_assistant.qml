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
                function cancel() { busy = false; hands_free = false; listening = false }
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
    function test_compact_panel_is_conversation_only_and_sends_same_backend() {
        const p = pane(); p.open("find Mario")
        compare(p.opened, true); compare(p.searchPanel.askMode, true)
        compare(p.searchPanel.baseActionCount, 3)
        p.searchPanel.toggleMode(); compare(p.searchPanel.askMode, true)
        p.searchPanel.submit(); compare(p.assistant.question, "find Mario")
        compare(findChild(p, "couchSearchField").text, "")
        p.close(); compare(p.opened, false); compare(p.assistant.busy, true)
    }
    function test_push_to_talk_cancels_on_background_or_mode_switch() {
        const p = pane(); p.open(""); p.searchPanel.microphone()
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, true)
        p.windowActive = false; compare(p.speech.listening, false)
        p.windowActive = true; p.searchPanel.microphone(); p.active = false
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
    }
    function test_hands_free_is_opt_in_and_pauses_for_games_dialogs_and_replies() {
        const p = pane(); compare(p.handsFreeAllowed, false)
        p.ai.hands_free = true; compare(p.handsFreeAllowed, true)
        compare(p.speech.listening, true)
        p.inputBlocked = true; compare(p.handsFreeAllowed, false); compare(p.speech.listening, false)
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
    function test_preview_unmute_pauses_open_mic_without_changing_preference() {
        const p = pane(); p.ai.hands_free = true
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, true)
        p.previewAudioRequested = true
        compare(p.handsFreeAllowed, false); compare(p.speech.listening, false)
        compare(p.audioSuppressedForVoice, false); compare(p.ai.hands_free, true)
        // Focus changes used to make the supposedly unmuted video intermittent.
        p.windowActive = false; p.windowActive = true
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
        p.previewAudioRequested = false
        compare(p.handsFreeAllowed, true); compare(p.speech.listening, true)
        compare(p.audioSuppressedForVoice, true); compare(p.ai.hands_free, true)
    }
    function test_push_to_talk_and_replies_still_duck_an_audible_preview() {
        const p = pane(); p.ai.hands_free = true; p.previewAudioRequested = true
        p.open(""); p.searchPanel.microphone()
        compare(p.speech.listening, true); compare(p.audioSuppressedForVoice, true)
        p.searchPanel.cancelVoice()
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
        p.speechOutput.speaking = true; compare(p.audioSuppressedForVoice, true)
        p.speechOutput.speaking = false; compare(p.audioSuppressedForVoice, false)
    }
    function test_wake_word_listener_remains_available_during_preview() {
        const p = pane()
        p.assistant.config_json = JSON.stringify({captions:true,wake_word:true})
        p.ai.hands_free = true; p.previewAudioRequested = true
        compare(p.handsFreeAllowed, true); compare(p.speech.listening, true)
        compare(p.audioSuppressedForVoice, false)
        p.speech.awake = true; compare(p.audioSuppressedForVoice, true)
        p.speech.awake = false; compare(p.audioSuppressedForVoice, false)
        // Changing to open conversation while audio plays must stop capture.
        p.assistant.config_json = JSON.stringify({captions:true,wake_word:false})
        compare(p.speech.listening, false); compare(p.audioSuppressedForVoice, false)
    }
    function test_real_video_unmute_with_open_mic_survives_focus_and_repeated_toggles() {
        const p = pane(); audioPane = p
        p.previewAudioRequested = Qt.binding(function() {
            return !test.previewMuted && preview.hasAudio
                && preview.playbackState === MediaPlayer.PlayingState
        })
        p.ai.hands_free = true
        preview.source = Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
        preview.play()
        tryVerify(function() { return preview.position > 500 && preview.hasAudio }, 5000)
        for (let i = 0; i < 3; ++i) {
            const before = preview.position
            previewMuted = false
            tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
            verify(previewSound.player.hasAudio)
            compare(p.speech.listening, false)
            p.windowActive = false; p.windowActive = true
            wait(150)
            compare(previewSound.player.playbackState, MediaPlayer.PlayingState)
            verify(preview.position >= before, "Unmute restarted the video")
            previewMuted = true
            compare(previewSound.audioSource.toString(), "")
            compare(p.speech.listening, true)
        }
        previewMuted = false
        tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        preview.pause()
        compare(p.speech.listening, true)
        compare(previewSound.audioSource.toString(), "")
        preview.play()
        tryCompare(previewSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        compare(p.speech.listening, false)
        preview.source = ""
        compare(p.speech.listening, true)
        compare(p.ai.hands_free, true)
    }
    function test_visible_hands_free_button_toggles_both_directions_without_settings() {
        const p = pane(); p.open("")
        const button = findChild(p, "desktopHandsFreeToggle"); verify(button.visible)
        compare(button.text, "Hands-free · Off")
        button.clicked(); compare(p.ai.hands_free, true); compare(p.speech.listening, true)
        compare(button.text, "Hands-free · On"); compare(p.ai.installs, 0)
        p.previewAudioRequested = true
        compare(button.text, "Hands-free · Paused"); verify(button.highlighted)
        button.clicked(); compare(p.ai.hands_free, false); compare(p.speech.listening, false)
        compare(button.text, "Hands-free · Off"); verify(!button.highlighted)
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
        compare(p.speech.faulted, false)
        compare(p.ai.hands_free, true); compare(p.speech.listening, true)
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
