import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchSearch"
    when: windowShown
    visible: true
    width: 1000; height: 400
    Component {
        id: searchComponent
        Lunchpail.CouchSearchOverlay {
            width: 960; height: 335
            speech: QtObject {
                property bool ready: false
                property bool busy: false
                property bool listening: false
                property string status: "Local test speech source"
                property string transcript: ""
                property int starts: 0
                property int preparations: 0
                property int cancellations: 0
                property int stops: 0
                signal completed(string text)
                function prepare() { preparations++; busy = true }
                function start() { starts++; busy = true; listening = true }
                function stop() { stops++; busy = false; listening = false }
                function cancel() { cancellations++; busy = false; listening = false }
                function poll() {}
            }
        }
    }
    SignalSpy { id: edits; signalName: "queryEdited" }
    SignalSpy { id: closes; signalName: "closeRequested" }
    function panel() {
        const search = createTemporaryObject(searchComponent, test)
        verify(search)
        edits.target = search; edits.clear()
        closes.target = search; closes.clear()
        search.open("")
        return search
    }
    function test_enable_downloads_without_opening_microphone() {
        const search = panel()
        search.microphone()
        compare(search.speech.preparations, 1)
        compare(search.speech.starts, 0)
        compare(search.microphoneBusy, false)
        search.speech.ready = true; search.speech.busy = false
        search.microphone()
        compare(search.speech.starts, 1)
        compare(search.microphoneBusy, true)
    }
    function test_type_updates_search_without_shortcuts() {
        const search = panel()
        const field = findChild(search, "couchSearchField")
        keyClick(Qt.Key_M); keyClick(Qt.Key_A); keyClick(Qt.Key_R); keyClick(Qt.Key_I); keyClick(Qt.Key_O)
        compare(field.text, "mario")
        compare(edits.count, 5)
        compare(edits.signalArguments[4][0], "mario")
        compare(search.speech.starts, 0)
        keyClick(Qt.Key_Return)
        compare(closes.count, 1)
    }
    function test_streaming_text_and_typing_cancels_late_results() {
        const search = panel()
        search.speech.ready = true
        search.microphone()
        search.speech.transcript = "sonic"
        compare(edits.signalArguments[0][0], "sonic")
        const field = findChild(search, "couchSearchField")
        field.cursorPosition = field.length
        keyClick(Qt.Key_Space); keyClick(Qt.Key_2)
        compare(field.text, "sonic 2")
        compare(search.speech.cancellations, 1)
        search.speech.transcript = "stale"
        compare(field.text, "sonic 2")
        search.clear()
        compare(field.text, "")
        compare(edits.signalArguments[edits.count - 1][0], "")
    }
    function test_back_cancels_capture_and_controller_never_launches() {
        const search = panel()
        search.speech.ready = true
        search.handleNavigation("accept")
        compare(search.speech.starts, 1)
        verify(search.handleNavigation("favorite"))
        search.handleNavigation("back")
        compare(search.speech.cancellations, 1)
        compare(closes.count, 1)
        search.speech.transcript = "late result"
        compare(edits.count, 0)
    }
    function test_hiding_stops_microphone() {
        const search = panel()
        search.speech.ready = true
        search.microphone()
        search.visible = false
        compare(search.speech.cancellations, 1)
        verify(!search.microphoneBusy)
    }
    function test_escape_and_typing_after_button_focus() {
        const search = panel()
        const button = findChild(search, "couchSearchAction1")
        verify(button)
        button.forceActiveFocus()
        keyClick(Qt.Key_S)
        compare(findChild(search, "couchSearchField").text, "s")
        button.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(closes.count, 1)
    }
}
