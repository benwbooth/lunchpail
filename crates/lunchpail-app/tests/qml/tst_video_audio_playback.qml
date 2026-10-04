import QtQuick
import QtMultimedia
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "VideoAudioPlayback"
    when: windowShown
    width: 320
    height: 180
    visible: true

    readonly property url fixture: Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
    property bool muted: true
    property bool watchPosition: false
    property real lowestPosition: 0

    VideoOutput {
        id: output
        anchors.fill: parent
    }

    Lunchpail.RetryingMediaPlayer {
        id: video
        activeAudioTrack: -1
        audioOutput: null
        videoOutput: output
        loops: MediaPlayer.Infinite
        maximumRetries: 0
        onPositionChanged: {
            if (test.watchPosition)
                test.lowestPosition = Math.min(test.lowestPosition, position)
        }
    }

    Lunchpail.PreviewAudioCompanion {
        id: sound
        videoSource: video.source
        videoPosition: video.position
        previewPlaying: video.playbackState === MediaPlayer.PlayingState
        unmuted: !test.muted
        // Exercise the real audio decoder/output without playing a test tone
        // through the user's speakers.
        volume: 0
    }

    SignalSpy { id: sourceSpy; target: video.player; signalName: "sourceChanged" }
    SignalSpy { id: stateSpy; target: video.player; signalName: "playbackStateChanged" }
    SignalSpy { id: frameSpy; target: output.videoSink; signalName: "videoFrameChanged" }
    SignalSpy { id: errorSpy; target: sound; signalName: "playbackError" }

    function init() {
        watchPosition = false
        muted = true
        video.source = fixture
        tryCompare(video, "mediaStatus", MediaPlayer.LoadedMedia, 5000)
        verify(video.seekable)
        verify(video.duration >= 12000)
        video.position = 2500
        sourceSpy.clear()
        stateSpy.clear()
        frameSpy.clear()
        errorSpy.clear()
    }

    function cleanup() {
        watchPosition = false
        muted = true
        video.stop()
        video.source = ""
        tryCompare(video, "mediaStatus", MediaPlayer.NoMedia)
        compare(sound.audioSource.toString(), "")
        compare(errorSpy.count, 0)
    }

    function waitForSound() {
        tryCompare(sound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        verify(sound.player.hasAudio)
        verify(sound.player.seekable)
        tryVerify(function() {
            return Math.abs(sound.player.position - video.position) <= 550
        }, 3000)
    }

    function test_repeated_unmute_never_restarts_video() {
        video.play()
        tryVerify(function() { return video.position > 2800 && frameSpy.count > 2 }, 5000)
        const before = video.position
        lowestPosition = before
        watchPosition = true
        sourceSpy.clear()
        stateSpy.clear()
        const framesBefore = frameSpy.count

        for (let i = 0; i < 3; ++i) {
            muted = false
            waitForSound()
            wait(250)
            muted = true
            compare(sound.audioSource.toString(), "")
            wait(100)
        }

        verify(lowestPosition >= before, "Video timeline moved backwards on unmute")
        verify(video.position > before)
        verify(frameSpy.count > framesBefore)
        compare(sourceSpy.count, 0, "Mute changed the decoder's source")
        compare(stateSpy.count, 0, "Mute stopped or paused the video")
        compare(video.playbackState, MediaPlayer.PlayingState)
    }

    function test_unmute_while_paused_preserves_frame_and_position() {
        video.play()
        tryVerify(function() { return video.position > 2800 && frameSpy.count > 2 }, 5000)
        video.pause()
        tryCompare(video, "playbackState", MediaPlayer.PausedState)
        wait(100)
        const before = video.position
        sourceSpy.clear()
        stateSpy.clear()
        muted = false
        wait(350)
        compare(video.position, before)
        compare(video.playbackState, MediaPlayer.PausedState)
        compare(sound.audioSource.toString(), "")
        compare(sourceSpy.count, 0)
        compare(stateSpy.count, 0)

        video.play()
        waitForSound()
        verify(video.position >= before)
    }

    function test_sound_tracks_forward_and_backward_seeks() {
        video.play()
        muted = false
        waitForSound()
        video.position = 8500
        waitForSound()
        verify(sound.player.position >= 8000)
        video.position = 1500
        waitForSound()
        verify(sound.player.position < 2500)
        compare(sourceSpy.count, 0)
    }

    function test_sound_follows_video_loop() {
        video.play()
        muted = false
        waitForSound()
        video.position = video.duration - 400
        tryVerify(function() { return video.position < 2000 }, 5000)
        waitForSound()
        verify(sound.player.position < 2500)
        compare(sourceSpy.count, 0)
    }

    function test_closing_video_during_unmute_cancels_sound() {
        video.play()
        muted = false
        video.source = ""
        wait(300)
        compare(sound.audioSource.toString(), "")
        compare(sound.audioPlaybackState, MediaPlayer.StoppedState)
        compare(video.playbackState, MediaPlayer.StoppedState)
    }
}
