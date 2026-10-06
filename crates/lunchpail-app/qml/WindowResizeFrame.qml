pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: frame
    required property var applicationWindow
    component Edge: MouseArea {
        required property int edges
        acceptedButtons: Qt.LeftButton
        onPressed: frame.applicationWindow.startSystemResize(edges)
    }
    Edge {
        objectName: "windowResizeTop"
        edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.leftMargin: 10; anchors.rightMargin: 10; height: 5
    }
    Edge {
        objectName: "windowResizeBottom"
        edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 10; anchors.rightMargin: 10; height: 7
    }
    Edge {
        objectName: "windowResizeLeft"
        edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.topMargin: 10; anchors.bottomMargin: 10; width: 6
    }
    Edge {
        objectName: "windowResizeRight"
        edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.topMargin: 10; anchors.bottomMargin: 10; width: 6
    }
    Edge {
        objectName: "windowResizeTopLeft"
        edges: Qt.TopEdge | Qt.LeftEdge; cursorShape: Qt.SizeFDiagCursor
        anchors.left: parent.left; anchors.top: parent.top; width: 10; height: 10
    }
    Edge {
        objectName: "windowResizeTopRight"
        edges: Qt.TopEdge | Qt.RightEdge; cursorShape: Qt.SizeBDiagCursor
        anchors.right: parent.right; anchors.top: parent.top; width: 10; height: 10
    }
    Edge {
        objectName: "windowResizeBottomLeft"
        edges: Qt.BottomEdge | Qt.LeftEdge; cursorShape: Qt.SizeBDiagCursor
        anchors.left: parent.left; anchors.bottom: parent.bottom; width: 10; height: 10
    }
    Edge {
        objectName: "windowResizeBottomRight"
        edges: Qt.BottomEdge | Qt.RightEdge; cursorShape: Qt.SizeFDiagCursor
        anchors.right: parent.right; anchors.bottom: parent.bottom; width: 10; height: 10
    }
}
