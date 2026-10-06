pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: search
    required property var speech
    property var assistant: null
    property var speechOutput: null
    property bool askMode: false
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
    signal settingsRequested()
    signal installationRequested(bool assistantModel)
    signal gameChosen(var game)
    readonly property var answer: assistant ? JSON.parse(assistant.result_json || "{}") : ({})
    readonly property var conversation: assistant && assistant.history_json ? JSON.parse(assistant.history_json) : []
    readonly property var resultRows: (answer.games || []).map(g => ({kind: "game", data: g}))
        .concat((answer.patches || []).map(p => ({kind: "patch", data: p})))
    readonly property int baseActionCount: assistant ? 4 : 3
    readonly property int actionCount: baseActionCount + (askMode ? resultRows.length : 0)
    readonly property bool microphoneBusy: acceptingVoice && speech.busy
    readonly property bool inputFocused: field.activeFocus
    onAnswerChanged: Qt.callLater(function() {
        // A new answer starts at its first card, not the previous scroll offset.
        results.positionViewAtBeginning()
    })

    function open(initialText) {
        controllerIndex = 0
        field.text = initialText
        field.cursorPosition = field.length
        field.forceActiveFocus()
    }
    function focusInput() { field.forceActiveFocus() }
    function edit(text) {
        if (!askMode) queryEdited(text)
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
        if (speechOutput) speechOutput.stop()
        if (assistant && assistant.busy) assistant.cancel()
        if (speech.hands_free) speech.cancel()
        if (speech.busy) {
            if (acceptingVoice && speech.listening) speech.stop()
            else { acceptingVoice = false; speech.cancel() }
        } else if (!speech.ready) {
            installationRequested(false)
        } else {
            acceptingVoice = true
            speech.start()
        }
    }
    function clear() {
        cancelVoice()
        if (askMode && assistant) assistant.clear()
        field.text = ""
        edit("")
        field.forceActiveFocus()
    }
    function toggleMode() {
        cancelVoice()
        if (assistant && assistant.busy) assistant.cancel()
        askMode = !askMode
        controllerIndex = 0
        field.text = askMode ? "" : query
        field.forceActiveFocus()
    }
    function submit() {
        if (!askMode) { close(); return }
        if (!assistant || !assistant.ready) { installationRequested(true); return }
        if (assistant.busy) assistant.cancel()
        else { cancelVoice(); if (speechOutput) speechOutput.stop(); assistant.ask(field.text); field.text = "" }
    }
    function chooseRow(index) {
        const row = resultRows[index]
        if (!row) return
        if (row.kind === "game") { close(); gameChosen(row.data) }
        else if (/^https?:\/\//i.test(row.data.source_url || "")) Qt.openUrlExternally(row.data.source_url)
    }
    function activate(index) {
        if (index === 0) microphone()
        else if (index === 1) clear()
        else if (index === 2) submit()
        else if (index === 3 && assistant) toggleMode()
        else chooseRow(index - baseActionCount)
    }
    onControllerIndexChanged: {
        if (controllerIndex >= baseActionCount) {
            results.currentIndex = controllerIndex - baseActionCount
            results.positionViewAtIndex(results.currentIndex, ListView.Contain)
        }
    }
    function handleNavigation(action) {
        if (action === "back") { close(); return true }
        if (action === "details" || action === "menu") { microphone(); return true }
        if (action === "left" || action === "up" || action === "right" || action === "down") {
            controllerIndex = (controllerIndex + (action === "left" || action === "up" ? actionCount - 1 : 1)) % actionCount
            feedbackRequested("move")
            return true
        }
        if (action === "accept") {
            activate(controllerIndex)
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
        ignoreUnknownSignals: true // Also permits simple speech fakes in isolated UI tests.
        function onTranscriptChanged() {
            if (!search.visible || !search.acceptingVoice || !search.speech.transcript.length) return
            field.text = search.speech.transcript
            search.edit(field.text)
        }
        function onCompleted(text) {
            if (!search.visible || !search.acceptingVoice) return
            search.acceptingVoice = false
            if (search.askMode && search.assistant && text.trim().length) { field.text = text; search.submit() }
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
            text: search.askMode ? "TALK TO LUNCHPAIL" : "SEARCH GAMES  ·  " + search.resultCount + " RESULTS"
            color: search.inkColor; font.pixelSize: 20; font.bold: true
        }
        TextField {
            id: field
            objectName: "couchSearchField"
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            font.pixelSize: 28
            color: search.inkColor
            placeholderText: search.askMode ? "Search for Super Mario Bros… or play the game" : "Type or speak a game title"
            placeholderTextColor: search.mutedColor
            selectByMouse: true
            onTextEdited: { search.cancelVoice(); search.edit(text) }
            onAccepted: search.submit()
            Keys.onEscapePressed: event => { search.close(); event.accepted = true }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F2) { search.microphone(); event.accepted = true }
            }
            background: Rectangle { color: "#090f19"; radius: 10; border.color: search.accentColor }
            Accessible.name: search.askMode ? "Ask Lunchpail a game question" : "Search games in Couch Mode"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: [search.speech.hands_free ? "Speak · F2" : search.speech.busy ? (search.acceptingVoice ? (search.speech.listening ? "Stop microphone" : "Cancel transcription") : "Cancel download")
                        : search.speech.ready ? "Speak · F2" : "Download speech model", search.askMode ? "New conversation" : "Clear search",
                        search.askMode ? (!search.assistant || !search.assistant.ready ? "Install & ask" : search.assistant.busy ? "Cancel answer" : "Ask") : "Browse results"]
                        .concat(search.assistant ? [search.askMode ? "Search titles" : "Ask AI"] : [])
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
                        search.activate(index)
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
            text: search.askMode ? "Enter to send · F2 to speak · Esc to browse · Follow up naturally: ‘play that one’" : "Direct title filter · Enter / Esc to browse"
            color: search.mutedColor; font.pixelSize: 13; wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true; visible: search.askMode
            text: search.assistant ? search.assistant.status : ""; textFormat: Text.PlainText
            color: search.accentColor; font.pixelSize: 13; wrapMode: Text.WordWrap
            maximumLineCount: 3; elide: Text.ElideRight
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: search.askMode && !search.conversation.length && (search.answer.message || "").length > 0
            spacing: 8
            Text {
                objectName: "assistantEvidenceSummary"
                Layout.fillWidth: true
                text: search.answer.message || ""; textFormat: Text.PlainText
                color: search.inkColor; font.pixelSize: 15; wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: search.answer.notice || ""; textFormat: Text.PlainText
                color: search.mutedColor; font.pixelSize: 12; wrapMode: Text.WordWrap
            }
        }
        ListView {
            id: transcript
            objectName: "conversationTranscript"
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: search.askMode && search.conversation.length > 0
            clip: true; spacing: 10; model: search.conversation
            property bool followTail: true
            function revealLatest() {
                if (followTail) Qt.callLater(() => {
                    if (transcript.followTail) { transcript.forceLayout(); transcript.positionViewAtEnd() }
                })
            }
            onCountChanged: { followTail = true; revealLatest() }
            onContentHeightChanged: revealLatest()
            onHeightChanged: revealLatest()
            onMovementStarted: followTail = false
            onMovementEnded: followTail = atYEnd
            delegate: Rectangle {
                id: bubble
                required property var modelData
                width: transcript.width
                height: message.implicitHeight + 22
                radius: 10; color: modelData.role === "user" ? "#27384b" : "#162a28"
                Text {
                    id: message; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
                    text: (bubble.modelData.role === "user" ? "You: " : "Lunchpail: ") + bubble.modelData.content
                    textFormat: Text.PlainText; wrapMode: Text.WordWrap; font.pixelSize: 18
                    color: bubble.modelData.role === "user" ? search.accentColor : search.inkColor
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
        ListView {
            id: results
            objectName: "assistantResults"
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: search.askMode && !search.conversation.length
            clip: true; spacing: 10
            model: search.resultRows
            delegate: Button {
                id: resultButton
                required property var modelData
                required property int index
                width: results.width
                height: resultText.implicitHeight + 24
                highlighted: search.controllerIndex === search.baseActionCount + index
                onClicked: search.chooseRow(index)
                contentItem: Text {
                    id: resultText
                    textFormat: Text.PlainText
                    text: resultButton.modelData.kind === "game"
                        ? resultButton.modelData.data.title + " · " + resultButton.modelData.data.platform + "\n"
                          + resultButton.modelData.data.genre + " · " + resultButton.modelData.data.year + " · Rating " + resultButton.modelData.data.rating
                          + (resultButton.modelData.data.local ? " · Installed" : "") + "\nOpen game details"
                        : "Patch candidate: " + resultButton.modelData.data.title + "\n"
                          + resultButton.modelData.data.provider + " · " + (resultButton.modelData.data.language || "Language unknown")
                          + " · " + resultButton.modelData.data.compatibility + "\nOpen provider source"
                    color: resultButton.highlighted ? "#101720" : search.inkColor
                    font.pixelSize: 15; wrapMode: Text.WordWrap
                }
                background: Rectangle { radius: 10; color: resultButton.highlighted ? search.accentColor : "#243345"; border.color: "#667487" }
                Accessible.name: resultText.text
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
