import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl as ControlsImpl

ToolButton {
    id: control
    property bool destructive: false
    property bool previewHover: false
    property color focusColor: "#62d6c6"
    readonly property bool showHover: hovered || previewHover
    flat: true
    display: AbstractButton.IconOnly
    icon.width: 18
    icon.height: 18
    icon.color: destructive && showHover ? "#ffffff" : "#d9e4ef"
    contentItem: Item {
        ControlsImpl.IconImage {
            anchors.centerIn: parent
            width: 18; height: 18
            sourceSize.width: 18; sourceSize.height: 18
            fillMode: Image.PreserveAspectFit
            name: control.icon.name
            source: control.icon.source
            color: control.icon.color
        }
    }
    background: Rectangle {
        radius: width / 2
        color: control.down ? (control.destructive ? "#8d2735" : "#34445a")
               : control.showHover ? (control.destructive ? "#b33342" : "#2b394b") : "transparent"
        border.width: control.visualFocus ? 1 : 0
        border.color: control.focusColor
    }
}
