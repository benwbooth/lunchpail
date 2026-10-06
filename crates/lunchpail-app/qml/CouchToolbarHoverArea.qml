import QtQuick

Item {
    id: area
    readonly property bool hovered: visible && enabled && pointer.hovered && pointer.point.position.y >= 0
                                   && pointer.point.position.y < height
    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: 150
    HoverHandler {
        id: pointer
        // Observe the common ancestor, not a sibling behind the toolbar.
        // Buttons consume sibling hover; putting the sensor above them also
        // deprives the buttons of hover. Either way creates unstable reveal
        // state. An ancestor observes both the empty band and its controls.
        parent: area.parent
        enabled: area.visible && area.enabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false
    }
}
