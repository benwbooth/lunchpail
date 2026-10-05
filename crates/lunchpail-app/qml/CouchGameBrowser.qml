pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: browser
    required property var library
    required property color background
    required property color panel
    required property color panelRaised
    required property color ink
    required property color muted
    required property color accent
    required property color accentCool
    required property int cardRadius
    property string viewStyle: "wheel"
    property bool navigationActive: false
    property bool hoverSelectionEnabled: true
    property int currentIndex: 0
    property bool selectionPending: true
    property string reportedGameId: ""
    readonly property var currentItem: !selectionPending && presentation.item ? presentation.item.currentItem : null
    readonly property int count: presentation.item ? presentation.item.count : 0
    readonly property int columns: viewStyle === "wall" && presentation.item
                                   ? presentation.item.columnCount : 1
    signal currentGameChanged()
    signal cardActivated(int index)
    signal cardHovered(int index)
    CouchPointerSelection {
        id: pointerSelection
        enabled: browser.visible && browser.hoverSelectionEnabled
        onSelected: index => {
            if (index >= 0 && index < browser.count) {
                browser.currentIndex = index
                browser.cardHovered(index)
            }
        }
    }
    HoverHandler {
        onPointChanged: if (hovered) pointerSelection.observe(point.scenePosition)
        onHoveredChanged: if (!hovered) pointerSelection.forget()
    }
    function cancelPointerSelection() { pointerSelection.cancel() }

    function reportSelection() {
        const item = currentItem
        if (!item || item.index !== currentIndex || item.gameId === reportedGameId) return
        reportedGameId = item.gameId
        currentGameChanged()
    }

    function applySelection() {
        const item = presentation.item
        // PathView must create its first delegate before an index jump; keep
        // the requested selection independent of its initial index of zero.
        if (!item || (count > 0 && !item.currentItem
                      && (viewStyle === "wheel" || viewStyle === "album"))) return
        const requested = Math.max(0, Math.min(currentIndex, count - 1))
        const next = count > 0 ? requested : -1
        if (item.currentIndex !== next) item.currentIndex = next
        if (currentIndex !== next) currentIndex = next
        selectionPending = false
        Qt.callLater(reportSelection)
    }

    function positionViewAtIndex(index, mode) {
        if (presentation.item && index >= 0) {
            if (viewStyle === "wheel" || viewStyle === "album")
                applySelection()
            else
                presentation.item.positionViewAtIndex(index, mode)
        }
    }
    function positionViewAtBeginning() { positionViewAtIndex(0, ListView.Beginning) }
    function positionViewAtEnd() { positionViewAtIndex(count - 1, ListView.End) }
    function settleSelection() {
        if (!presentation.item || count <= 0 || viewStyle === "wheel" || viewStyle === "album") return
        presentation.item.forceLayout()
        positionViewAtIndex(currentIndex, ListView.Contain)
    }
    onWidthChanged: { pointerSelection.cancel(); Qt.callLater(settleSelection) }
    onHeightChanged: { pointerSelection.cancel(); Qt.callLater(settleSelection) }
    onCurrentIndexChanged: {
        pointerSelection.cancel()
        selectionPending = true
        applySelection()
    }
    onViewStyleChanged: pointerSelection.cancel()
    onCurrentItemChanged: Qt.callLater(reportSelection)

    Loader {
        id: presentation
        anchors.fill: parent
        active: browser.visible
        sourceComponent: browser.viewStyle === "wall" ? wall
                         : browser.viewStyle === "shelf" ? shelf : animatedPath
        onLoaded: {
            browser.selectionPending = true
            browser.reportedGameId = ""
            browser.applySelection()
            browser.positionViewAtIndex(browser.currentIndex, ListView.Center)
            Qt.callLater(browser.settleSelection)
            Qt.callLater(browser.reportSelection)
        }
    }
    Connections {
        target: presentation.item
        function onCurrentIndexChanged() {
            if (!browser.selectionPending && presentation.item && browser.currentIndex !== presentation.item.currentIndex)
                browser.currentIndex = presentation.item.currentIndex
        }
        function onCurrentItemChanged() {
            if (browser.selectionPending) Qt.callLater(browser.applySelection)
        }
    }

    Component {
        id: shelf
        CouchGameShelf {
            library: browser.library
            background: browser.background
            panel: browser.panel
            panelRaised: browser.panelRaised
            ink: browser.ink
            muted: browser.muted
            accent: browser.accent
            accentCool: browser.accentCool
            cardRadius: browser.cardRadius
            navigationActive: browser.navigationActive
            leftMargin: 70; rightMargin: 70
            onCardActivated: index => browser.cardActivated(index)
            onCardHoverMoved: (index, position) => pointerSelection.move(index, position)
            onCardHoverLeft: index => pointerSelection.leave(index)
        }
    }
    Component {
        id: wall
        MomentumGridView {
            id: grid
            VisibleArtworkPriority {
                libraryModel: browser.library
                view: grid
                viewId: "couch-wall"
            }
            objectName: "couchWallGrid"
            readonly property int columnCount: Math.max(3, Math.min(10, Math.floor(verticalContentWidth / 220)))
            model: browser.library
            cellWidth: verticalContentWidth / columnCount
            cellHeight: Math.max(120, Math.min(365, cellWidth * 1.42, height))
            clip: true
            cacheBuffer: height / 2
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 180
            ScrollBar.vertical: LbScrollBar { policy: ScrollBar.AsNeeded }
            delegate: CouchGameCard {
                library: browser.library
                width: grid.cellWidth - 12
                height: grid.cellHeight - 10
                selected: GridView.isCurrentItem
                ink: browser.ink
                muted: browser.muted
                accent: browser.accent
                panel: browser.panel
                onActivated: index => browser.cardActivated(index)
                onHoverMoved: (index, position) => pointerSelection.move(index, position)
                onHoverLeft: index => pointerSelection.leave(index)
            }
        }
    }
    Component {
        id: animatedPath
        PathView {
            id: carousel
            VisibleArtworkPriority {
                libraryModel: browser.library
                view: carousel
                viewId: "couch-path"
                artworkType: carousel.wheel ? "clear-logo" : "box-front"
            }
            readonly property bool wheel: browser.viewStyle === "wheel"
            model: browser.library
            clip: true
            pathItemCount: wheel ? 7 : 9
            cacheItemCount: 2
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 210
            snapMode: PathView.SnapToItem
            dragMargin: width
            flickDeceleration: 450
            path: wheel ? wheelPath : albumPath
            delegate: CouchGameCard {
                id: pathCard
                library: browser.library
                width: carousel.wheel ? carousel.width * 0.80 : Math.min(carousel.height * 0.68, carousel.width * 0.23)
                height: carousel.wheel ? Math.min(154, carousel.height * 0.205) : carousel.height * 0.93
                wheel: carousel.wheel
                selected: PathView.isCurrentItem
                ink: browser.ink
                muted: browser.muted
                accent: browser.accent
                panel: browser.panel
                scale: PathView.itemScale ?? 1
                opacity: PathView.itemOpacity ?? 1
                z: PathView.itemDepth ?? 0
                rotation: carousel.wheel ? (PathView.itemAngle ?? 0) : 0
                transform: Rotation {
                    origin.x: pathCard.width / 2
                    origin.y: pathCard.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: carousel.wheel ? 0 : (pathCard.PathView.itemAngle ?? 0)
                }
                onActivated: index => browser.cardActivated(index)
                onHoverMoved: (index, position) => pointerSelection.move(index, position)
                onHoverLeft: index => pointerSelection.leave(index)
            }
            Path {
                id: wheelPath
                startX: carousel.width * 0.85; startY: -80
                PathAttribute { name: "itemScale"; value: 0.48 }
                PathAttribute { name: "itemOpacity"; value: 0.15 }
                PathAttribute { name: "itemAngle"; value: -16 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathQuad { x: carousel.width * 0.43; y: carousel.height / 2
                    controlX: carousel.width * 0.4; controlY: carousel.height * 0.15 }
                PathPercent { value: 0.5 }
                PathAttribute { name: "itemScale"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }
                PathAttribute { name: "itemAngle"; value: 0 }
                PathAttribute { name: "itemDepth"; value: 10 }
                PathQuad { x: carousel.width * 0.85; y: carousel.height + 80
                    controlX: carousel.width * 0.4; controlY: carousel.height * 0.85 }
                PathAttribute { name: "itemScale"; value: 0.48 }
                PathAttribute { name: "itemOpacity"; value: 0.15 }
                PathAttribute { name: "itemAngle"; value: 16 }
                PathAttribute { name: "itemDepth"; value: 0 }
            }
            Path {
                id: albumPath
                startX: -carousel.width * 0.08; startY: carousel.height * 0.53
                PathAttribute { name: "itemScale"; value: 0.64 }
                PathAttribute { name: "itemOpacity"; value: 0.22 }
                PathAttribute { name: "itemAngle"; value: 60 }
                PathAttribute { name: "itemDepth"; value: 0 }
                PathLine { x: carousel.width * 0.33; y: carousel.height * 0.53 }
                PathPercent { value: 0.38 }
                PathAttribute { name: "itemScale"; value: 0.78 }
                PathAttribute { name: "itemOpacity"; value: 0.8 }
                PathAttribute { name: "itemAngle"; value: 55 }
                PathAttribute { name: "itemDepth"; value: 4 }
                PathLine { x: carousel.width * 0.5; y: carousel.height * 0.47 }
                PathPercent { value: 0.5 }
                PathAttribute { name: "itemScale"; value: 1 }
                PathAttribute { name: "itemOpacity"; value: 1 }
                PathAttribute { name: "itemAngle"; value: 0 }
                PathAttribute { name: "itemDepth"; value: 10 }
                PathLine { x: carousel.width * 0.67; y: carousel.height * 0.53 }
                PathPercent { value: 0.62 }
                PathAttribute { name: "itemScale"; value: 0.78 }
                PathAttribute { name: "itemOpacity"; value: 0.8 }
                PathAttribute { name: "itemAngle"; value: -55 }
                PathAttribute { name: "itemDepth"; value: 4 }
                PathLine { x: carousel.width * 1.08; y: carousel.height * 0.53 }
                PathAttribute { name: "itemScale"; value: 0.64 }
                PathAttribute { name: "itemOpacity"; value: 0.22 }
                PathAttribute { name: "itemAngle"; value: -60 }
                PathAttribute { name: "itemDepth"; value: 0 }
            }
        }
    }
}
