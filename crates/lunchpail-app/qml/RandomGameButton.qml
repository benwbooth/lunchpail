import QtQuick
import QtQuick.Controls

HeaderButton {
    id: control
    required property var libraryModel
    property string selectedGameId: ""
    property bool filterPending: false
    property bool compact: false
    property var randomSource: Math.random
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
    Accessible.description: "Select a game matching the current platform, collection, search, and filters. Does not launch it."
    ToolTip.visible: hovered || visualFocus
    ToolTip.text: "Select a random game from these results"

    function chooseGame() {
        if (!enabled) return ""
        const count = libraryModel.filtered_count
        const current = libraryModel.row_for_game(selectedGameId)
        const skipCurrent = count > 1 && current >= 0 && current < count
        // Draw directly from the filtered model, not just instantiated cards.
        // Remapping one slot keeps every other result equally likely.
        let row = Math.floor(randomSource() * (skipCurrent ? count - 1 : count))
        if (skipCurrent && row >= current) row++
        const gameId = libraryModel.game_id_for_row(row)
        if (gameId.length > 0) gameChosen(gameId)
        return gameId
    }
    onClicked: chooseGame()

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
