import QtQuick

QtObject {
    property bool active: false
    property bool muted: false
    property real volume: 0.22
    property double lastMove: -1000
    property double lastPlayed: -1000
    property string lastKind: ""
    function accept(kind, now) {
        if (!active || muted || volume <= 0
                || ["move", "confirm", "back", "switch", "enter", "launch"].indexOf(kind) < 0) return false
        if (kind === lastKind && now - lastPlayed < 65) return false
        if (kind === "move" && now - lastMove < 80) return false
        // A controller accept also emits a generic confirm: don't cut off launch.
        if (lastKind === "launch" && kind !== "back" && now - lastPlayed < 260) return false
        if (kind === "move") lastMove = now
        lastPlayed = now; lastKind = kind
        return true
    }
}
