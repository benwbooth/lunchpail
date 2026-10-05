import QtQuick

QtObject {
    property bool active: false
    property bool muted: false
    property real volume: 0.22
    property double lastMove: -1000
    property double lastPlayed: -1000
    property string lastKind: ""
    readonly property var navigationKinds: ["move", "wheel", "wall", "flow", "focus"]
    function isNavigation(kind) { return navigationKinds.indexOf(kind) >= 0 }
    function accept(kind, now) {
        if (!active || muted || volume <= 0
                || (!isNavigation(kind) && ["confirm", "back", "switch", "enter", "launch"].indexOf(kind) < 0)) return false
        if (kind === lastKind && now - lastPlayed < 65) return false
        if (isNavigation(kind) && now - lastMove < (kind === "wheel" ? 50 : 80)) return false
        // A controller accept also emits a generic confirm: don't cut off launch.
        if (lastKind === "launch" && kind !== "back" && now - lastPlayed < 260) return false
        if (isNavigation(kind)) lastMove = now
        lastPlayed = now; lastKind = kind
        return true
    }
}
