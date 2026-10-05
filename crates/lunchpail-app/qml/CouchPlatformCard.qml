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
    property bool coverFlow: false
    property bool pointerActivationEnabled: true
    property bool animateEntrance: false
    property int entranceDelay: 0
    property real entranceProgress: animateEntrance ? 0 : 1
    SequentialAnimation {
        running: card.animateEntrance
        PauseAnimation { duration: Math.max(0, Math.min(180, card.entranceDelay)) }
        NumberAnimation {
            target: card; property: "entranceProgress"; from: 0; to: 1
            duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.65
        }
    }
    property real focusDistance: 8
    property real focusAmount: selected ? 1 : Math.max(0, 1 - focusDistance / 3) * 0.35
    Behavior on focusAmount { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    property color panel: "#182230"
    property color ink: "#f4f7fb"
    property color muted: "#8d99aa"
    property color accent: "#ffb454"
    readonly property color systemAccent: identity.color(platformName)
    signal activated(int index)
    signal hoverMoved(int index, point position)
    signal hoverLeft(int index)

    CouchFocusFrame {
        anchors.fill: frame; selected: card.selected; accent: card.accent; radius: frame.radius
        visible: !card.wheel
        opacity: card.entranceProgress
        scale: frame.scale
        transform: Translate { y: card.coverFlow ? 0 : -4 * card.focusAmount }
    }
    CouchCoverReflection {
        sourceItem: frame
        x: frame.x; y: frame.y + frame.height + 6
        width: frame.width; height: card.height * 0.23
        visible: card.coverFlow
    }
    Rectangle {
        id: frame
        objectName: "couchPlatformCardFrame"
        anchors.fill: parent; anchors.margins: 8
        radius: 16
        color: "transparent"
        gradient: card.wheel ? null : panelGradient
        Gradient {
            id: panelGradient
            GradientStop { position: 0; color: card.selected ? Qt.lighter(card.panel, 1.45) : card.panel }
            GradientStop { position: 1; color: "#0b111b" }
        }
        border.color: card.wheel ? "transparent" : card.selected ? card.accent : "#384758"
        border.width: 1
        opacity: card.entranceProgress
        scale: (card.wheel || card.coverFlow ? 1 : 0.95 + card.focusAmount * 0.075)
               * (0.86 + 0.14 * card.entranceProgress)
        transform: Translate { y: card.coverFlow || card.wheel ? 0 : -4 * card.focusAmount }
        Rectangle {
            visible: !card.wheel
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 1 }
            height: 3; width: parent.width * 0.36; radius: 2
            color: card.systemAccent
        }
        Image {
            id: logo
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: card.wheel ? parent.bottom : title.top; margins: 16 }
            source: { card.library.media_revision; return card.library.platform_media_url(card.platformName, "clear-logo") }
            sourceSize: Qt.size(640, 300)
            asynchronous: true; fillMode: Image.PreserveAspectFit; mipmap: true
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
            visible: !card.wheel
            anchors { left: parent.left; right: parent.right; bottom: count.top; leftMargin: 14; rightMargin: 14; bottomMargin: 6 }
            text: card.platformName
            textFormat: Text.PlainText
            color: card.ink; font.pixelSize: card.wheel ? 15 : 13; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            id: count
            visible: !card.wheel
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
            text: card.gameCount.toLocaleString(Qt.locale(), "f", 0) + (card.gameCount === 1 ? " GAME" : " GAMES")
            color: card.selected ? card.accent : card.muted; font.pixelSize: 10; font.letterSpacing: 1
        }
        SemanticIcon {
            visible: card.wheel && card.selected
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: -4 }
            width: 16; height: 22; name: "play"; filled: true; color: card.accent
        }
    }
    HoverHandler {
        id: hover
        onPointChanged: if (hovered) card.hoverMoved(card.index, point.scenePosition)
        onHoveredChanged: if (!hovered) card.hoverLeft(card.index)
    }
    TapHandler {
        enabled: card.pointerActivationEnabled
        onTapped: card.activated(card.index)
    }
    Accessible.role: Accessible.ListItem
    Accessible.name: platformName + ", " + gameCount + " games"
    Accessible.selected: selected
    Accessible.onPressAction: activated(index)
}
