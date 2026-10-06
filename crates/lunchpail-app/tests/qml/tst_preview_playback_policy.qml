import QtQuick
import QtMultimedia
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "PreviewPlaybackPolicy"
    when: windowShown
    width: 320
    height: 180
    visible: true

    readonly property url fixture: Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
    property bool muted: false
    property bool startDetailsOnLoad: false
    property bool overlapObserved: false

    function checkOverlap() {
        if ((details.playbackState === MediaPlayer.PlayingState
             && grid.playbackState === MediaPlayer.PlayingState)
                || (detailsSound.audioSource.toString().length > 0
                    && gridSound.audioSource.toString().length > 0))
            overlapObserved = true
    }

    Lunchpail.PreviewPlaybackPolicy { id: policy }
    VideoOutput { id: detailsOutput; anchors.fill: parent }
    VideoOutput { id: gridOutput; anchors.fill: parent }

    Lunchpail.RetryingMediaPlayer {
        id: details
        playbackAllowed: policy.detailsAllowed
        activeAudioTrack: -1
        audioOutput: null
        videoOutput: detailsOutput
        loops: MediaPlayer.Infinite
        maximumRetries: 0
        onMediaStatusChanged: {
            if (test.startDetailsOnLoad && mediaStatus === MediaPlayer.LoadedMedia)
                play()
        }
        onPlaybackStateChanged: test.checkOverlap()
    }
    Lunchpail.RetryingMediaPlayer {
        id: grid
        playbackAllowed: policy.gridAllowed
        autoPlay: true
        activeAudioTrack: -1
        audioOutput: null
        videoOutput: gridOutput
        loops: MediaPlayer.Infinite
        maximumRetries: 0
        onPlaybackStateChanged: test.checkOverlap()
    }
    Lunchpail.PreviewAudioCompanion {
        id: detailsSound
        videoSource: details.source
        videoPosition: details.position
        previewPlaying: details.playbackState === MediaPlayer.PlayingState
        unmuted: !test.muted && policy.detailsAllowed
        volume: 0
        onAudioSourceChanged: test.checkOverlap()
    }
    Lunchpail.PreviewAudioCompanion {
        id: gridSound
        videoSource: grid.source
        videoPosition: grid.position
        previewPlaying: grid.playbackState === MediaPlayer.PlayingState
        unmuted: !test.muted && policy.gridAllowed
        volume: 0
        onAudioSourceChanged: test.checkOverlap()
    }
    SignalSpy { id: detailsSourceSpy; target: details.player; signalName: "sourceChanged" }

    function init() {
        startDetailsOnLoad = false
        muted = false
        policy.suspended = false
        policy.fullscreenOpen = false
        policy.desktopActive = true
        policy.detailsVisible = true
        policy.gridRequested = false
        details.source = fixture
        grid.source = fixture
        tryCompare(details, "mediaStatus", MediaPlayer.LoadedMedia, 5000)
        tryCompare(grid, "mediaStatus", MediaPlayer.LoadedMedia, 5000)
        details.position = 2500
        overlapObserved = false
        detailsSourceSpy.clear()
    }

    function cleanup() {
        startDetailsOnLoad = false
        policy.suspended = true
        details.stop()
        grid.stop()
        details.source = ""
        grid.source = ""
        tryCompare(details, "mediaStatus", MediaPlayer.NoMedia)
        tryCompare(grid, "mediaStatus", MediaPlayer.NoMedia)
        compare(detailsSound.audioSource.toString(), "")
        compare(gridSound.audioSource.toString(), "")
        verify(!overlapObserved, "Two video or audio decoders were active together")
    }

    function expectOwner(owner) {
        compare(policy.owner, owner)
        if (owner === "grid") {
            tryCompare(grid, "playbackState", MediaPlayer.PlayingState, 5000)
            verify(details.playbackState !== MediaPlayer.PlayingState)
            compare(detailsSound.audioSource.toString(), "")
            if (!muted)
                tryCompare(gridSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        } else if (owner === "details") {
            tryCompare(details, "playbackState", MediaPlayer.PlayingState, 5000)
            verify(grid.playbackState !== MediaPlayer.PlayingState)
            compare(gridSound.audioSource.toString(), "")
            if (!muted)
                tryCompare(detailsSound.player, "playbackState", MediaPlayer.PlayingState, 5000)
        } else {
            verify(details.playbackState !== MediaPlayer.PlayingState)
            verify(grid.playbackState !== MediaPlayer.PlayingState)
            compare(detailsSound.audioSource.toString(), "")
            compare(gridSound.audioSource.toString(), "")
        }
        verify(!overlapObserved)
    }

    function test_hover_preempts_details_and_restores_same_timeline() {
        details.play()
        expectOwner("details")
        for (let i = 0; i < 3; ++i) {
            policy.gridRequested = true
            expectOwner("grid")
            const pausedAt = details.position
            verify(pausedAt >= 2500)
            wait(160)
            compare(details.position, pausedAt)
            policy.gridRequested = false
            expectOwner("details")
            verify(details.position >= pausedAt)
            verify(!muted)
        }
        compare(detailsSourceSpy.count, 0, "Ownership must not reload the video")
    }

    function test_user_pause_is_preserved_data() {
        return [{ tag: "paused-before-hover", pauseDuringHover: false },
                { tag: "paused-during-hover", pauseDuringHover: true }]
    }

    function test_user_pause_is_preserved(data) {
        details.play()
        expectOwner("details")
        if (!data.pauseDuringHover)
            details.pause()
        policy.gridRequested = true
        expectOwner("grid")
        if (data.pauseDuringHover)
            details.pause()
        const pausedAt = details.position
        policy.gridRequested = false
        wait(200)
        compare(details.playbackState, MediaPlayer.PausedState)
        compare(details.position, pausedAt)
        compare(detailsSound.audioSource.toString(), "")
        verify(!muted)
    }

    function test_late_details_load_cannot_interrupt_hover() {
        details.source = ""
        policy.gridRequested = true
        expectOwner("grid")
        startDetailsOnLoad = true
        details.source = fixture
        tryCompare(details, "mediaStatus", MediaPlayer.LoadedMedia, 5000)
        wait(200)
        expectOwner("grid")
        verify(details.playbackRequested, "Remember the blocked load's play intent")
        policy.gridRequested = false
        expectOwner("details")
    }

    function test_fullscreen_preempts_grid_then_returns_ownership() {
        details.play()
        policy.gridRequested = true
        expectOwner("grid")
        policy.fullscreenOpen = true
        expectOwner("details")
        policy.fullscreenOpen = false
        expectOwner("grid")
        policy.gridRequested = false
        expectOwner("details")
    }

    function test_hidden_couch_and_running_game_suspend_desktop_players() {
        details.play()
        expectOwner("details")
        policy.detailsVisible = false
        expectOwner("")
        policy.detailsVisible = true
        expectOwner("details")
        policy.gridRequested = true
        expectOwner("grid")
        policy.desktopActive = false
        expectOwner("")
        policy.fullscreenOpen = true
        expectOwner("details")
        policy.suspended = true
        expectOwner("")
    }

    function test_mute_remains_independent_of_ownership() {
        muted = true
        details.play()
        expectOwner("details")
        policy.gridRequested = true
        expectOwner("grid")
        verify(muted)
        compare(gridSound.audioSource.toString(), "")
        muted = false
        expectOwner("grid")
        policy.gridRequested = false
        expectOwner("details")
        verify(!muted)
    }

    function test_explicit_pause_prevents_autoplay_reassertion() {
        policy.gridRequested = true
        expectOwner("grid")
        grid.pause()
        const pausedAt = grid.position
        grid.ensureAutoPlay()
        policy.fullscreenOpen = true
        policy.fullscreenOpen = false
        wait(200)
        compare(grid.playbackState, MediaPlayer.PausedState)
        compare(grid.position, pausedAt)
    }
}
