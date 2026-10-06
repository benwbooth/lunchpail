pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A non-modal conversation stays reachable above the workflows the agent opens.
// It does not own the library's keyboard/controller navigation or change mode.
Item {
    id: desktop
    required property var assistant
    required property var speech
    required property var speechOutput
    required property var ai
    property bool active: true
    property bool windowActive: true
    property bool gameRunning: false
    property bool inputBlocked: false
    // This is the user's requested video sound, independent of voice ducking.
    // Deriving it from the actual audio decoder would create a mic/audio loop.
    property bool previewAudioRequested: false
    property bool opened: false
    property bool coolingDown: false
    readonly property var config: JSON.parse(assistant.config_json || "{}")
    readonly property var searchPanel: conversation
    readonly property var handsFreeInstallDialog: handsFreeSetup.installDialog
    readonly property var handsFreeSetupController: handsFreeSetup
    readonly property string handsFreePauseReason: !assistant.ready ? "Assistant setup needed"
        : !speech.ready ? "Speech model setup needed"
        : speech.faulted ? speech.status
        : !active ? "Couch mode is active"
        : !windowActive ? "Lunchpail is not focused"
        : gameRunning ? "A game is running"
        : inputBlocked ? "A dialog or menu is open"
        : assistant.busy ? "Processing your request"
        : speechOutput.speaking ? "Speaking a reply"
        : coolingDown ? "Waiting for reply audio to finish"
        : conversation.microphoneBusy ? "Push-to-talk is active"
        : handsFreePausedForPreview ? "Preview audio is playing"
        : speech.busy && !speech.listening ? "Processing speech" : ""
    readonly property string handsFreeLabel: !ai.hands_free ? "Hands-free · Off"
        : !handsFreeSetup.ready ? "Hands-free · Setup"
        : speech.faulted ? "Hands-free · Error"
        : speech.hands_free && speech.listening ? "Hands-free · On" : "Hands-free · Paused"
    readonly property string handsFreeHint: (handsFreeSetup.pending ? "Cancel hands-free setup"
        : !handsFreeSetup.ready ? "Set up hands-free listening"
        : ai.hands_free ? "Turn hands-free listening off" : "Turn hands-free listening on")
        + " · F4" + (ai.hands_free && handsFreePauseReason ? " · " + handsFreePauseReason : "")
    readonly property bool handsFreePausedForPreview: previewAudioRequested && !config.wake_word
    readonly property bool handsFreeAllowed: active && windowActive && !gameRunning && !inputBlocked
        && ai.hands_free && assistant.ready && !assistant.busy && !speechOutput.speaking && !coolingDown
        && !conversation.microphoneBusy && !handsFreePausedForPreview
    readonly property bool audioSuppressedForVoice: active
        && ((handsFree.capturingCommand && !handsFreePausedForPreview)
            || conversation.microphoneBusy || speechOutput.speaking)
    signal settingsRequested()
    signal gameChosen(var game)
    function open(text) {
        opened = true
        conversation.open(text || "")
    }
    function close() { opened = false; conversation.cancelVoice() }
    function toggle() { if (opened) close(); else open("") }
    function toggleHandsFree() { handsFreeSetup.toggle() }
    function acceptVoiceRequest(text) {
        speech.cancel()
        if (!assistant.ready) {
            conversation.preserveRequest(text)
            opened = true
            handsFreeSetup.request()
        } else assistant.ask(text)
    }
    onActiveChanged: { if (!active) { conversation.cancelVoice(); handsFreeSetup.cancel() } }
    onWindowActiveChanged: { if (!windowActive) conversation.cancelVoice() }
    onGameRunningChanged: { if (gameRunning) conversation.cancelVoice() }
    visible: active
    HandsFreeSetup {
        id: handsFreeSetup
        ai: desktop.ai
        assistant: desktop.assistant
        onStoppedListening: desktop.speech.cancel()
        onSettingsRequested: desktop.settingsRequested()
        onEnabledListening: {
            desktop.speech.refresh()
            desktop.speech.faulted = false
            handsFree.reconcile()
        }
    }
    CouchHandsFreeController {
        id: handsFree
        speech: desktop.speech
        allowed: desktop.handsFreeAllowed
        wakeWordRequired: !!desktop.config.wake_word
        onSearchRequested: text => desktop.acceptVoiceRequest(text)
    }
    Timer { id: cooldown; interval: 900; onTriggered: desktop.coolingDown = false }
    Connections {
        target: desktop.assistant
        function onBusyChanged() {
            if (!desktop.assistant.busy) { desktop.coolingDown = true; cooldown.restart() }
        }
    }
    Connections {
        target: desktop.speechOutput
        function onSpeakingChanged() {
            desktop.coolingDown = true
            if (desktop.speechOutput.speaking) cooldown.stop()
            else cooldown.restart()
        }
    }
    Item {
        id: panel
        objectName: "desktopConversationPanel"
        anchors { left: parent.left; bottom: parent.bottom; margins: 18 }
        width: Math.min(500, parent.width - 36)
        height: Math.min(620, parent.height - 36)
        visible: desktop.opened
        Rectangle { anchors.fill: parent; color: "#172230"; radius: 16; border.color: "#eec270" }
        RowLayout {
            id: toolbar
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: desktop.speech.listening ? "● Mic on" : "NORMAL MODE"
                color: desktop.speech.listening ? "#72e1a0" : "#acb6c6"
                font.pixelSize: 12; font.bold: true
            }
            LbButton {
                objectName: "desktopHandsFreeToggle"
                text: desktop.handsFreeLabel
                highlighted: desktop.ai.hands_free
                onClicked: desktop.toggleHandsFree()
                ToolTip.visible: hovered
                ToolTip.text: desktop.handsFreeHint
                Accessible.name: desktop.handsFreeHint
            }
            LbButton { text: "AI & voice"; onClicked: desktop.settingsRequested() }
            LbButton { text: "Close"; Accessible.name: "Close assistant"; onClicked: desktop.close() }
        }
        Text {
            id: microphoneStatus
            objectName: "desktopHandsFreeStatus"
            anchors { top: toolbar.bottom; left: parent.left; right: parent.right; margins: 12; topMargin: 6 }
            visible: desktop.ai.hands_free && desktop.handsFreePauseReason.length > 0
            text: "Mic paused · " + desktop.handsFreePauseReason
            color: "#acb6c6"; font.pixelSize: 12; wrapMode: Text.WordWrap
        }
        CouchSearchOverlay {
            id: conversation
            anchors { top: microphoneStatus.visible ? microphoneStatus.bottom : toolbar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 6 }
            visible: desktop.active && desktop.opened
            compact: true; conversationOnly: true; askMode: true
            speech: desktop.speech; assistant: desktop.assistant; speechOutput: desktop.speechOutput
            onCloseRequested: desktop.close()
            onInstallationRequested: desktop.settingsRequested()
            onSettingsRequested: desktop.settingsRequested()
            onGameChosen: game => desktop.gameChosen(game)
        }
    }
    ConversationCaptions {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
        width: Math.min(720, parent.width - 40)
        assistant: desktop.assistant; speech: desktop.speech; speechOutput: desktop.speechOutput
        enabledCaptions: desktop.active && !desktop.gameRunning && desktop.config.captions !== false
        expanded: desktop.opened
        onConversationRequested: desktop.open("")
    }
}
