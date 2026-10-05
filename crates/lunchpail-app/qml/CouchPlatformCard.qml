pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: card
    CouchPlatformIdentity { id: identity }
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
    readonly property color systemAccent: identity.color(platformName)
    signal activated(int index)
    signal hoverMoved(int index, point position)
    signal hoverLeft(int index)

    CouchFocusFrame { anchors.fill: frame; selected: card.selected; accent: card.accent; radius: frame.radius }
    Rectangle {
        id: frame
        anchors.fill: parent; anchors.margins: 8
        radius: 16
        gradient: Gradient {
            GradientStop { position: 0; color: card.selected ? Qt.lighter(card.panel, 1.45) : card.panel }
            GradientStop { position: 1; color: "#0b111b" }
        }
        border.color: card.selected ? card.accent : "#384758"
        border.width: 1
        scale: card.selected ? 1 : hover.hovered ? 0.99 : 0.97
        Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 1 }
            height: 3; width: parent.width * 0.36; radius: 2
            color: card.systemAccent
        }
        Image {
            id: logo
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: title.top; margins: 16 }
            source: { card.library.media_revision; return card.library.platform_media_url(card.platformName, "clear-logo") }
            sourceSize: Qt.size(640, 300)
            asynchronous: true; fillMode: Image.PreserveAspectFit
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
        Text {
            anchors.fill: logo
            anchors.margins: 6
            visible: logo.status !== Image.Ready
            text: identity.wordmark(card.platformName)
            color: card.selected ? card.ink : card.systemAccent
            font.pixelSize: 38; minimumPixelSize: 15; fontSizeMode: Text.Fit
            font.weight: Font.Bold; font.letterSpacing: 1.2
            wrapMode: Text.WordWrap; maximumLineCount: 3
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        Text {
            id: title
            anchors { left: parent.left; right: parent.right; bottom: count.top; leftMargin: 14; rightMargin: 14; bottomMargin: 6 }
            text: card.platformName
            textFormat: Text.PlainText
            color: card.ink; font.pixelSize: card.wheel ? 15 : 13; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            id: count
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
            text: card.gameCount.toLocaleString(Qt.locale(), "f", 0) + (card.gameCount === 1 ? " GAME" : " GAMES")
            color: card.selected ? card.accent : card.muted; font.pixelSize: 10; font.letterSpacing: 1
        }
    }
    HoverHandler {
        id: hover
        onPointChanged: if (hovered) card.hoverMoved(card.index, point.scenePosition)
        onHoveredChanged: if (!hovered) card.hoverLeft(card.index)
    }
    TapHandler { onTapped: card.activated(card.index) }
    Accessible.role: Accessible.ListItem
    Accessible.name: platformName + ", " + gameCount + " games"
    Accessible.selected: selected
    Accessible.onPressAction: activated(index)
}
