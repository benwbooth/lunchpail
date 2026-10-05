import QtQuick

// A stationary pointer must not chase cards moved beneath it by a controller
// or an animated path. Only a new scene-space pointer position arms selection.
QtObject {
    id: selection
    property bool enabled: true
    property point observedPosition: Qt.point(-10000, -10000)
    property bool pointerKnown: false
    property int movementSerial: 0
    property int consumedSerial: 0
    property double movementTime: 0
    property int pendingIndex: -1
    signal selected(int index)
    function nearestPathIndex(view, pathView, scenePosition, vertical) {
        if (!pathView || !pathView.currentItem) return -1
        const point = view.mapFromItem(null, scenePosition.x, scenePosition.y)
        let nearest = -1, distance = Infinity
        // In a magnifying/overlapping carousel the focused card's rectangle
        // covers its neighbors. Pick the closest visual center, not that box.
        for (const item of pathView.currentItem.parent.children) {
            if (typeof item.index !== "number" || item.index < 0
                    || !item.visible || item.opacity < 0.15) continue
            const center = item.mapToItem(view, item.width / 2, item.height / 2)
            const along = Math.abs(vertical ? point.y - center.y : point.x - center.x)
            const across = Math.abs(vertical ? point.x - center.x : point.y - center.y)
            const reach = (vertical ? item.height : item.width) * item.scale * 0.70
            const breadth = (vertical ? item.width : item.height) * item.scale * 0.55
            if (along <= reach && across <= breadth && along < distance) {
                nearest = item.index; distance = along
            }
        }
        return nearest
    }
    function observe(position) {
        if (!enabled) return
        if (pointerKnown && (position.x !== observedPosition.x || position.y !== observedPosition.y)) {
            movementSerial++
            movementTime = Date.now()
        }
        observedPosition = position
        pointerKnown = true
    }
    function move(index, position) {
        // Parent and delegate handlers can receive the same event in either
        // order. After delivery, require actual movement seen by the browser.
        Qt.callLater(function() {
            if (!enabled || !pointerKnown || movementSerial === consumedSerial
                    || Date.now() - movementTime > 80
                    || position.x !== observedPosition.x || position.y !== observedPosition.y) return
            consumedSerial = movementSerial
            pendingIndex = index
            dwell.restart()
        })
    }
    function leave(index) {
        if (pendingIndex === index) { dwell.stop(); pendingIndex = -1 }
    }
    function cancel() { dwell.stop(); pendingIndex = -1; consumedSerial = movementSerial }
    function forget() { cancel(); pointerKnown = false }
    onEnabledChanged: forget()
    property Timer dwell: Timer {
        interval: 180
        onTriggered: if (selection.enabled && selection.pendingIndex >= 0)
                         selection.selected(selection.pendingIndex)
    }
}
