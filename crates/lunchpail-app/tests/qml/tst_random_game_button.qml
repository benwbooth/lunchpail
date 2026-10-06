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
        signal modelReset()
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
    function test_every_other_result_is_selected_before_initial_game_repeats() {
        const button = createTemporaryObject(buttonComponent, test)
        for (let current = 0; current < library.results.length; ++current) {
            button.resetShuffle()
            button.selectedGameId = library.results[current]
            const expected = library.results.filter(function(id) { return id !== button.selectedGameId })
            const chosen = []
            for (let slot = 0; slot < expected.length; ++slot) {
                button.randomSource = function() { return (slot + 0.5) / expected.length }
                const id = button.chooseGame()
                verify(expected.indexOf(id) >= 0)
                verify(chosen.indexOf(id) < 0)
                chosen.push(id)
                button.selectedGameId = id
            }
            compare(button.shuffleRemaining, 0)
        }
    }
    function test_complete_cycles_are_unique_and_do_not_repeat_at_boundary_data() {
        return [{tag: "first-slot", draw: 0}, {tag: "middle-slot", draw: 0.5}, {tag: "last-slot", draw: 0.999999}]
    }
    function test_complete_cycles_are_unique_and_do_not_repeat_at_boundary(data) {
        library.results = ["a", "b", "c", "d", "e"]
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return data.draw }})
        let last = ""
        for (let cycle = 0; cycle < 5; ++cycle) {
            const chosen = []
            for (let i = 0; i < library.filtered_count; ++i) {
                const id = button.chooseGame()
                verify(chosen.indexOf(id) < 0)
                verify(id !== last)
                chosen.push(id)
                last = id
                button.selectedGameId = id
            }
            compare(chosen.slice().sort().join(","), library.results.slice().sort().join(","))
            compare(button.shuffleRemaining, 0)
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
        button.resetShuffle()
        button.randomSource = function() { return 0.999999 }
        compare(button.chooseGame(), "nes-mario-3")
    }
    function test_full_result_set_not_only_visible_cards() {
        const rows = []
        for (let i = 0; i < 10000; ++i) rows.push("filtered-game-" + i)
        library.results = rows
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0.999999 }})
        compare(button.chooseGame(), "filtered-game-9999")
        compare(button.shuffleRemaining, 9999)
        verify(Object.keys(button.shuffleSlots).length <= 1)
    }
    function test_same_count_result_replacement_starts_a_fresh_cycle() {
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0 }})
        button.chooseGame()
        library.filtering = true
        library.results = ["snes-one", "snes-two", "snes-three"]
        library.modelReset()
        library.filtering = false
        verify(!button.shuffleStarted)
        const chosen = []
        for (let i = 0; i < 3; ++i) chosen.push(button.chooseGame())
        compare(chosen.slice().sort().join(","), library.results.slice().sort().join(","))
    }
    function test_metadata_only_reset_preserves_used_games() {
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0 }})
        const first = button.chooseGame()
        library.modelReset()
        compare(button.shuffleRemaining, 2)
        verify(button.chooseGame() !== first)
    }
    function test_pending_filter_resets_cycle_but_selection_changes_do_not() {
        const button = createTemporaryObject(buttonComponent, test, {randomSource: function() { return 0 }})
        button.selectedGameId = button.chooseGame()
        compare(button.shuffleRemaining, 2)
        button.selectedGameId = button.chooseGame()
        compare(button.shuffleRemaining, 1)
        button.filterPending = true
        verify(!button.shuffleStarted)
        compare(button.chooseGame(), "")
        button.filterPending = false
        const previous = button.selectedGameId
        verify(button.chooseGame() !== previous)
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
