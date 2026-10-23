import QtQuick
import QtQuick.Controls

// Compact header button that shows or hides a side pane. The icon is a
// window outline whose left or right strip is filled while the pane shows.
HeaderButton {
    id: toggle
    property string side: "left"
    property bool shown: true
    property string paneName: ""
    active: shown
    implicitWidth: 42
    leftPadding: 0
    rightPadding: 0
    contentItem: Item {
        implicitWidth: 20
        implicitHeight: 16
        Rectangle {
            anchors.centerIn: parent
            width: 20
            height: 16
            radius: 3
            color: "transparent"
            border.width: 1.5
            border.color: toggle.enabled ? (toggle.shown ? "#ffb454" : "#8d99aa") : "#4a5466"
            Rectangle {
                width: 6
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 3
                x: toggle.side === "left" ? 3 : parent.width - width - 3
                radius: 1
                color: parent.border.color
                opacity: toggle.shown ? 1 : 0.35
            }
        }
    }
    ToolTip.visible: hovered
    ToolTip.text: (shown ? "Hide " : "Show ") + paneName
    Accessible.name: (shown ? "Hide " : "Show ") + paneName
}
