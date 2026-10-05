pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: browser
    required property var library
    property string viewStyle: "wheel"
    property color panel: "#182230"
    property color ink: "#f4f7fb"
    property color muted: "#8d99aa"
    property color accent: "#ffb454"
    property int currentIndex: 0
    property bool selectionPending: true
    readonly property int count: library.platform_count
    readonly property int columns: viewStyle === "wall" && presentation.item ? presentation.item.columnCount : 1
    readonly property var currentItem: !selectionPending && presentation.item ? presentation.item.currentItem : null
    property bool hoverSelectionEnabled: true
    signal activated(int index)
    function applySelection() {
        const item = presentation.item
        if (!item || (count > 0 && !item.currentItem && viewStyle !== "wall" && viewStyle !== "shelf")) return
        const next = count > 0 ? Math.max(0, Math.min(currentIndex, count - 1)) : -1
        item.currentIndex = next
        if (currentIndex !== next) currentIndex = next
        selectionPending = false
    }
    function positionViewAtIndex(index, mode) {
        if (!presentation.item || index < 0) return
        if (viewStyle === "wall" || viewStyle === "shelf") presentation.item.positionViewAtIndex(index, mode)
        else applySelection()
    }
    function positionViewAtBeginning() { positionViewAtIndex(0, ListView.Beginning) }
    function positionViewAtEnd() { positionViewAtIndex(count - 1, ListView.End) }
    function settleSelection() {
        if (!presentation.item || count <= 0) return
        if (viewStyle === "wall" || viewStyle === "shelf") presentation.item.forceLayout()
        positionViewAtIndex(currentIndex, ListView.Contain)
    }
    onCurrentIndexChanged: {
        pointerSelection.cancel()
        selectionPending = true; applySelection()
    }
    onViewStyleChanged: pointerSelection.cancel()
    onWidthChanged: { pointerSelection.cancel(); Qt.callLater(settleSelection) }
    onHeightChanged: { pointerSelection.cancel(); Qt.callLater(settleSelection) }
    onCountChanged: { selectionPending = true; Qt.callLater(applySelection) }
    CouchPointerSelection {
        id: pointerSelection
        enabled: browser.visible && browser.hoverSelectionEnabled
        onSelected: index => { if (index < browser.count) browser.currentIndex = index }
    }
    HoverHandler {
        onPointChanged: if (hovered) pointerSelection.observe(point.scenePosition)
        onHoveredChanged: if (!hovered) pointerSelection.forget()
    }
    function cancelPointerSelection() { pointerSelection.cancel() }
    Loader {
        id: presentation
        anchors.fill: parent
        active: browser.visible
        sourceComponent: browser.viewStyle === "wall" ? wall : browser.viewStyle === "shelf" ? shelf : carouselComponent
        onLoaded: {
            browser.selectionPending = true
            browser.applySelection()
            Qt.callLater(browser.settleSelection)
        }
    }
    Connections {
        target: presentation.item
        function onCurrentIndexChanged() {
            if (!browser.selectionPending && presentation.item && presentation.item.currentIndex >= 0)
                browser.currentIndex = presentation.item.currentIndex
        }
        function onCurrentItemChanged() { if (browser.selectionPending) Qt.callLater(browser.applySelection) }
    }
    Component {
        id: wall
        MomentumGridView {
            id: grid
            objectName: "couchPlatformWall"
            readonly property int columnCount: Math.max(2, Math.floor(verticalContentWidth / 210))
            model: browser.count
            cellWidth: verticalContentWidth / columnCount
            cellHeight: Math.min(220, cellWidth * 0.92)
            clip: true; cacheBuffer: height / 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: LbScrollBar { policy: ScrollBar.AsNeeded }
            delegate: CouchPlatformCard {
                library: browser.library
                width: grid.cellWidth - 8; height: grid.cellHeight - 8
                selected: GridView.isCurrentItem
                panel: browser.panel; ink: browser.ink; muted: browser.muted; accent: browser.accent
                onActivated: index => browser.activated(index)
                onHoverMoved: (index, position) => pointerSelection.move(index, position)
                onHoverLeft: index => pointerSelection.leave(index)
            }
        }
    }
    Component {
        id: shelf
        MomentumListView {
            id: row
            orientation: ListView.Horizontal
            model: browser.count; clip: true; spacing: 10
            snapMode: ListView.SnapToItem
            boundsBehavior: Flickable.StopAtBounds
            delegate: CouchPlatformCard {
                library: browser.library
                width: Math.min(260, row.width * 0.4); height: Math.min(row.height, 310)
                y: (row.height - height) / 2
                selected: ListView.isCurrentItem
                panel: browser.panel; ink: browser.ink; muted: browser.muted; accent: browser.accent
                onActivated: index => browser.activated(index)
                onHoverMoved: (index, position) => pointerSelection.move(index, position)
                onHoverLeft: index => pointerSelection.leave(index)
            }
        }
    }
    Component {
        id: carouselComponent
        PathView {
            id: carousel
            readonly property bool wheel: browser.viewStyle === "wheel"
            model: browser.count; clip: true
            pathItemCount: wheel ? 5 : 7
            cacheItemCount: 2
            preferredHighlightBegin: 0.5; preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 210
            snapMode: PathView.SnapToItem
            dragMargin: width; flickDeceleration: 450
            path: wheel ? wheelPath : flowPath
            delegate: CouchPlatformCard {
                id: card
                library: browser.library
                width: carousel.wheel ? carousel.width * 0.75 : carousel.width * 0.35
                height: carousel.wheel ? Math.min(200, carousel.height * 0.38) : Math.min(carousel.height * 0.88, width * 1.25)
                wheel: carousel.wheel; selected: PathView.isCurrentItem
                panel: browser.panel; ink: browser.ink; muted: browser.muted; accent: browser.accent
                scale: PathView.itemScale ?? 1; opacity: PathView.itemOpacity ?? 1; z: PathView.itemDepth ?? 0
                rotation: carousel.wheel ? (PathView.itemAngle ?? 0) : 0
                transform: Rotation {
                    origin.x: card.width / 2; origin.y: card.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: carousel.wheel ? 0 : (card.PathView.itemAngle ?? 0)
                }
                onActivated: index => browser.activated(index)
                onHoverMoved: (index, position) => pointerSelection.move(index, position)
                onHoverLeft: index => pointerSelection.leave(index)
            }
            Path {
                id: wheelPath
                startX: carousel.width * 0.8; startY: -90
                PathAttribute { name: "itemScale"; value: 0.55 }
                PathAttribute { name: "itemOpacity"; value: 0.25 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathAttribute { name: "itemAngle"; value: -14 }
                PathQuad { x: carousel.width * 0.45; y: carousel.height / 2; controlX: carousel.width * 0.38; controlY: carousel.height * 0.15 }
                PathPercent { value: 0.5 }
                PathAttribute { name: "itemScale"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }
                PathAttribute { name: "itemDepth"; value: 10 }
                PathAttribute { name: "itemAngle"; value: 0 }
                PathQuad { x: carousel.width * 0.8; y: carousel.height + 90; controlX: carousel.width * 0.38; controlY: carousel.height * 0.85 }
                PathAttribute { name: "itemScale"; value: 0.55 }
                PathAttribute { name: "itemOpacity"; value: 0.25 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathAttribute { name: "itemAngle"; value: 14 }
            }
            Path {
                id: flowPath
                startX: -carousel.width * 0.1; startY: carousel.height * 0.55
                PathAttribute { name: "itemScale"; value: 0.65 }
                PathAttribute { name: "itemOpacity"; value: 0.25 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathAttribute { name: "itemAngle"; value: 60 }
                PathLine { x: carousel.width * 0.28; y: carousel.height * 0.55 }
                PathPercent { value: 0.35 }
                PathAttribute { name: "itemScale"; value: 0.78 }
                PathAttribute { name: "itemOpacity"; value: 0.8 }
                PathAttribute { name: "itemDepth"; value: 4 }
                PathAttribute { name: "itemAngle"; value: 50 }
                PathLine { x: carousel.width / 2; y: carousel.height / 2 }
                PathPercent { value: 0.5 }
                PathAttribute { name: "itemScale"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }
                PathAttribute { name: "itemDepth"; value: 10 }
                PathAttribute { name: "itemAngle"; value: 0 }
                PathLine { x: carousel.width * 0.72; y: carousel.height * 0.55 }
                PathPercent { value: 0.65 }
                PathAttribute { name: "itemScale"; value: 0.78 }
                PathAttribute { name: "itemOpacity"; value: 0.8 }
                PathAttribute { name: "itemDepth"; value: 4 }
                PathAttribute { name: "itemAngle"; value: -50 }
                PathLine { x: carousel.width * 1.1; y: carousel.height * 0.55 }
                PathAttribute { name: "itemScale"; value: 0.65 }
                PathAttribute { name: "itemOpacity"; value: 0.25 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathAttribute { name: "itemAngle"; value: -60 }
            }
        }
    }
}
