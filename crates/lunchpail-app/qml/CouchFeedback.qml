import QtQuick
import QtMultimedia

Item {
    id: feedback
    property bool active: false
    property bool muted: false
    property real volume: 0.22
    readonly property string lastKind: policy.lastKind
    readonly property bool ready: move.status === SoundEffect.Ready
                                  && confirm.status === SoundEffect.Ready
                                  && back.status === SoundEffect.Ready
                                  && switchView.status === SoundEffect.Ready
                                  && enter.status === SoundEffect.Ready
                                  && launch.status === SoundEffect.Ready
    readonly property var effects: [move, confirm, back, switchView, enter, launch]
    signal played(string kind)
    CouchSoundPolicy { id: policy; active: feedback.active; muted: feedback.muted; volume: feedback.volume }
    function stop() { for (const effect of effects) effect.stop() }
    onActiveChanged: if (!active) stop()
    onMutedChanged: if (muted) stop()
    onVolumeChanged: if (volume <= 0) stop()
    function play(kind) {
        const effect = kind === "back" ? back : kind === "confirm" ? confirm
                     : kind === "switch" ? switchView : kind === "enter" ? enter
                     : kind === "launch" ? launch : move
        if (effect.status !== SoundEffect.Ready || !policy.accept(kind, Date.now())) return false
        stop()
        effect.play()
        played(kind)
        return true
    }
    SoundEffect { id: move; source: "qrc:/couch-sounds/move.wav"; volume: feedback.volume }
    SoundEffect { id: confirm; source: "qrc:/couch-sounds/confirm.wav"; volume: feedback.volume }
    SoundEffect { id: back; source: "qrc:/couch-sounds/back.wav"; volume: feedback.volume }
    SoundEffect { id: switchView; source: "qrc:/couch-sounds/switch.wav"; volume: feedback.volume }
    SoundEffect { id: enter; source: "qrc:/couch-sounds/enter.wav"; volume: feedback.volume }
    SoundEffect { id: launch; source: "qrc:/couch-sounds/launch.wav"; volume: feedback.volume }
}
