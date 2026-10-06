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
    property bool opened: false
    property bool coolingDown: false
    readonly property var config: JSON.parse(assistant.config_json || "{}")
    readonly property var searchPanel: conversation
    readonly property bool handsFreeAllowed: active && windowActive && !gameRunning && !inputBlocked
        && ai.hands_free && !assistant.busy && !speechOutput.speaking && !coolingDown
        && !conversation.microphoneBusy
    readonly property bool audioSuppressedForVoice: active
        && (handsFree.capturingCommand || conversation.microphoneBusy || speechOutput.speaking)
    signal settingsRequested()
    signal gameChosen(var game)
    function open(text) {
        opened = true
        conversation.open(text || "")
    }
    function close() { opened = false; conversation.cancelVoice() }
    function toggle() { if (opened) close(); else open("") }
    onActiveChanged: { if (!active) conversation.cancelVoice() }
    onWindowActiveChanged: { if (!windowActive) conversation.cancelVoice() }
    onGameRunningChanged: { if (gameRunning) conversation.cancelVoice() }
    visible: active
    CouchHandsFreeController {
        id: handsFree
        speech: desktop.speech
        allowed: desktop.handsFreeAllowed
        wakeWordRequired: !!desktop.config.wake_word
        onSearchRequested: text => {
            desktop.speech.cancel()
            if (!desktop.assistant.ready) desktop.settingsRequested()
            else desktop.assistant.ask(text)
        }
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
                objectName: "desktopHandsFreeOff"
                visible: desktop.ai.hands_free
                text: "Turn mic off"
                onClicked: { desktop.ai.enable_hands_free(false); desktop.speech.cancel() }
            }
            LbButton { text: "AI & voice"; onClicked: desktop.settingsRequested() }
            LbButton { text: "Close"; Accessible.name: "Close assistant"; onClicked: desktop.close() }
        }
        CouchSearchOverlay {
            id: conversation
            anchors { top: toolbar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 6 }
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
