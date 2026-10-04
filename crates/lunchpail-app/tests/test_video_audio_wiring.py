"""Guard the shared preference wiring in the full application QML."""
from pathlib import Path
import re
import unittest


class VideoAudioWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = (Path(__file__).resolve().parents[1] / "qml" / "Main.qml").read_text()

    def test_every_speaker_control_changes_the_same_preference(self):
        self.assertNotIn("hoverPreviewAudioMuted", self.qml)
        self.assertIn("unmuted: !root.videoAudioMuted", self.qml)
        self.assertEqual(
            re.findall(r"root\.videoAudioMuted\s*=\s*([^\n]+)", self.qml),
            ["!root.videoAudioMuted"] * 4,
        )
        self.assertNotIn("gameVideoAudio", self.qml)

    def test_unmute_cannot_reload_or_reconfigure_the_details_video(self):
        self.assertNotIn("enableAudio", self.qml)
        self.assertNotIn("reloadPipeline", self.qml)
        self.assertNotIn("unmuteResume", self.qml)
        player = self.qml.split("id: gameVideoPlayer", 1)[1].split("id: gameSoundtrackAudio", 1)[0]
        self.assertIn("activeAudioTrack: -1", player)
        self.assertIn("audioOutput: null", player)
        self.assertNotIn("videoAudioMuted", player)

    def test_details_sound_follows_video_without_controlling_it(self):
        sound = self.qml.split("id: gameVideoSound", 1)[1].split("RetryingMediaPlayer {", 1)[0]
        self.assertIn("videoSource: gameVideoPlayer.source", sound)
        self.assertIn("videoPosition: gameVideoPlayer.position", sound)
        self.assertIn("previewPlaying: gameVideoPlayer.playbackState === MediaPlayer.PlayingState", sound)
        self.assertIn("unmuted: !root.videoAudioMuted", sound)
        self.assertIn("volume: 0.45", sound)


if __name__ == "__main__":
    unittest.main()
