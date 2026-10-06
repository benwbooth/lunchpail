import QtQuick
import QtQuick.Controls

// Compact, artwork-safe actions with the same visual language in the details pane.
Button {
    id: control
    property string iconName: ""
    property bool iconFilled: true
    property bool positive: false
    property bool selected: false
    property bool busy: false
    property bool keepIconWhenBusy: false
    property bool showLabel: text.length > 0
    property real iconSize: 20
    readonly property color foreground: !enabled && !busy ? "#8c99a9"
                                               : selected ? "#ffce86"
                                               : positive ? "#dcffe9" : "#f0f4fa"
    implicitWidth: showLabel ? Math.max(80, label.implicitWidth + 24
                                        + (iconName.length > 0 || busy ? iconSize + spacing : 0)) : 36
    implicitHeight: 36
    padding: 8
    spacing: 7
    hoverEnabled: true
    // Clicking a card action must not enter controller-navigation mode.
    focusPolicy: Qt.TabFocus
    font.family: Qt.application.font.family
    font.pixelSize: 12
    font.weight: Font.DemiBold
    scale: down ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    Accessible.name: text
    background: Rectangle {
        id: surface
        readonly property bool raised: control.positive && control.enabled && !control.busy
        radius: Math.min(10, height / 3)
        color: !control.enabled && !control.busy ? "#e61a222e"
               : control.down ? (control.positive ? "#f0123023" : "#f017202d")
               : control.selected ? (control.hovered ? "#f0473928" : "#ee322a21")
               : control.positive ? (control.hovered ? "#f0285940" : "#ed1b4030")
               : control.hovered ? "#f0313e50" : "#e61a2432"
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? "#e8f1ff"
                      : control.selected ? (control.hovered ? "#c69555" : "#80603a")
                      : control.positive && control.enabled ? (control.hovered ? "#8fd8ad" : "#507f63")
                      : control.hovered ? "#708299" : "#63738393"
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        gradient: raised ? playFinish : null
        Gradient {
            id: playFinish
            GradientStop { position: 0; color: Qt.lighter(surface.color, control.down ? 1.04 : 1.24) }
            GradientStop { position: 1; color: Qt.darker(surface.color, 1.12) }
        }
        // Small translucent layers keep the shadow soft without allocating a
        // shader texture for every cover, and also work with software rendering.
        Item {
            id: shadow
            objectName: "gameActionShadow"
            anchors.fill: parent
            z: -1
            visible: surface.raised
            property real elevation: control.down ? 1 : control.hovered ? 4 : 3
            Behavior on elevation { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            Repeater {
                model: shadow.visible ? 5 : 0
                Rectangle {
                    required property int index
                    readonly property real spread: index * 0.8
                    x: -spread
                    y: shadow.elevation - spread
                    width: shadow.width + spread * 2
                    height: shadow.height + spread * 2
                    radius: surface.radius + spread
                    color: "black"
                    opacity: control.down ? 0.035 : 0.075
                }
            }
        }
        Rectangle {
            objectName: "gameActionTopHighlight"
            visible: surface.raised
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: surface.radius
            anchors.rightMargin: surface.radius
            height: 1
            color: control.down ? "#10d9ffe8" : "#38d9ffe8"
        }
    }
    contentItem: Item {
        implicitWidth: contents.implicitWidth
        implicitHeight: control.iconSize
        Row {
            id: contents
            anchors.centerIn: parent
            spacing: control.spacing
            Item {
                id: iconSlot
                width: control.iconName.length > 0 || control.busy ? control.iconSize : 0
                height: control.iconSize
                visible: width > 0
                SemanticIcon {
                    objectName: "gameActionIcon"
                    anchors.fill: parent
                    name: control.iconName
                    filled: control.iconFilled
                    color: control.foreground
                    visible: !control.busy || control.keepIconWhenBusy
                    opacity: control.busy ? 0.55 : 1
                }
                SemanticIcon {
                    id: progress
                    objectName: "gameActionProgress"
                    anchors.centerIn: parent
                    width: control.keepIconWhenBusy ? control.iconSize + 7 : control.iconSize
                    height: width
                    name: "loading"
                    color: control.foreground
                    visible: control.busy
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                        running: control.busy && control.visible
                    }
                }
            }
            Text {
                id: label
                objectName: "gameActionLabel"
                visible: control.showLabel
                text: control.text
                textFormat: Text.PlainText
                font: control.font
                color: control.foreground
                height: control.iconSize
                width: Math.min(implicitWidth, Math.max(0, control.availableWidth
                                    - (iconSlot.visible ? iconSlot.width + control.spacing : 0)))
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
