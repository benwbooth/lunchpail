import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchEntrySelection"
    when: windowShown
    Component {
        id: component
        Lunchpail.CouchEntrySelection {
            library: QtObject {
                property bool ready: true
                property bool filtering: false
                property string current_platform: "NES"
                property int row: 42
                function row_for_game(id) { return row }
            }
            browser: QtObject {
                property int currentIndex: 0
                property var currentItem: ({gameId: "mario"})
                property int positioned: -1
                function positionViewAtIndex(row, mode) { positioned = row }
            }
        }
    }
    SignalSpy { id: settled; signalName: "settled" }
    function entry() {
        const item = createTemporaryObject(component, test)
        verify(item); settled.target = item; settled.clear()
        return item
    }
    function test_waits_for_platform_filter_and_matching_delegate() {
        const item = entry(); item.begin("faxanadu", "NES"); item.active = true
        item.library.filtering = true
        verify(!item.reconcile()); compare(item.browser.currentIndex, 0)
        item.library.current_platform = "SNES"; item.library.filtering = false
        verify(!item.reconcile()); compare(item.browser.currentIndex, 0)
        item.library.current_platform = "NES"
        verify(!item.reconcile()); compare(item.browser.currentIndex, 42)
        verify(item.pending); compare(settled.count, 0)
        item.browser.currentItem = {gameId: "faxanadu", index: 0}
        verify(!item.reconcile()); verify(item.pending)
        item.browser.currentItem = {gameId: "faxanadu", index: 42}
        verify(item.reconcile()); verify(!item.pending); compare(settled.count, 1)
        compare(settled.signalArguments[0][0], "faxanadu")
    }
    function test_hidden_game_is_not_replaced_with_the_first_row() {
        const item = entry(); item.begin("faxanadu", "NES"); item.active = true
        item.library.row = -1; verify(!item.reconcile())
        verify(item.pending); verify(item.unavailable)
        compare(item.gameId, "faxanadu"); compare(settled.count, 0)
        compare(item.browser.currentIndex, 0)
    }
    function test_latest_entry_wins_and_exit_cancels() {
        const item = entry(); item.begin("mario", "NES"); item.begin("faxanadu", "NES")
        item.active = true; item.browser.currentItem = {gameId: "mario"}
        verify(!item.reconcile()); compare(settled.count, 0)
        item.cancel(); verify(!item.pending); verify(!item.reconcile())
    }
}
