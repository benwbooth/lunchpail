import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "RandomGameButton"
    when: windowShown
    visible: true
    width: 320; height: 160
    QtObject {
        id: library
        property bool ready: true
        property bool loading: false
        property bool filtering: false
        property var results: ["nes-mario", "nes-mario-2", "nes-mario-3"]
        readonly property int filtered_count: results.length
        function row_for_game(id) { return results.indexOf(id) }
        function game_id_for_row(row) { return results[row] || "" }
    }
    Component {
        id: buttonComponent
        Lunchpail.RandomGameButton { x: 20; y: 20; libraryModel: library }
    }
    SignalSpy { id: picks; signalName: "gameChosen" }
    function init() {
        library.ready = true; library.loading = false; library.filtering = false
        library.results = ["nes-mario", "nes-mario-2", "nes-mario-3"]
        picks.clear()
    }
    function cleanup() { picks.target = null }

    function test_click_and_keyboard_select_without_changing_results() {
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0.99 }})
        picks.target = button
        mouseClick(button)
        compare(picks.count, 1)
        compare(picks.signalArguments[0][0], "nes-mario-3")
        compare(library.results.join(","), "nes-mario,nes-mario-2,nes-mario-3")
        button.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        compare(picks.count, 2)
        compare(findChild(button, "randomGameDiceIcon").name, "dice")
        compare(button.Accessible.name, "Select random game")
    }
    function test_every_other_result_is_reachable_without_repeating_current() {
        const button = createTemporaryObject(buttonComponent, test)
        for (let current = 0; current < library.results.length; ++current) {
            button.selectedGameId = library.results[current]
            const expected = library.results.filter(function(id) { return id !== button.selectedGameId })
            for (let slot = 0; slot < expected.length; ++slot) {
                button.randomSource = function() { return (slot + 0.5) / expected.length }
                compare(button.chooseGame(), expected[slot])
            }
        }
    }
    function test_compact_button_keeps_dice_centered_and_accessible() {
        const button = createTemporaryObject(buttonComponent, test, {compact: true})
        compare(button.width, 41)
        compare(button.Accessible.name, "Select random game")
        const icon = findChild(button, "randomGameDiceIcon")
        verify(waitForRendering(button))
        const center = icon.mapToItem(button, icon.width / 2, icon.height / 2)
        fuzzyCompare(center.x, button.width / 2, 0.1)
        // The odd-sized vector is vertically snapped to a physical pixel.
        fuzzyCompare(center.y, button.height / 2, 0.6)
    }
    function test_selection_outside_results_allows_first_and_last() {
        const button = createTemporaryObject(buttonComponent, test, {selectedGameId: "snes-mario"})
        button.randomSource = function() { return 0 }
        compare(button.chooseGame(), "nes-mario")
        button.randomSource = function() { return 0.999999 }
        compare(button.chooseGame(), "nes-mario-3")
    }
    function test_full_result_set_not_only_visible_cards() {
        const rows = []
        for (let i = 0; i < 10000; ++i) rows.push("filtered-game-" + i)
        library.results = rows
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0.999999 }})
        compare(button.chooseGame(), "filtered-game-9999")
    }
    function test_new_filters_and_single_result() {
        const button = createTemporaryObject(buttonComponent, test, {selectedGameId: "nes-mario"})
        library.filtering = true
        verify(!button.enabled)
        library.results = ["snes-metroid"]
        library.filtering = false
        compare(button.chooseGame(), "snes-metroid")
        button.selectedGameId = "snes-metroid"
        compare(button.chooseGame(), "snes-metroid")
    }
    function test_empty_loading_and_pending_filters_do_not_pick() {
        const button = createTemporaryObject(buttonComponent, test)
        picks.target = button
        for (const property of ["ready", "loading", "filtering"]) {
            library[property] = property !== "ready"
            verify(!button.enabled)
            compare(button.chooseGame(), "")
            mouseClick(button)
            compare(picks.count, 0)
            library[property] = property === "ready"
        }
        button.filterPending = true
        verify(!button.enabled)
        compare(button.chooseGame(), "")
        button.filterPending = false
        library.results = []
        verify(!button.enabled)
        compare(button.chooseGame(), "")
        compare(picks.count, 0)
    }
}
