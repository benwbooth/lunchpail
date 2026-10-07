import QtQuick

// "listening" means the capture device is open, not that speech was heard.
// Hardware switches are often not exposed to the OS: report signal evidence,
// never assert that the physical microphone is muted.
QtObject {
    required property var speech
    readonly property bool silent: !!speech.listening && speech.input_silent === true
    readonly property bool hearingSpeech: !!speech.listening && !silent && speech.speech_active === true
    readonly property string label: silent ? "No input" : hearingSpeech ? "Hearing speech"
        : speech.listening ? "Mic idle" : "Mic off"
    readonly property string detail: silent ? "No audio input · Microphone may be muted or silent"
        : hearingSpeech ? "● Hearing speech · Speak naturally"
        : speech.listening ? "Mic on · Waiting for speech" : (speech.status || "Microphone off")
}
