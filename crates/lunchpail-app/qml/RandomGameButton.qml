import QtQuick
import QtQuick.Controls

HeaderButton {
    id: control
    required property var libraryModel
    property string selectedGameId: ""
    property bool filterPending: false
    property bool compact: false
    property var randomSource: Math.random
    property var shuffleSlots: ({})
    property int shuffleRemaining: 0
    property int shuffleSize: 0
    property bool shuffleStarted: false
    signal gameChosen(string gameId)

    objectName: "randomGameButton"
    text: "Random"
    implicitWidth: compact ? 41 : Math.max(92, implicitContentWidth + leftPadding + rightPadding)
    leftPadding: compact ? 11 : 16
    rightPadding: leftPadding
    enabled: libraryModel.ready && !libraryModel.loading && !libraryModel.filtering
             && !filterPending && libraryModel.filtered_count > 0
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    Accessible.name: "Select random game"
    Accessible.description: "Shuffle games matching the current platform, collection, search, and filters without repeats until the cycle is complete. Does not launch them."
    ToolTip.visible: hovered || visualFocus
    ToolTip.text: "Shuffle these results · no repeats until every game has had a turn"

    function resetShuffle() {
        shuffleSlots = {}
        shuffleRemaining = 0
        shuffleSize = 0
        shuffleStarted = false
    }
    function rowAt(slot) {
        return shuffleSlots[slot] === undefined ? slot : shuffleSlots[slot]
    }
    function takeRow(slot) {
        const row = rowAt(slot)
        const last = shuffleRemaining - 1
        if (slot !== last) shuffleSlots[slot] = rowAt(last)
        delete shuffleSlots[last]
        shuffleRemaining--
        return row
    }
    function startShuffle(count, current, firstCycle) {
        shuffleSlots = {}
        shuffleRemaining = count
        shuffleSize = count
        shuffleStarted = true
        // The game already selected when shuffling starts has had its turn.
        if (firstCycle && count > 1 && current >= 0 && current < count)
            takeRow(current)
    }

    function chooseGame() {
        if (!enabled) return ""
        const count = libraryModel.filtered_count
        const current = libraryModel.row_for_game(selectedGameId)
        if (!shuffleStarted || shuffleSize !== count)
            startShuffle(count, current, true)
        else if (shuffleRemaining === 0)
            startShuffle(count, current, false)
        // Lazy Fisher-Yates: only chosen/swapped slots need storage, so even a
        // huge library needs no up-front list allocation or per-game queries.
        let slot = Math.floor(randomSource() * shuffleRemaining)
        if (shuffleRemaining > 1 && rowAt(slot) === current) {
            const other = Math.floor(randomSource() * (shuffleRemaining - 1))
            slot = other >= slot ? other + 1 : other
        }
        const gameId = libraryModel.game_id_for_row(takeRow(slot))
        if (gameId.length > 0) gameChosen(gameId)
        return gameId
    }
    onClicked: chooseGame()
    onLibraryModelChanged: resetShuffle()
    onFilterPendingChanged: if (filterPending) resetShuffle()
    Connections {
        target: control.libraryModel
        ignoreUnknownSignals: true
        function onModelReset() {
            // Metadata-only repaints do not change the filtered row identities.
            if (control.libraryModel.filtering || control.libraryModel.loading)
                control.resetShuffle()
        }
        function onFiltered_countChanged() { control.resetShuffle() }
        function onFilteringChanged() { if (control.libraryModel.filtering) control.resetShuffle() }
        function onLoadingChanged() { if (control.libraryModel.loading) control.resetShuffle() }
    }

    contentItem: Row {
        spacing: 7
        SemanticIcon {
            objectName: "randomGameDiceIcon"
            width: 19; height: 19
            anchors.verticalCenter: parent.verticalCenter
            name: "dice"
            color: control.enabled ? "#f4f7fb" : "#8d99aa"
        }
        Text {
            visible: !control.compact
            text: control.text
            font: control.font
            color: control.enabled ? "#f4f7fb" : "#8d99aa"
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
