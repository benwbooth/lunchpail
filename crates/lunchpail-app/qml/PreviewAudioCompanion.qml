import QtQuick
import QtMultimedia

// Videos stay on their silent players. Opening a separate audio-only decoder
// on demand avoids resetting a video sink when the user unmutes.
QtObject {
    id: companion

    property url videoSource: ""
    property int videoPosition: 0
    property bool previewPlaying: false
    property bool unmuted: false
    property alias volume: soundOutput.volume
    readonly property alias audioSource: audioPlayer.source
    readonly property alias audioPlaybackState: audioPlayer.playbackState
    readonly property alias audioMuted: soundOutput.muted
    signal playbackError(string message)

    onVideoPositionChanged: audioPlayer.syncPosition(false)

    property AudioOutput output: DefaultAudioOutput {
        id: soundOutput
        muted: !companion.unmuted
        volume: 0.34
    }

    property MediaPlayer player: MediaPlayer {
        id: audioPlayer
        property bool positionedForSource: false
        source: companion.unmuted && companion.previewPlaying
                ? companion.videoSource : ""
        audioOutput: soundOutput
        activeVideoTrack: -1
        loops: MediaPlayer.Infinite

        function syncPosition(force) {
            if (!companion.unmuted || !companion.previewPlaying || !seekable
                    || (!force && (!positionedForSource
                                  || playbackState !== MediaPlayer.PlayingState)))
                return
            const target = duration > 0
                         ? Math.min(Math.max(0, companion.videoPosition), duration)
                         : Math.max(0, companion.videoPosition)
            // Follow seeks and loop boundaries, but tolerate normal differences
            // between the two decoders' position-notification intervals.
            if (force || Math.abs(position - target) > 500)
                position = target
        }

        function startIfReady() {
            if (!companion.unmuted || !companion.previewPlaying
                    || source.toString().length === 0
                    || (mediaStatus !== MediaPlayer.LoadedMedia
                        && mediaStatus !== MediaPlayer.BufferedMedia))
                return
            if (!positionedForSource) {
                positionedForSource = true
                syncPosition(true)
            }
            if (playbackState !== MediaPlayer.PlayingState)
                play()
        }

        onSourceChanged: {
            positionedForSource = false
            if (source.toString().length === 0)
                stop()
            else
                Qt.callLater(startIfReady)
        }
        onMediaStatusChanged: startIfReady()
        onSeekableChanged: {
            if (audioPlayer.seekable && positionedForSource)
                syncPosition(true)
        }
        onErrorOccurred: function(error, errorString) {
            companion.playbackError(errorString)
        }
    }
}
