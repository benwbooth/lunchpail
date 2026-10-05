import QtQuick
import QtQuick.Controls

Button {
    id: control
    property color inkColor: "#f4f7fb"
    property color panelColor: "#101823"
    property color accentColor: "#ffab52"
    property bool emphasized: false
    property string iconName: ""
    readonly property bool iconOnly: iconName.length > 0
    implicitWidth: iconOnly ? 44 : Math.max(44, label.implicitWidth + 44)
    implicitHeight: 44
    padding: iconOnly ? 10 : 14
    hoverEnabled: true
    scale: down ? 0.96 : hovered || visualFocus ? 1.025 : 1
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    background: Rectangle {
        radius: 12
        color: control.emphasized ? Qt.rgba(control.accentColor.r, control.accentColor.g, control.accentColor.b, 0.18)
              : control.hovered || control.visualFocus ? Qt.lighter(control.panelColor, 1.65)
              : Qt.rgba(control.panelColor.r, control.panelColor.g, control.panelColor.b, 0.88)
        border.width: control.visualFocus ? 2 : 1
        border.color: control.hovered || control.visualFocus || control.emphasized ? control.accentColor : "#384758"
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
    contentItem: Item {
        Text {
            id: label
            objectName: "couchActionLabel"
            anchors.fill: parent
            visible: !control.iconOnly
            text: control.text
            textFormat: Text.PlainText
            color: control.enabled ? control.inkColor : "#758294"
            font.pixelSize: 12; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        SemanticIcon {
            objectName: "couchActionIcon"
            anchors.centerIn: parent
            width: 24; height: 24
            visible: control.iconOnly
            name: control.iconName
            color: control.enabled ? control.inkColor : "#758294"
        }
    }
    Accessible.name: text
}
