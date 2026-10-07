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
    property bool filtered: false
    readonly property int count: filtered ? library.filtered_platform_count : library.platform_count
    function nameAt(index) {
        library.platform_revision
        return filtered ? library.filtered_platform_name_at(index) : library.platform_name_at(index)
    }
    function gameCountAt(index) {
        library.platform_revision
        return filtered ? library.filtered_platform_game_count_at(index) : library.platform_game_count_at(index)
    }
    readonly property int columns: viewStyle === "wall" && presentation.item ? presentation.item.columnCount : 1
    readonly property var currentItem: !selectionPending && presentation.item ? presentation.item.currentItem : null
    property bool hoverSelectionEnabled: true
    function requestLogos() {
        if (visible && count > 0 && typeof library.request_platform_logos === "function")
            library.request_platform_logos()
    }
    Component.onCompleted: Qt.callLater(requestLogos)
    onVisibleChanged: if (visible) Qt.callLater(requestLogos)
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
        else {
            applySelection()
            if (mode === ListView.Center)
                presentation.item.positionViewAtIndex(index, PathView.SnapPosition)
        }
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
    onCountChanged: { selectionPending = true; Qt.callLater(applySelection); Qt.callLater(requestLogos) }
    CouchPointerSelection {
        id: pointerSelection
        enabled: browser.visible && browser.hoverSelectionEnabled
        onSelected: index => { if (index < browser.count) browser.currentIndex = index }
    }
    HoverHandler {
        onPointChanged: if (hovered) {
            pointerSelection.observe(point.scenePosition)
            browser.movePathPointer(point.scenePosition)
        }
        onHoveredChanged: if (!hovered) pointerSelection.forget()
    }
    function cancelPointerSelection() { pointerSelection.cancel() }
    function pathIndexAt(position) {
        return pointerSelection.nearestPathIndex(browser, presentation.item, position, viewStyle === "wheel")
    }
    function movePathPointer(position) {
        if (viewStyle !== "wheel" && viewStyle !== "album") return
        const index = pathIndexAt(position)
        if (index >= 0) pointerSelection.move(index, position)
    }
    Loader {
        id: presentation
        anchors.fill: parent
        active: browser.visible
        sourceComponent: browser.viewStyle === "wall" ? wall : browser.viewStyle === "shelf" ? shelf
                         : browser.viewStyle === "wheel" ? wheelComponent : carouselComponent
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
                platformName: browser.nameAt(index)
                gameCount: browser.gameCountAt(index)
                width: grid.cellWidth - 8; height: grid.cellHeight - 8
                selected: GridView.isCurrentItem
                animateEntrance: true
                entranceDelay: (index % grid.columnCount) * 24
                focusDistance: Math.abs(index % grid.columnCount - grid.currentIndex % grid.columnCount)
                    + Math.abs(Math.floor(index / grid.columnCount) - Math.floor(grid.currentIndex / grid.columnCount))
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
                platformName: browser.nameAt(index)
                gameCount: browser.gameCountAt(index)
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
    Component { id: wheelComponent; AnimatedPath { wheel: true } }
    Component { id: carouselComponent; AnimatedPath { wheel: false } }
    component AnimatedPath: PathView {
            id: carousel
            objectName: "couchPlatformCarousel"
            property bool wheel: false
            model: browser.count; clip: true
            pathItemCount: 11
            cacheItemCount: wheel ? 12 : 2
            preferredHighlightBegin: 0.5; preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: wheel ? 160 : 340
            snapMode: PathView.SnapToItem
            dragMargin: width; flickDeceleration: 450
            path: wheel ? wheelPath : flowPath
            TapHandler {
                onTapped: eventPoint => {
                    const index = browser.pathIndexAt(eventPoint.scenePosition)
                    if (index >= 0) browser.activated(index)
                }
            }
            delegate: wheel ? wheelDelegate : coverDelegate
            Component {
                id: wheelDelegate
                CouchWheelLogo {
                    required property int index
                    property string platformName: browser.nameAt(index)
                    width: carousel.width * 0.94
                    height: carousel.height * 0.21
                    title: platformName
                    source: {
                        browser.library.media_revision
                        return browser.library.platform_media_url(platformName, "wheel-logo")
                    }
                    selected: PathView.isCurrentItem
                    ink: browser.ink
                    scale: PathView.itemScale ?? 1
                    opacity: PathView.itemOpacity ?? 1
                    z: PathView.itemDepth ?? 0
                    rotation: PathView.itemAngle ?? 0
                    Accessible.onPressAction: browser.activated(index)
                }
            }
            Component {
              id: coverDelegate
              CouchPlatformCard {
                id: card
                library: browser.library
                platformName: browser.nameAt(index)
                gameCount: browser.gameCountAt(index)
                width: carousel.wheel ? carousel.width * 0.76 : Math.min(carousel.height * 0.68, carousel.width * 0.30)
                height: carousel.wheel ? Math.min(174, carousel.height * 0.25) : carousel.height * 0.74
                wheel: carousel.wheel; selected: PathView.isCurrentItem
                coverFlow: !carousel.wheel
                pointerActivationEnabled: false
                panel: browser.panel; ink: browser.ink; muted: browser.muted; accent: browser.accent
                scale: PathView.itemScale ?? 1; opacity: PathView.itemOpacity ?? 1; z: PathView.itemDepth ?? 0
                rotation: carousel.wheel ? (PathView.itemAngle ?? 0) : 0
                transform: Rotation {
                    origin.x: card.width / 2; origin.y: card.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: carousel.wheel ? 0 : (card.PathView.itemAngle ?? 0)
                }
                onActivated: index => browser.activated(index)
                onHoverMoved: (index, position) => browser.movePathPointer(position)
              }
            }
            CouchWheelPath {
                id: wheelPath
                viewportWidth: carousel.width; viewportHeight: carousel.height
            }
            CouchCoverFlowPath {
                id: flowPath
                viewportWidth: carousel.width; viewportHeight: carousel.height
            }
    }
}
