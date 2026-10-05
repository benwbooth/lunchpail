pragma ComponentBehavior: Bound
import QtQuick

// Fixed-size slots keep the shelf stable while the selected cover lifts.
// Only the viewport requests artwork; delegates never trigger downloads.
MomentumListView {
    id: shelf
    required property var library
    required property color background
    required property color panel
    required property color panelRaised
    required property color ink
    required property color muted
    required property color accent
    required property color accentCool
    required property int cardRadius
    property bool navigationActive: false
    signal currentGameChanged()
    signal cardActivated(int index)
    signal cardHoverMoved(int index, point position)
    signal cardHoverLeft(int index)

    orientation: ListView.Horizontal
    spacing: 16
    clip: true
    reuseItems: true
    cacheBuffer: width * 0.5
    model: library
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 180
    preferredHighlightBegin: width * 0.18
    preferredHighlightEnd: width * 0.72
    highlightRangeMode: ListView.ApplyRange
    maximumFlickVelocity: 9000
    flickDeceleration: 2300
    snapMode: ListView.SnapToItem
    onCurrentIndexChanged: currentGameChanged()
    onCurrentItemChanged: currentGameChanged()

    VisibleArtworkPriority {
        libraryModel: shelf.library
        view: shelf
        viewId: "couch-shelf"
    }
    delegate: CouchGameCard {
        library: shelf.library
        width: Math.max(150, Math.min(245, shelf.height * 0.69))
        height: shelf.height - 12
        selected: ListView.isCurrentItem
        ink: shelf.ink; muted: shelf.muted; accent: shelf.accent; panel: shelf.panel
        onActivated: index => shelf.cardActivated(index)
        onHoverMoved: (index, position) => shelf.cardHoverMoved(index, position)
        onHoverLeft: index => shelf.cardHoverLeft(index)
    }
}
