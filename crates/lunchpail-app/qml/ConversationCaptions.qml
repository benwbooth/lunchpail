pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: captions
    required property var assistant
    required property var speech
    required property var speechOutput
    property bool enabledCaptions: true
    property bool expanded: false
    property bool recent: false
    property color inkColor: "#f2f5fa"
    property color accentColor: "#eec270"
    readonly property var history: JSON.parse(assistant.history_json || "[]")
    readonly property string playerText: speech.listening && speech.transcript ? speech.transcript
        : history.filter(m => m.role === "user").slice(-1).map(m => m.content).join("")
    readonly property string assistantText: assistant.busy ? assistant.status
        : history.filter(m => m.role === "assistant").slice(-1).map(m => m.content).join("")
    signal conversationRequested()
    visible: enabledCaptions && !expanded && (recent || assistant.busy || speechOutput.speaking || speech.awake)
    implicitHeight: captionContent.implicitHeight + 24
    color: "#ed101924"; radius: 14; border.color: "#5c738a"
    function showRecent() { recent = true; expiry.restart() }
    Connections {
        target: captions.assistant
        function onHistory_jsonChanged() { captions.showRecent() }
    }
    Connections {
        target: captions.speech
        function onTranscriptChanged() { if (captions.speech.transcript) captions.showRecent() }
    }
    Timer { id: expiry; interval: 16000; onTriggered: captions.recent = false }
    ColumnLayout {
        id: captionContent
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 5
        Text { Layout.fillWidth: true; text: "You: " + captions.playerText; visible: !!captions.playerText; color: captions.accentColor; textFormat: Text.PlainText; wrapMode: Text.WordWrap; font.pixelSize: 19; maximumLineCount: 2; elide: Text.ElideRight }
        Text { Layout.fillWidth: true; text: "Lunchpail: " + captions.assistantText; visible: !!captions.assistantText; color: captions.inkColor; textFormat: Text.PlainText; wrapMode: Text.WordWrap; font.pixelSize: 19; maximumLineCount: 4; elide: Text.ElideRight }
        RowLayout {
            Button { text: "Conversation"; onClicked: captions.conversationRequested() }
            Button { text: captions.assistant.busy ? "Stop reply" : "Stop voice"; visible: captions.assistant.busy || captions.speechOutput.speaking; onClicked: { captions.speechOutput.stop(); if (captions.assistant.busy) captions.assistant.cancel() } }
        }
    }
}
