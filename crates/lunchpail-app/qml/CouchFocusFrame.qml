import QtQuick

// A finite focus reveal: no continuously animating effects when browsing rests.
Item {
    id: halo
    property bool selected: false
    property color accent: "#ffab52"
    property real radius: 16
    property real reveal: 1
    onSelectedChanged: if (selected) revealAnimation.restart()
    opacity: selected ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 190 } }
    Rectangle { anchors.fill: parent; anchors.margins: -7; radius: halo.radius + 7; color: "transparent"; border.width: 3; border.color: Qt.rgba(halo.accent.r, halo.accent.g, halo.accent.b, 0.08) }
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: halo.radius + 3; color: "transparent"; border.width: 2; border.color: Qt.rgba(halo.accent.r, halo.accent.g, halo.accent.b, 0.26) }
    Rectangle { anchors.fill: parent; radius: halo.radius; color: "transparent"; border.width: 2; border.color: halo.accent }
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: -2 }
        width: parent.width * (0.12 + 0.3 * halo.reveal); height: 3; radius: 2
        color: "#f8faff"
        opacity: 0.85 - halo.reveal * 0.4
    }
    NumberAnimation { id: revealAnimation; target: halo; property: "reveal"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
}
