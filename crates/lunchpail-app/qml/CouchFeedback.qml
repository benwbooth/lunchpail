import QtQuick
import QtMultimedia

Item {
    id: feedback
    property bool active: false
    property bool muted: false
    property real volume: 0.22
    readonly property string lastKind: policy.lastKind
    readonly property bool ready: effects.every(effect => effect.status === SoundEffect.Ready)
    readonly property var navigationEffects: [move, wheel, wall, flow, focus]
    readonly property var actionEffects: [confirm, back, switchView, enter, launch]
    readonly property var effects: navigationEffects.concat(actionEffects)
    readonly property var sounds: ({move, wheel, wall, flow, focus, confirm, back,
                                  "switch": switchView, enter, launch})
    signal played(string kind)
    CouchSoundPolicy { id: policy; active: feedback.active; muted: feedback.muted; volume: feedback.volume }
    function stop() { for (const effect of effects) effect.stop() }
    onActiveChanged: if (!active) stop()
    onMutedChanged: if (muted) stop()
    onVolumeChanged: if (volume <= 0) stop()
    function play(kind) {
        const effect = sounds[kind]
        if (!effect || effect.status !== SoundEffect.Ready || !policy.accept(kind, Date.now())) return false
        // Browsing may continue during a confirmation/transition sound. Short
        // navigation cues should not chop off those longer action tails.
        for (const navigation of navigationEffects) navigation.stop()
        if (!policy.isNavigation(kind))
            for (const action of actionEffects) action.stop()
        effect.play()
        played(kind)
        return true
    }
    SoundEffect { id: move; source: "qrc:/couch-sounds/move.wav"; volume: feedback.volume }
    SoundEffect { id: wheel; source: "qrc:/couch-sounds/wheel.wav"; volume: feedback.volume }
    SoundEffect { id: wall; source: "qrc:/couch-sounds/wall.wav"; volume: feedback.volume }
    SoundEffect { id: flow; source: "qrc:/couch-sounds/flow.wav"; volume: feedback.volume }
    SoundEffect { id: focus; source: "qrc:/couch-sounds/focus.wav"; volume: feedback.volume }
    SoundEffect { id: confirm; source: "qrc:/couch-sounds/confirm.wav"; volume: feedback.volume }
    SoundEffect { id: back; source: "qrc:/couch-sounds/back.wav"; volume: feedback.volume }
    SoundEffect { id: switchView; source: "qrc:/couch-sounds/switch.wav"; volume: feedback.volume }
    SoundEffect { id: enter; source: "qrc:/couch-sounds/enter.wav"; volume: feedback.volume }
    SoundEffect { id: launch; source: "qrc:/couch-sounds/launch.wav"; volume: feedback.volume }
}
