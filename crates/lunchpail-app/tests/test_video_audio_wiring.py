"""Guard independent global audio scopes in the full application QML."""
from pathlib import Path
import unittest


class VideoAudioWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = (Path(__file__).resolve().parents[1] / "qml" / "Main.qml").read_text()

    def test_every_speaker_control_changes_only_its_saved_scope(self):
        self.assertNotIn("hoverPreviewAudioMuted", self.qml)
        self.assertNotRegex(self.qml, r"root\.videoAudioMuted\s*=")
        for scope in ("grid", "details", "couch"):
            self.assertEqual(self.qml.count(f'videoAudioPreferences.toggle("{scope}")'), 1)
        self.assertIn("onClicked: videoAudioPreferences.toggle(root.gameVideoAudioScope)", self.qml)
        self.assertNotIn("id: gameVideoAudio", self.qml)

    def test_surfaces_read_their_separate_preferences(self):
        self.assertIn("readonly property bool gridVideoAudioMuted: videoAudioPreferences.gridMuted", self.qml)
        self.assertIn("readonly property bool detailsVideoAudioMuted: videoAudioPreferences.detailsMuted", self.qml)
        self.assertIn("unmuted: !root.gridVideoAudioMuted", self.qml)
        self.assertIn("unmuted: !root.gameVideoAudioMuted", self.qml)
        self.assertNotIn("videoAudioPreferences.normalMuted", self.qml)
        self.assertIn("videoMuted: videoAudioPreferences.couchMuted", self.qml)
        self.assertIn("VideoAudioPreferences { id: videoAudioPreferences }", self.qml)

    def test_fullscreen_and_assistant_preserve_the_originating_scope(self):
        self.assertIn("root.fullscreenVideoAudioScope = root.activeVideoAudioScope", self.qml)
        self.assertIn('root.fullscreenVideoAudioScope = "details"', self.qml)
        self.assertIn("videoAudioPreferences.setMuted(root.activeVideoAudioScope, action === \"mute\")", self.qml)

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
        self.assertIn("unmuted: !root.gameVideoAudioMuted", sound)
        self.assertIn("volume: root.hoverPreviewExclusiveProbe ? 0 : 0.45", sound)

    def test_video_decoders_and_sound_share_exclusive_playback_ownership(self):
        for player_id, sound_id, permission in (
            ("gameVideoPlayer", "gameVideoSound", "detailsAllowed"),
            ("hoverPreviewPlayer", "hoverPreviewSound", "gridAllowed"),
        ):
            player = self.qml.split(f"id: {player_id}", 1)[1].split("onSourceChanged:", 1)[0]
            self.assertIn(f"playbackAllowed: previewPlayback.{permission}", player)
            sound = self.qml.split(f"id: {sound_id}", 1)[1].split("RetryingMediaPlayer {", 1)[0]
            self.assertIn(f"&& previewPlayback.{permission}", sound)
        self.assertIn("fullscreenOpen: mediaFullscreen.opened", self.qml)
        self.assertIn("suspended: gameDetails.game_running", self.qml)


if __name__ == "__main__":
    unittest.main()
