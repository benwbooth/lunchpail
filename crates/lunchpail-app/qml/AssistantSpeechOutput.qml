import QtQuick
import QtTextToSpeech

Item {
    id: output
    property var config: ({})
    property bool allowed: true
    property bool queued: false
    readonly property bool speaking: queued || tts.state === TextToSpeech.Speaking || tts.state === TextToSpeech.Paused
    readonly property var engines: tts.availableEngines().filter(name => name !== "mock")
    property string requestedEngine: ""
    property var voiceNames: []
    property string error: ""
    signal finished()
    function refreshVoices() {
        const voices = tts.availableVoices()
        voiceNames = voices.map(v => v.name)
        const selected = voices.find(v => v.name === (config.voice || ""))
        if (selected) tts.voice = selected
        if (tts.state === TextToSpeech.Error) error = "Speech playback unavailable: " + tts.errorString()
        else if (voices.length) error = ""
    }
    function say(text) {
        if (!allowed || config.spoken_replies === false || !text.trim().length) return
        error = ""
        tts.stop()
        if (!engines.length) { error = "No system speech voice is installed. Captions remain available."; return }
        queued = true
        startTimeout.restart()
        tts.say(text)
    }
    function test() { say("Hello! I'm Lunchpail. What would you like to play?") }
    function stop() { queued = false; startTimeout.stop(); tts.stop() }
    onAllowedChanged: if (!allowed) stop()
    onConfigChanged: {
        const desired = config.voice_engine || ""
        if (desired !== requestedEngine) { requestedEngine = desired; tts.engine = desired }
        refreshVoices()
        if (config.spoken_replies === false) stop()
    }
    Component.onCompleted: refreshVoices()
    Timer { id: startTimeout; interval: 4000; onTriggered: { output.queued = false; if (tts.state !== TextToSpeech.Speaking) output.error = "System voice did not start. Choose another voice or check your speech service." } }
    TextToSpeech {
        id: tts
        rate: output.config.voice_rate || 0
        volume: output.config.voice_volume === undefined ? 0.85 : output.config.voice_volume
        onEngineChanged: output.refreshVoices()
        onStateChanged: (state) => {
            if (state === TextToSpeech.Ready) output.refreshVoices()
            if (state === TextToSpeech.Speaking) { output.queued = false; startTimeout.stop() }
            if (state === TextToSpeech.Ready && !output.queued) output.finished()
        }
        onErrorOccurred: (reason, message) => { output.queued = false; startTimeout.stop(); output.error = "Speech playback unavailable: " + message; output.finished() }
    }
}
