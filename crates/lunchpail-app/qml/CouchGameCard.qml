pragma ComponentBehavior: Bound

import QtQuick

// The same identity/artwork contract is used by the wall and both animated paths.
Item {
    id: card
    CouchPlatformIdentity { id: identity }
    required property var library
    required property int index
    required property string gameId
    required property string gameTitle
    required property string gameCanonicalTitle
    required property string gamePlatform
    required property bool gameLocal
    required property bool gameDownloadable
    required property int gameDatabaseId
    required property double gameMediaId
    property bool selected: false
    property bool wheel: false
    property color ink: "#f4f7fb"
    property color muted: "#8d99aa"
    property color accent: "#ffb454"
    property color panel: "#182230"
    property int artworkRevision: library.media_revision
    readonly property bool favorite: {
        library.favorite_revision
        return library.is_favorite(gameId)
    }
    readonly property bool favoriteBusy: {
        library.favorite_pending_count
        return library.favorite_pending(gameId)
    }
    readonly property url artwork: {
        artworkRevision
        // Generic artwork lookup may substitute a portrait cover when a logo
        // is missing. The wheel needs a logo or its readable title fallback.
        return wheel ? library.exact_artwork_url(gameMediaId, "clear-logo")
                     : library.artwork_url(gameMediaId, "box-front")
    }
    signal activated(int index)
    signal hoverMoved(int index, point position)
    signal hoverLeft(int index)

    // The viewport owns fetching. Delegate creation and role changes must not
    // enqueue the same image repeatedly while the wheel is moving.

    CouchFocusFrame { anchors.fill: frame; radius: frame.radius; selected: card.selected; accent: card.accent }
    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: 9
        radius: 14
        color: card.wheel ? (card.selected ? Qt.rgba(0.03, 0.06, 0.1, 0.72) : "transparent") : card.panel
        border.color: card.wheel ? (card.selected ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.6) : "transparent") : card.selected ? card.accent : Qt.rgba(1, 1, 1, 0.14)
        border.width: card.selected ? 2 : 1
        scale: card.wheel || card.selected ? 1 : hover.hovered ? 1.025 : 0.97
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            anchors { fill: cover; margins: 0 }
            visible: !card.wheel && cover.status !== Image.Ready
            radius: 10
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.darker(identity.color(card.gamePlatform), 2.4) }
                GradientStop { position: 1; color: "#0b111c" }
            }
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 4; color: identity.color(card.gamePlatform); opacity: 0.8 }
            Text {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 15 }
                text: identity.wordmark(card.gamePlatform)
                color: "#b6c6dc"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2
                elide: Text.ElideRight
            }
        }
        Image {
            id: cover
            anchors.fill: parent
            anchors.margins: card.wheel ? 14 : 5
            anchors.bottomMargin: card.wheel ? 14 : 52
            source: card.artwork
            sourceSize.width: card.wheel ? 640 : 480
            sourceSize.height: card.wheel ? 240 : 640
            asynchronous: true
            cache: true
            mipmap: !card.wheel
            retainWhileLoading: true
            fillMode: Image.PreserveAspectFit
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Text {
            anchors.centerIn: cover
            width: cover.width - 20
            visible: cover.status !== Image.Ready
            text: card.gameTitle
            color: card.ink
            font.pixelSize: card.wheel ? 28 : 25
            font.weight: Font.Bold
            minimumPixelSize: 14
            fontSizeMode: Text.Fit
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            height: cover.height
            verticalAlignment: Text.AlignVCenter
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
            height: 51; radius: 12; visible: !card.wheel
            color: card.selected ? Qt.lighter(card.panel, 1.45) : card.panel
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        Text {
            visible: !card.wheel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: 34
            text: card.gameTitle
            color: card.ink
            font.pixelSize: 15
            minimumPixelSize: 12
            fontSizeMode: Text.Fit
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 9
            width: 8; height: 8; radius: 4
            visible: card.gameLocal && !card.wheel
            color: "#5ee391"
        }
        Rectangle {
            visible: card.wheel && card.selected
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 7 }
            width: 4; height: parent.height * 0.42; radius: 2; color: card.accent
        }
        FavoriteButton {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 9
            visible: !card.wheel
            favorite: card.favorite
            busy: card.favoriteBusy
            gameTitle: card.gameTitle
            onToggleRequested: favorite => card.library.set_favorite(card.gameId, favorite)
        }
    }
    HoverHandler {
        id: hover
        onPointChanged: if (hovered) card.hoverMoved(card.index, point.scenePosition)
        onHoveredChanged: if (!hovered) card.hoverLeft(card.index)
    }
    TapHandler { onTapped: card.activated(card.index) }
    Accessible.role: Accessible.ListItem
    Accessible.name: gameTitle + ", " + gamePlatform
    Accessible.selected: selected
    Accessible.onPressAction: activated(index)
}
