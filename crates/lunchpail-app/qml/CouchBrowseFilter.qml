pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// A non-modal filter: browsing stays visible and never invokes the assistant.
FocusScope {
    id: filter
    property string query: ""
    property string scopeLabel: "games"
    property int resultCount: 0
    property int maximumLength: 200
    property bool editing: false
    property color panelColor: "#172230"
    property color inkColor: "#f2f5fa"
    property color mutedColor: "#acb6c6"
    property color accentColor: "#eec270"
    readonly property bool inputFocused: field.activeFocus
    signal queryEdited(string text)
    signal finished()
    signal navigationRequested(string action)
    implicitHeight: 76
    onQueryChanged: if (field.text !== query) field.text = query
    onVisibleChanged: if (!visible && editing) finish()

    function open(text) {
        editing = true
        field.text = text
        field.cursorPosition = field.length
        field.forceActiveFocus()
        if (field.text !== query) queryEdited(field.text)
    }
    function finish() {
        editing = false
        finished()
    }
    function browse(action) {
        finish()
        navigationRequested(action)
    }
    Rectangle {
        anchors.fill: parent
        color: filter.panelColor; radius: 14
        border.color: filter.inputFocused ? filter.accentColor : filter.mutedColor
        border.width: filter.inputFocused ? 2 : 1
    }
    TextField {
        id: field
        objectName: "couchBrowseFilterField"
        anchors { left: parent.left; right: clearButton.left; top: parent.top; margins: 10 }
        height: 34
        text: filter.query
        maximumLength: filter.maximumLength
        font.pixelSize: 22
        color: filter.inkColor
        placeholderText: "Filter " + filter.scopeLabel
        placeholderTextColor: filter.mutedColor
        selectByMouse: true
        background: Item {}
        Accessible.name: "Filter " + filter.scopeLabel
        onActiveFocusChanged: filter.editing = activeFocus
        onTextEdited: filter.queryEdited(text)
        onAccepted: filter.finish()
        Keys.onEscapePressed: event => { filter.finish(); event.accepted = true }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true
                filter.finish()
                return
            }
            let action = ""
            if (event.key === Qt.Key_Up) action = "up"
            else if (event.key === Qt.Key_Down) action = "down"
            else if (event.key === Qt.Key_PageUp) action = "page_left"
            else if (event.key === Qt.Key_PageDown) action = "page_right"
            if (action) { event.accepted = true; filter.browse(action) }
        }
    }
    CouchActionButton {
        id: clearButton
        objectName: "couchBrowseFilterClear"
        anchors { right: parent.right; top: parent.top; margins: 10 }
        width: 42; height: 34
        text: "×"
        inkColor: filter.inkColor; panelColor: filter.panelColor; accentColor: filter.accentColor
        Accessible.name: "Clear " + filter.scopeLabel + " filter"
        onClicked: filter.open("")
    }
    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
        text: filter.resultCount + " " + filter.scopeLabel + " · Enter / Esc to browse · Space from the list to ask the assistant"
        color: filter.mutedColor; font.pixelSize: 12
    }
}
