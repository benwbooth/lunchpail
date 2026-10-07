import QtQuick
import QtTest
import QtMultimedia
import "../../qml" as Lunchpail

// Run through test_audio_device_switch.py, which supplies an isolated audio
// server and changes only that server's default output at the READY markers.
TestCase {
    name: "AudioDeviceSwitch"
    when: windowShown
    MediaDevices { id: devices }
    Lunchpail.PreviewAudioCompanion {
        id: sound
        videoSource: Qt.resolvedUrl("../fixtures/video-audio-sync.mp4")
        previewPlaying: true
        unmuted: true
        volume: 0.34
    }
    Lunchpail.CouchFeedback { id: feedback }

    function checkRoute(description) {
        tryVerify(() => devices.defaultAudioOutput.description === description, 15000)
        tryCompare(sound.output, "device", devices.defaultAudioOutput, 5000)
        for (const effect of feedback.effects)
            compare(effect.audioDevice.id.toString(), devices.defaultAudioOutput.id.toString())
        compare(sound.volume, 0.34)
    }

    function test_active_and_muted_outputs_follow_device_changes() {
        checkRoute("Route_A")
        tryCompare(sound.player, "playbackState", MediaPlayer.PlayingState, 10000)
        console.log("AUDIO_ROUTE_READY_B")
        checkRoute("Route_B")
        compare(sound.player.playbackState, MediaPlayer.PlayingState)
        verify(!sound.audioMuted)
        console.log("AUDIO_ROUTE_VERIFY_B")
        // Let the driver verify the live PulseAudio stream, not just QML state.
        wait(4000)
        sound.unmuted = false
        compare(sound.audioSource.toString(), "")
        console.log("AUDIO_ROUTE_READY_A")
        checkRoute("Route_A")
        verify(sound.audioMuted)
        sound.unmuted = true
        tryCompare(sound.player, "playbackState", MediaPlayer.PlayingState, 10000)
        console.log("AUDIO_ROUTE_VERIFY_A")
        wait(4000)
    }
}
