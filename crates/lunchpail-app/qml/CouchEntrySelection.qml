import QtQuick

// Pin identity while the asynchronous platform filter and its delegates settle.
Item {
    id: entry
    required property var library
    required property var browser
    property bool active: false
    property string gameId: ""
    property string platform: ""
    property bool unavailable: false
    readonly property bool pending: gameId.length > 0
    signal settled(string gameId)
    function begin(id, system) { gameId = id; platform = system; unavailable = false }
    function cancel() { gameId = ""; platform = ""; unavailable = false }
    function reconcile() {
        if (!active || !pending || !library.ready || library.filtering
                || library.current_platform !== platform) return false
        const row = library.row_for_game(gameId)
        if (row < 0) { unavailable = true; return false }
        unavailable = false
        browser.currentIndex = row
        browser.positionViewAtIndex(row, ListView.Center)
        if (!browser.currentItem || browser.currentItem.gameId !== gameId
                || browser.currentItem.index !== row || browser.currentIndex !== row) return false
        const selected = gameId
        cancel()
        settled(selected)
        return true
    }
    Timer { interval: 40; repeat: true; running: entry.active && entry.pending && !entry.unavailable; onTriggered: entry.reconcile() }
    Connections {
        target: entry.library
        // Model reset completes before filteringChanged, but its view delegates
        // can still be queued for polish. Let the next timer tick inspect them.
        function onFilteringChanged() { if (!entry.library.filtering) entry.unavailable = false }
    }
}
