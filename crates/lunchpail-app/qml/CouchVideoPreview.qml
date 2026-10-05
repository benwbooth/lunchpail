import QtQuick
import QtQuick.Controls
import QtMultimedia

Rectangle {
    id: preview
    property url source: ""
    property bool active: false
    property bool muted: true
    property string label: "Gameplay preview"
    property bool paused: false
    property bool backgroundMode: false
    property string errorMessage: ""
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property int position: player.position
    readonly property int duration: player.duration
    signal muteRequested()
    signal fullscreenRequested(url source)
    color: backgroundMode ? "transparent" : "#060a10"; radius: backgroundMode ? 0 : 14; border.color: backgroundMode ? "transparent" : "#3b5063"; clip: true
    onSourceChanged: { paused = false; errorMessage = "" }
    onActiveChanged: { if (!active) player.pause(); else if (!paused) player.play() }
    onPausedChanged: { if (paused) player.pause(); else if (active) player.play() }

    VideoOutput {
        id: output
        anchors { fill: parent; margins: preview.backgroundMode ? 0 : 2; bottomMargin: preview.backgroundMode ? 0 : 46 }
        fillMode: VideoOutput.PreserveAspectFit
        opacity: preview.playing || preview.paused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }
    RetryingMediaPlayer {
        id: player
        source: preview.active ? preview.source : ""
        autoPlay: preview.active && !preview.paused
        activeAudioTrack: -1; audioOutput: null; videoOutput: output
        loops: MediaPlayer.Infinite
        onErrorOccurred: (error, message) => preview.errorMessage = message
    }
    PreviewAudioCompanion {
        videoSource: player.source; videoPosition: player.position
        previewPlaying: preview.playing; unmuted: !preview.muted
    }
    BusyIndicator {
        anchors.centerIn: output; width: 42; height: 42
        running: preview.active && !preview.errorMessage && player.mediaStatus === MediaPlayer.LoadingMedia
        visible: running
    }
    Text {
        anchors.centerIn: output; width: output.width - 40
        visible: !!preview.errorMessage
        text: "Preview unavailable"; color: "#a7b4c4"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter
    }
    Row {
        id: controls
        visible: !preview.backgroundMode
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        spacing: 8; height: 32
        Text {
            width: parent.width - 126; height: parent.height
            text: preview.label; color: "#9eadbd"; font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        LbToolButton {
            width: 34; height: 32; text: preview.paused ? "▶" : "Ⅱ"
            Accessible.name: preview.paused ? "Play preview" : "Pause preview"
            onClicked: preview.paused = !preview.paused
        }
        LbToolButton {
            width: 34; height: 32
            Accessible.name: preview.muted ? "Unmute all game videos" : "Mute all game videos"
            contentItem: SemanticIcon { name: preview.muted ? "mute" : "volume"; color: "#dbe6ee" }
            onClicked: preview.muteRequested()
        }
        LbToolButton {
            width: 34; height: 32
            Accessible.name: "Watch preview fullscreen"
            contentItem: SemanticIcon { name: "fullscreen"; color: "#dbe6ee" }
            onClicked: preview.fullscreenRequested(preview.source)
        }
    }
}
