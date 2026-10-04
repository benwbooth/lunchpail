pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: search
    required property var speech
    property string query: ""
    property int resultCount: 0
    property color panelColor: "#172230"
    property color inkColor: "#f2f5fa"
    property color mutedColor: "#acb6c6"
    property color accentColor: "#eec270"
    property int controllerIndex: 0
    property bool acceptingVoice: false
    signal queryEdited(string text)
    signal closeRequested()
    signal feedbackRequested(string kind)
    readonly property bool microphoneBusy: acceptingVoice && speech.busy

    function open(initialText) {
        controllerIndex = 0
        field.text = initialText
        field.cursorPosition = field.length
        field.forceActiveFocus()
    }
    function focusInput() { field.forceActiveFocus() }
    function edit(text) {
        queryEdited(text)
    }
    function cancelVoice() {
        acceptingVoice = false
        if (speech.busy) speech.cancel()
    }
    function close() {
        cancelVoice()
        feedbackRequested("back")
        closeRequested()
    }
    function microphone() {
        if (speech.busy) {
            if (acceptingVoice) speech.stop()
            else speech.cancel()
        } else if (!speech.ready) {
            // Explicit enable action downloads only the model, never opens the mic.
            speech.prepare()
        } else {
            acceptingVoice = true
            speech.start()
        }
    }
    function clear() {
        cancelVoice()
        field.text = ""
        edit("")
        field.forceActiveFocus()
    }
    function handleNavigation(action) {
        if (action === "back") { close(); return true }
        if (action === "details" || action === "menu") { microphone(); return true }
        if (action === "left" || action === "up" || action === "right" || action === "down") {
            controllerIndex = (controllerIndex + (action === "left" || action === "up" ? 2 : 1)) % 3
            feedbackRequested("move")
            return true
        }
        if (action === "accept") {
            if (controllerIndex === 0) microphone()
            else if (controllerIndex === 1) clear()
            else close()
            return true
        }
        return true // Search owns controller input; never launch a hidden game.
    }
    onVisibleChanged: if (!visible) cancelVoice()
    Keys.onEscapePressed: event => { close(); event.accepted = true }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F2) {
            microphone()
            event.accepted = true
        } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
            cancelVoice()
            field.forceActiveFocus()
            field.insert(field.cursorPosition, event.text)
            edit(field.text)
            event.accepted = true
        }
    }
    Connections {
        target: search.speech
        function onTranscriptChanged() {
            if (!search.visible || !search.acceptingVoice || !search.speech.transcript.length) return
            field.text = search.speech.transcript
            search.edit(field.text)
        }
    }
    Timer { interval: 50; repeat: true; running: search.speech.busy; onTriggered: search.speech.poll() }
    Rectangle {
        anchors.fill: parent
        color: search.panelColor
        radius: 22
        border.width: 2
        border.color: search.accentColor
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 26
        spacing: 14
        Text {
            text: "SEARCH GAMES  ·  " + search.resultCount + " RESULTS"
            color: search.inkColor; font.pixelSize: 20; font.bold: true
        }
        TextField {
            id: field
            objectName: "couchSearchField"
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            font.pixelSize: 28
            color: search.inkColor
            placeholderText: "Type or speak a game title"
            placeholderTextColor: search.mutedColor
            selectByMouse: true
            onTextEdited: { search.cancelVoice(); search.edit(text) }
            onAccepted: search.close()
            Keys.onEscapePressed: event => { search.close(); event.accepted = true }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F2) { search.microphone(); event.accepted = true }
            }
            background: Rectangle { color: "#090f19"; radius: 10; border.color: search.accentColor }
            Accessible.name: "Search games in Couch Mode"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: [search.speech.busy ? (search.acceptingVoice ? "Stop microphone" : "Cancel download")
                        : search.speech.ready ? "Speak · F2" : "Enable voice · 191 MB", "Clear search", "Browse results"]
                delegate: Button {
                    id: action
                    required property int index
                    required property string modelData
                    objectName: "couchSearchAction" + index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    text: modelData
                    font.pixelSize: 18
                    highlighted: search.controllerIndex === index
                    background: Rectangle {
                        radius: 10
                        color: action.highlighted ? search.accentColor : "#243345"
                        border.color: action.highlighted ? search.accentColor : "#667487"
                        border.width: action.activeFocus ? 3 : 1
                    }
                    contentItem: Text {
                        text: action.text
                        color: action.highlighted ? "#101720" : search.inkColor
                        font.pixelSize: 18
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onClicked: {
                        search.controllerIndex = index
                        if (index === 0) search.microphone()
                        else if (index === 1) search.clear()
                        else search.close()
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: (search.speech.listening ? "● " : "") + search.speech.status
            color: search.speech.listening ? "#72e1a0" : search.mutedColor
            font.pixelSize: 15
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text: "Local English recognition · Audio is never saved or uploaded · Enter / Esc to browse"
            color: search.mutedColor; font.pixelSize: 13; wrapMode: Text.WordWrap
        }
    }
}
