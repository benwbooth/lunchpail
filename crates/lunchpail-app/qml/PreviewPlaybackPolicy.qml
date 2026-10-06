import QtQuick

// Only one video surface may play. Hand ownership over break-before-make so
// the outgoing decoder and its audio stop before the incoming one can start.
QtObject {
    id: policy
    property bool desktopActive: true
    property bool detailsVisible: false
    property bool gridRequested: false
    property bool fullscreenOpen: false
    property bool suspended: false

    readonly property string owner: suspended ? ""
                                   : fullscreenOpen ? "details"
                                   : !desktopActive ? ""
                                   : gridRequested ? "grid"
                                   : detailsVisible ? "details" : ""
    property bool detailsAllowed: false
    property bool gridAllowed: false

    function applyOwner() {
        detailsAllowed = false
        gridAllowed = false
        if (owner === "details")
            detailsAllowed = true
        else if (owner === "grid")
            gridAllowed = true
    }

    onOwnerChanged: applyOwner()
    Component.onCompleted: applyOwner()
}
