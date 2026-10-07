import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchBrowseFilter"
    when: windowShown
    visible: true
    width: 900; height: 300
    property int leakedAccepts: 0
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) leakedAccepts++
    }
    Component {
        id: component
        Lunchpail.CouchBrowseFilter {
            width: 800; height: implicitHeight
            onQueryEdited: text => query = text
            onFinished: test.forceActiveFocus()
        }
    }
    SignalSpy { id: edits; signalName: "queryEdited" }
    SignalSpy { id: done; signalName: "finished" }
    SignalSpy { id: navigation; signalName: "navigationRequested" }
    function panel() {
        const item = createTemporaryObject(component, test)
        verify(item)
        edits.target = item; edits.clear()
        done.target = item; done.clear()
        navigation.target = item; navigation.clear()
        leakedAccepts = 0
        return item
    }
    function test_first_character_and_multiword_query_filter_live() {
        const item = panel()
        item.open("s")
        verify(item.inputFocused)
        compare(item.query, "s")
        keyClick(Qt.Key_U); keyClick(Qt.Key_P); keyClick(Qt.Key_E); keyClick(Qt.Key_R)
        keyClick(Qt.Key_Space); keyClick(Qt.Key_M)
        compare(item.query, "super m")
        compare(edits.count, 7)
        keyClick(Qt.Key_Backspace)
        compare(item.query, "super ")
        compare(done.count, 0)
    }
    function test_enter_and_escape_keep_filter_without_activating_result() {
        const item = panel()
        item.open("mario")
        keyClick(Qt.Key_Return)
        compare(item.query, "mario")
        compare(done.count, 1)
        verify(!item.editing); verify(!item.inputFocused)
        compare(navigation.count, 0)
        compare(leakedAccepts, 0, "Finishing a filter must consume Return before its browser sees it")
        item.open(item.query)
        keyClick(Qt.Key_Enter)
        compare(done.count, 2)
        compare(leakedAccepts, 0)
        item.open(item.query)
        keyClick(Qt.Key_Escape)
        compare(item.query, "mario")
        compare(done.count, 3)
        verify(!item.inputFocused)
    }
    function test_arrows_return_to_filtered_browser() {
        const item = panel()
        item.open("nes")
        keyClick(Qt.Key_Down)
        compare(navigation.count, 1)
        compare(navigation.signalArguments[0][0], "down")
        compare(item.query, "nes")
        verify(!item.inputFocused)
    }
    function test_platform_limit_clear_and_external_scope_changes() {
        const item = panel()
        item.scopeLabel = "platforms"; item.maximumLength = 80
        item.open("a".repeat(100))
        compare(item.query.length, 80)
        item.query = "snes"
        compare(findChild(item, "couchBrowseFilterField").text, "snes")
        mouseClick(findChild(item, "couchBrowseFilterClear"))
        compare(item.query, "")
        verify(item.inputFocused)
        item.query = "game filter"
        compare(findChild(item, "couchBrowseFilterField").text, "game filter")
    }
    function test_cursor_editing_and_unicode_are_not_assistant_shortcuts() {
        const item = panel()
        item.open("étoile 2")
        keyClick(Qt.Key_Left); keyClick(Qt.Key_Backspace)
        compare(item.query, "étoile2")
        keyClick(Qt.Key_Space)
        compare(item.query, "étoile 2")
        compare(done.count, 0)
    }
}
