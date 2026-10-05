pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: card
    required property var library
    required property int index
    property string platformName: library.platform_name_at(index)
    property int gameCount: library.platform_game_count_at(index)
    property bool selected: false
    property bool wheel: false
    property color panel: "#182230"
    property color ink: "#f4f7fb"
    property color muted: "#8d99aa"
    property color accent: "#ffb454"
    signal activated(int index)
    signal hoverMoved(int index, point position)
    signal hoverLeft(int index)
    Rectangle {
        anchors.fill: parent; anchors.margins: 6
        radius: 14
        color: card.selected ? Qt.lighter(card.panel, 1.25) : card.panel
        border.color: card.selected ? card.accent : Qt.rgba(1, 1, 1, 0.15)
        border.width: card.selected ? 2 : 1
        Image {
            id: logo
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: title.top; margins: 12 }
            source: { card.library.media_revision; return card.library.platform_media_url(card.platformName, "clear-logo") }
            sourceSize: Qt.size(640, 300)
            asynchronous: true; fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.centerIn: logo
            visible: logo.status !== Image.Ready
            text: card.platformName.charAt(0).toUpperCase()
            font.pixelSize: Math.min(56, logo.height * 0.7); font.weight: Font.Black
            color: card.muted
        }
        Text {
            id: title
            anchors { left: parent.left; right: parent.right; bottom: count.top; leftMargin: 10; rightMargin: 10; bottomMargin: 3 }
            text: card.platformName
            textFormat: Text.PlainText
            color: card.ink; font.pixelSize: card.wheel ? 17 : 15; font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            id: count
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
            text: card.gameCount.toLocaleString(Qt.locale(), "f", 0) + (card.gameCount === 1 ? " GAME" : " GAMES")
            color: card.selected ? card.accent : card.muted; font.pixelSize: 10
        }
    }
    HoverHandler {
        onPointChanged: if (hovered) card.hoverMoved(card.index, point.scenePosition)
        onHoveredChanged: if (!hovered) card.hoverLeft(card.index)
    }
    TapHandler { onTapped: card.activated(card.index) }
    Accessible.role: Accessible.ListItem
    Accessible.name: platformName + ", " + gameCount + " games"
    Accessible.selected: selected
    Accessible.onPressAction: activated(index)
}
