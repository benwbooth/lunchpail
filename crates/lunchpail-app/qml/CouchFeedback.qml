import QtQuick
import QtMultimedia

Item {
    id: feedback
    property bool active: false
    property bool muted: false
    property real volume: 0.22
    property double lastMove: 0
    property double lastPlayed: 0
    property string lastKind: ""
    readonly property bool ready: move.status === SoundEffect.Ready
                                  && confirm.status === SoundEffect.Ready
                                  && back.status === SoundEffect.Ready
    signal played(string kind)
    function play(kind) {
        if (!active || muted || volume <= 0) return false
        const now = Date.now()
        if (kind === lastKind && now - lastPlayed < 55) return false
        if (kind === "move" && now - lastMove < 65) return false
        if (kind === "move") lastMove = now
        const effect = kind === "back" ? back : kind === "confirm" ? confirm : move
        if (effect.status !== SoundEffect.Ready) return false
        effect.play()
        lastPlayed = now
        lastKind = kind
        played(kind)
        return true
    }
    SoundEffect { id: move; source: "qrc:/couch-sounds/move.wav"; volume: feedback.volume }
    SoundEffect { id: confirm; source: "qrc:/couch-sounds/confirm.wav"; volume: feedback.volume }
    SoundEffect { id: back; source: "qrc:/couch-sounds/back.wav"; volume: feedback.volume }
}
